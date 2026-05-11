suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(readr)
})

project_root <- if (file.exists(file.path(getwd(), "config", "project_config.json"))) {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
} else {
  env_root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(env_root) && file.exists(file.path(env_root, "config", "project_config.json"))) {
    normalizePath(env_root, winslash = "/", mustWork = TRUE)
  } else {
    stop("Cannot find project root. Run shiny::runApp() from the project directory, or set PROJECT_ROOT.")
  }
}

Sys.setenv(PROJECT_ROOT = project_root)
setwd(project_root)

tables_dir <- file.path(project_root, "output", "tables")
states_path <- file.path(project_root, "data", "processed", "curlew_states_decoded.csv")

cache_paths <- list(
  trajectory = file.path(tables_dir, "14_trajectory_simulations.csv"),
  hourly_state = file.path(tables_dir, "14_trajectory_state_hourly.csv"),
  endpoints = file.path(tables_dir, "14_trajectory_endpoints.csv")
)

source(file.path(project_root, "R", "13_predict_flight_state.R"))
source(file.path(project_root, "R", "14_simulate_flight_trajectory.R"))

state_palette <- c(
  "Stopover" = "#4c78a8",
  "Local activity" = "#59a14f",
  "Flight" = "#f28e2b",
  "Fast flight" = "#e15759"
)

percent_labels <- function(x) paste0(round(x * 100), "%")

ensure_state_labels <- function(df, meta, state_col = "state", label_col = "state_label") {
  if (is.null(df) || nrow(df) == 0) return(df)
  if (!state_col %in% names(df)) return(df)

  if (label_col %in% names(df) && any(!is.na(df[[label_col]]))) {
    return(df)
  }

  label_map <- setNames(meta$state_label, as.character(meta$state))
  df[[label_col]] <- unname(label_map[as.character(df[[state_col]])])
  df[[label_col]][is.na(df[[label_col]])] <- paste("State", df[[state_col]][is.na(df[[label_col]])])
  df
}

cache_ready <- function() {
  all(file.exists(unlist(cache_paths, use.names = FALSE)))
}

read_cache <- function() {
  meta <- make_state_metadata(read_states())
  out <- list(
    trajectory = read_csv(cache_paths$trajectory, show_col_types = FALSE),
    hourly_state = read_csv(cache_paths$hourly_state, show_col_types = FALSE),
    endpoints = read_csv(cache_paths$endpoints, show_col_types = FALSE)
  )
  out$trajectory <- ensure_state_labels(out$trajectory, meta, "state", "state_label")
  out$hourly_state <- ensure_state_labels(out$hourly_state, meta, "state", "state_label")
  out$endpoints <- ensure_state_labels(out$endpoints, meta, "final_state", "final_state_label")
  out
}

read_prediction_cache <- function() {
  pred_path <- file.path(tables_dir, "13_state_prediction.csv")
  if (!file.exists(pred_path) || file.info(pred_path)$size == 0) return(NULL)
  ensure_state_labels(
    read_csv(pred_path, show_col_types = FALSE),
    make_state_metadata(read_states()),
    "state",
    "state_label"
  )
}

make_state_metadata <- function(states_df = NULL) {
  if (is.null(states_df) || nrow(states_df) == 0) {
    return(tibble(state = 1:4, state_label = names(state_palette)))
  }

  states_df |>
    filter(!is.na(state), !is.na(step)) |>
    group_by(state) |>
    summarise(mean_step = mean(step, na.rm = TRUE), .groups = "drop") |>
    arrange(mean_step) |>
    mutate(state_label = names(state_palette)[seq_len(n())])
}

read_states <- function() {
  if (!file.exists(states_path)) return(tibble())

  raw <- read_csv(states_path, show_col_types = FALSE) |>
    mutate(
      state = as.integer(state),
      ts = as.POSIXct(ts, tz = "UTC")
    )

  meta <- make_state_metadata(raw)
  raw |>
    select(-any_of("state_label")) |>
    left_join(meta |> select(state, state_label), by = "state") |>
    ensure_state_labels(meta, "state", "state_label")
}

read_transition_matrix <- function(meta) {
  transition_path <- file.path(tables_dir, "08_transition_matrix.csv")
  if (!file.exists(transition_path)) return(tibble())
  if (file.info(transition_path)$size == 0) return(tibble())

  mat <- suppressMessages(read_csv(transition_path, show_col_types = FALSE))
  if (nrow(mat) == 0 || ncol(mat) == 0) return(tibble())

  mat <- as.data.frame(mat)
  if (!any(names(mat) %in% c("from_state", "state"))) {
    mat$from_state <- seq_len(nrow(mat))
  }

  names(mat) <- make.names(names(mat), unique = TRUE)
  from_col <- if ("from_state" %in% names(mat)) "from_state" else names(mat)[[ncol(mat)]]
  state_cols <- setdiff(names(mat), from_col)

  out <- bind_rows(lapply(state_cols, function(col) {
    tibble(
      from_state = suppressWarnings(as.integer(mat[[from_col]])),
      to_state = suppressWarnings(as.integer(gsub("[^0-9]", "", col))),
      probability = suppressWarnings(as.numeric(mat[[col]]))
    )
  })) |>
    filter(!is.na(from_state), !is.na(to_state)) |>
    left_join(meta |> select(from_state = state, from_label = state_label), by = "from_state") |>
    left_join(meta |> select(to_state = state, to_label = state_label), by = "to_state") |>
    select(from_label, to_label, probability)

  out
}

run_r_step <- function(path) {
  source(file.path(project_root, path), local = new.env(parent = globalenv()))
}

run_python_step <- function(path, args = character()) {
  python_bin <- Sys.which("python")
  if (!nzchar(python_bin)) {
    stop("Python executable not found on PATH. Cannot run ", path)
  }

  status <- system2(
    python_bin,
    args = c(file.path(project_root, path), args),
    stdout = TRUE,
    stderr = TRUE
  )

  exit_status <- attr(status, "status")
  if (!is.null(exit_status) && exit_status != 0) {
    stop("Python step failed: ", path, "\n", paste(status, collapse = "\n"))
  }

  invisible(status)
}

ensure_prediction_cache <- function(progress = NULL) {
  if (cache_ready()) return("cache")

  step <- 0
  total <- 17
  tick <- function(label) {
    step <<- step + 1
    if (!is.null(progress)) {
      progress$set(value = step / total, message = "Cache missing: running full pipeline", detail = label)
    }
  }

  tick("A0 raw data check")
  run_r_step("R/02_check_raw.R")
  tick("A1 track cleaning")
  run_r_step("R/03_clean_tracking.R")
  tick("A2 track regularisation")
  run_r_step("R/04_regularize_tracks.R")
  tick("B1 ERA5 environment matching")
  run_python_step("py/05_match_era5.py", c("--project-root", project_root))
  tick("B2 NDVI matching")
  run_r_step("R/05b_match_ndvi.R")
  tick("C1 HMM input preparation")
  run_r_step("R/06_prepare_hmm_data.R")
  tick("C2 HMM fitting")
  run_r_step("R/07_fit_hmm_models.R")
  tick("C3 HMM state decoding")
  run_r_step("R/08_decode_hmm.R")
  tick("C4 adding NDVI to states")
  run_r_step("R/08b_add_ndvi_to_states.R")
  tick("D1 Levy and stopover detection")
  run_python_step("py/09_levy_stopovers.py", c("--project-root", project_root))
  tick("D2 stopover environment rebuild")
  run_r_step("R/09b_rebuild_stopovers_env.R")
  tick("D3 optimal stopping model")
  run_r_step("R/10_optimal_stopping.R")
  tick("D4 stopover sensitivity")
  run_r_step("R/10b_stopover_sensitivity.R")
  tick("E climate/resource scenario projection")
  run_r_step("R/11_climate_scenario_projection.R")
  tick("F SCVI ranking")
  run_r_step("R/12_scvi_conservation_value.R")
  tick("Prediction context")
  write_state_prediction_example()
  tick("Trajectory cache")
  write_trajectory_example()

  if (!cache_ready()) stop("Full pipeline finished but trajectory cache files were not created.")
  "rebuilt"
}

initial_cache <- if (cache_ready()) read_cache() else NULL
initial_prediction <- read_prediction_cache()
initial_states <- read_states()
initial_metadata <- make_state_metadata(initial_states)
initial_context <- if (file.exists(states_path)) {
  tryCatch(load_prediction_context(), error = function(e) NULL)
} else {
  NULL
}

default_row <- if (nrow(initial_states) > 0) {
  initial_states |>
    filter(!is.na(lon), !is.na(lat), !is.na(temp_C), !is.na(wind_support), !is.na(wind_speed)) |>
    slice_tail(n = 1)
} else {
  tibble(lon = 5.12657, lat = 50.91430, state = 2, temp_C = 25.3, wind_support = -0.53, wind_speed = 1.73, ndvi = 0.677)
}

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { background: #f7f8fa; color: #1f2933; }
      .app-title { margin: 18px 0 4px; font-weight: 700; }
      .panel { background: #ffffff; border: 1px solid #dde3ea; border-radius: 8px; padding: 14px; margin-bottom: 14px; }
      .summary-number { font-size: 24px; font-weight: 700; line-height: 1.1; }
      .summary-label { color: #667085; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
      .btn-primary { width: 100%; }
    "))
  ),
  titlePanel(div(class = "app-title", "Curlew Flight State and Trajectory App")),
  fluidRow(
    column(
      width = 12,
      div(
        class = "panel",
        div(class = "summary-label", "Pipeline Status"),
        textOutput("status"),
        checkboxInput("allow_rebuild", "Allow full pipeline rebuild", value = FALSE),
        actionButton("rebuild_cache", "Rebuild cache", class = "btn-primary")
      )
    )
  ),
  tabsetPanel(
    id = "main_tabs",
    tabPanel(
      "Observed Tracks",
      fluidRow(
        column(
          width = 3,
          div(
            class = "panel",
            selectInput("obs_id", "Individual", choices = character()),
            dateRangeInput("obs_dates", "Date range", start = Sys.Date() - 30, end = Sys.Date()),
            selectInput(
              "obs_color",
              "Map color",
              choices = c("State" = "state_label", "NDVI" = "ndvi", "Wind support" = "wind_support", "Temperature" = "temp_C"),
              selected = "state_label"
            )
          ),
          div(
            class = "panel",
            div(class = "summary-label", "Observed points"),
            div(class = "summary-number", textOutput("obs_n", inline = TRUE))
          )
        ),
        column(
          width = 9,
          div(class = "panel", leafletOutput("observed_map", height = "520px")),
          fluidRow(
            column(width = 6, div(class = "panel", plotOutput("observed_state_plot", height = "260px"))),
            column(width = 6, div(class = "panel", plotOutput("observed_timeline_plot", height = "260px")))
          ),
          div(class = "panel", tableOutput("transition_table"))
        )
      )
    ),
    tabPanel(
      "Prediction Simulator",
      fluidRow(
        column(
          width = 3,
          div(
            class = "panel",
            numericInput("pred_lon", "Current longitude", value = round(default_row$lon[[1]], 5), step = 0.01),
            numericInput("pred_lat", "Current latitude", value = round(default_row$lat[[1]], 5), step = 0.01),
            selectInput("pred_state", "Current state", choices = setNames(as.character(initial_metadata$state), initial_metadata$state_label), selected = as.character(default_row$state[[1]])),
            numericInput("pred_temp", "Temperature (C)", value = round(default_row$temp_C[[1]], 2), step = 0.5),
            numericInput("pred_wind_support", "Wind support", value = round(default_row$wind_support[[1]], 2), step = 0.1),
            numericInput("pred_wind_speed", "Wind speed", value = round(default_row$wind_speed[[1]], 2), step = 0.1),
            numericInput("pred_ndvi", "NDVI", value = if ("ndvi" %in% names(default_row)) round(default_row$ndvi[[1]], 3) else 0.5, step = 0.01, min = 0, max = 1),
            sliderInput("pred_horizon", "Simulation horizon (hours)", min = 6, max = 72, value = 24, step = 6),
            sliderInput("pred_sims", "Number of simulated tracks", min = 20, max = 500, value = 100, step = 20),
            numericInput("pred_seed", "Random seed", value = 42, step = 1),
            actionButton("run_prediction", "Predict and simulate", class = "btn-primary")
          )
        ),
        column(
          width = 9,
          fluidRow(
            column(width = 4, div(class = "panel", div(class = "summary-label", "Most likely next state"), div(class = "summary-number", textOutput("pred_top_state", inline = TRUE)))),
            column(width = 4, div(class = "panel", div(class = "summary-label", "Mean total distance"), div(class = "summary-number", textOutput("pred_mean_distance", inline = TRUE)))),
            column(width = 4, div(class = "panel", div(class = "summary-label", "Model source"), div(textOutput("pred_model_source", inline = TRUE))))
          ),
          fluidRow(
            column(width = 5, div(class = "panel", plotOutput("pred_prob_plot", height = "260px"))),
            column(width = 7, div(class = "panel", plotOutput("pred_hourly_plot", height = "260px")))
          ),
          div(class = "panel", leafletOutput("pred_map", height = "560px")),
          div(class = "panel", tableOutput("pred_endpoint_table"))
        )
      )
    ),
    tabPanel(
      "Model Notes",
      fluidRow(
        column(
          width = 12,
          div(
            class = "panel",
            tags$h4("How to read this app"),
            tags$p("Observed Tracks shows the historical GPS tracks after HMM state decoding. Prediction Simulator uses the existing decoded states and model outputs to simulate possible future movement envelopes from user-provided conditions."),
            tags$p("The predicted trajectories are probabilistic simulations, not deterministic forecasts. Multiple semi-transparent paths and endpoint clouds are more important than any single line."),
            tags$p("If output/tables/14_*.csv exists, the app renders cached prediction results immediately. If those files are missing, use Rebuild cache to run the full project pipeline manually."),
            tags$p("Current limitations: the sample size is small, wind_support is treated as a simplified user input, and the prediction layer should be described as exploratory scenario simulation.")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  states_data <- reactiveVal(initial_states)
  metadata <- reactiveVal(initial_metadata)
  transition_data <- reactiveVal(read_transition_matrix(initial_metadata))
  cache_data <- reactiveVal(initial_cache)
  context_data <- reactiveVal(initial_context)
  prediction_data <- reactiveVal(initial_prediction)
  simulation_data <- reactiveVal(initial_cache)
  boot_started <- reactiveVal(FALSE)

  status <- reactiveVal(if (cache_ready()) {
    "Trajectory cache found. Observed and cached prediction views are ready."
  } else {
    "Trajectory cache missing. Click Rebuild cache to run the full pipeline manually."
  })

  observeEvent(input$rebuild_cache, {
    if (!isTRUE(input$allow_rebuild)) {
      status("Rebuild blocked. Tick 'Allow full pipeline rebuild' first.")
      return()
    }
    if (boot_started()) return()
    boot_started(TRUE)

    withProgress(message = "Preparing trajectory cache", value = 0, {
      p <- shiny::Progress$new(session)
      on.exit({
        p$close()
        boot_started(FALSE)
      }, add = TRUE)
      result <- ensure_prediction_cache(progress = p)
      states <- read_states()
      meta <- make_state_metadata(states)
      states_data(states)
      metadata(meta)
      transition_data(read_transition_matrix(meta))
      cache_data(read_cache())
      context_data(load_prediction_context())
      prediction_data(read_prediction_cache())
      simulation_data(read_cache())
      status(paste("Pipeline finished via", result, "mode."))
    })
  }, ignoreInit = TRUE)

  observeEvent(states_data(), {
    states <- states_data()
    if (nrow(states) == 0) return()

    ids <- sort(unique(states$original_id))
    if (length(ids) == 0) ids <- sort(unique(states$ID))

    updateSelectInput(session, "obs_id", choices = ids, selected = ids[[1]])

    dates <- as.Date(states$ts)
    updateDateRangeInput(
      session,
      "obs_dates",
      start = min(dates, na.rm = TRUE),
      end = max(dates, na.rm = TRUE),
      min = min(dates, na.rm = TRUE),
      max = max(dates, na.rm = TRUE)
    )

    updateSelectInput(
      session,
      "pred_state",
      choices = setNames(as.character(metadata()$state), metadata()$state_label)
    )
  }, ignoreInit = FALSE)

  observed_filtered <- reactive({
    states <- states_data()
    req(nrow(states) > 0, input$obs_id, input$obs_dates)
    id_col <- if ("original_id" %in% names(states)) "original_id" else "ID"

    states |>
      filter(
        .data[[id_col]] == input$obs_id,
        as.Date(ts) >= input$obs_dates[[1]],
        as.Date(ts) <= input$obs_dates[[2]]
      )
  })

  output$status <- renderText(status())

  output$obs_n <- renderText({
    nrow(observed_filtered())
  })

  output$observed_map <- renderLeaflet({
    df <- observed_filtered()
    validate(need(nrow(df) > 0, "No observed points in this filter."))

    if (input$obs_color == "state_label") {
      pal <- colorFactor(state_palette, domain = names(state_palette))
      leaflet(df) |>
        addProviderTiles(providers$CartoDB.Positron) |>
        addPolylines(lng = ~lon, lat = ~lat, color = "#6b7280", weight = 1, opacity = 0.45) |>
        addCircleMarkers(lng = ~lon, lat = ~lat, radius = 3, stroke = FALSE, fillOpacity = 0.8, fillColor = ~pal(state_label), label = ~paste(state_label, ts)) |>
        addLegend(position = "bottomright", pal = pal, values = ~state_label, title = "State")
    } else {
      vals <- df[[input$obs_color]]
      pal <- colorNumeric("viridis", domain = vals, na.color = "#9ca3af")
      leaflet(df) |>
        addProviderTiles(providers$CartoDB.Positron) |>
        addPolylines(lng = ~lon, lat = ~lat, color = "#6b7280", weight = 1, opacity = 0.45) |>
        addCircleMarkers(lng = ~lon, lat = ~lat, radius = 3, stroke = FALSE, fillOpacity = 0.8, fillColor = pal(vals), label = ~paste(state_label, ts)) |>
        addLegend(position = "bottomright", pal = pal, values = vals, title = input$obs_color)
    }
  })

  output$observed_state_plot <- renderPlot({
    df <- observed_filtered()
    validate(need(nrow(df) > 0, "No observed points."))
    ggplot(df, aes(x = state_label, fill = state_label)) +
      geom_bar(show.legend = FALSE) +
      scale_fill_manual(values = state_palette, na.value = "#9ca3af") +
      labs(x = NULL, y = "Points", title = "Observed state counts") +
      theme_minimal(base_size = 12)
  })

  output$observed_timeline_plot <- renderPlot({
    df <- observed_filtered()
    validate(need(nrow(df) > 0, "No observed points."))
    ggplot(df, aes(x = ts, y = state_label, color = state_label)) +
      geom_point(size = 0.8, alpha = 0.8, show.legend = FALSE) +
      scale_color_manual(values = state_palette, na.value = "#9ca3af") +
      labs(x = NULL, y = NULL, title = "State sequence through time") +
      theme_minimal(base_size = 12)
  })

  output$transition_table <- renderTable({
    td <- transition_data()
    if (nrow(td) == 0) return(tibble(note = "Transition matrix table not available."))
    td |>
      mutate(probability = round(probability, 3)) |>
      arrange(from_label, to_label)
  })

  observeEvent(input$run_prediction, {
    req(context_data())
    withProgress(message = "Running prediction", value = 0, {
      incProgress(0.25, detail = "State probabilities")
      pred <- predict_flight_state(
        current_state = as.integer(input$pred_state),
        temp_C = input$pred_temp,
        wind_support = input$pred_wind_support,
        wind_speed = input$pred_wind_speed,
        ndvi = input$pred_ndvi,
        context = context_data()
      )
      pred <- ensure_state_labels(pred, metadata(), "state", "state_label")
      prediction_data(pred)

      incProgress(0.55, detail = "Trajectory simulation")
      sim <- simulate_flight_trajectory(
        start_lon = input$pred_lon,
        start_lat = input$pred_lat,
        current_state = as.integer(input$pred_state),
        temp_C = input$pred_temp,
        wind_support = input$pred_wind_support,
        wind_speed = input$pred_wind_speed,
        ndvi = input$pred_ndvi,
        horizon_hr = input$pred_horizon,
        n_sims = input$pred_sims,
        context = context_data(),
        seed = input$pred_seed
      )
      sim$trajectory <- ensure_state_labels(sim$trajectory, metadata(), "state", "state_label")
      sim$hourly_state <- ensure_state_labels(sim$hourly_state, metadata(), "state", "state_label")
      sim$endpoints <- ensure_state_labels(sim$endpoints, metadata(), "final_state", "final_state_label")
      simulation_data(sim)
    })
  }, ignoreInit = TRUE)

  output$pred_top_state <- renderText({
    if (!is.null(prediction_data())) {
      pred <- ensure_state_labels(prediction_data(), metadata(), "state", "state_label")
      return(pred$state_label[which.max(pred$probability)])
    }
    validate(need(!is.null(simulation_data()), "Click Predict and simulate"))
    simulation_data()$endpoints |>
      count(final_state_label, sort = TRUE) |>
      slice(1) |>
      pull(final_state_label)
  })

  output$pred_model_source <- renderText({
    if (!is.null(prediction_data())) return(unique(prediction_data()$model_source)[[1]])
    if (!is.null(simulation_data())) return("cached trajectory CSV")
    "Waiting for input"
  })

  output$pred_mean_distance <- renderText({
    validate(need(!is.null(simulation_data()), "Click Predict and simulate"))
    paste0(round(mean(simulation_data()$endpoints$total_distance_km, na.rm = TRUE), 1), " km")
  })

  output$pred_prob_plot <- renderPlot({
    validate(need(!is.null(prediction_data()), "No state probability cache yet. Click Predict and simulate."))
    pred <- ensure_state_labels(prediction_data(), metadata(), "state", "state_label")
    validate(need("state_label" %in% names(pred), "State labels are unavailable."))
    ggplot(pred, aes(x = reorder(state_label, probability), y = probability, fill = state_label)) +
      geom_col(width = 0.7, show.legend = FALSE) +
      coord_flip() +
      scale_fill_manual(values = state_palette, na.value = "#9ca3af") +
      scale_y_continuous(labels = percent_labels, limits = c(0, 1)) +
      labs(x = NULL, y = "Next-hour probability", title = "State prediction") +
      theme_minimal(base_size = 12)
  })

  output$pred_hourly_plot <- renderPlot({
    validate(need(!is.null(simulation_data()), "Click Predict and simulate"))
    ggplot(simulation_data()$hourly_state, aes(x = hour, y = probability, color = state_label)) +
      geom_line(linewidth = 0.8) +
      scale_color_manual(values = state_palette, na.value = "#9ca3af") +
      scale_y_continuous(labels = percent_labels, limits = c(0, 1)) +
      labs(x = "Hour", y = "Simulated state probability", color = NULL, title = "State probabilities over time") +
      theme_minimal(base_size = 12)
  })

  output$pred_map <- renderLeaflet({
    validate(need(!is.null(simulation_data()), "Click Predict and simulate"))
    sim <- simulation_data()$trajectory
    endpoints <- simulation_data()$endpoints
    pal <- colorFactor(state_palette, domain = names(state_palette))

    start_point <- sim |> filter(hour == min(hour, na.rm = TRUE)) |> slice(1)

    m <- leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addCircleMarkers(lng = start_point$lon[[1]], lat = start_point$lat[[1]], radius = 6, stroke = FALSE, fillOpacity = 1, fillColor = "#111827", label = "Start")

    sampled_ids <- sort(unique(sim$sim_id))
    if (length(sampled_ids) > 250) sampled_ids <- sample(sampled_ids, 250)

    for (sid in sampled_ids) {
      one <- sim |> filter(sim_id == sid) |> arrange(hour)
      m <- m |> addPolylines(data = one, lng = ~lon, lat = ~lat, color = "#2563eb", weight = 1, opacity = 0.18)
    }

    m |>
      addCircleMarkers(
        data = endpoints,
        lng = ~endpoint_lon,
        lat = ~endpoint_lat,
        radius = 3,
        stroke = FALSE,
        fillOpacity = 0.35,
        fillColor = ~pal(final_state_label),
        label = ~paste0("Final: ", final_state_label, "; distance: ", round(total_distance_km, 1), " km")
      ) |>
      addLegend(position = "bottomright", pal = pal, values = names(state_palette), title = "Final state")
  })

  output$pred_endpoint_table <- renderTable({
    validate(need(!is.null(simulation_data()), "Click Predict and simulate"))
    simulation_data()$endpoints |>
      summarise(
        simulations = n(),
        mean_endpoint_lon = round(mean(endpoint_lon, na.rm = TRUE), 4),
        mean_endpoint_lat = round(mean(endpoint_lat, na.rm = TRUE), 4),
        mean_total_distance_km = round(mean(total_distance_km, na.rm = TRUE), 1),
        median_total_distance_km = round(median(total_distance_km, na.rm = TRUE), 1)
      )
  })
}

shinyApp(ui, server)
