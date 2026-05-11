suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(readr)
})

find_project_root <- function() {
  candidates <- c(
    Sys.getenv("PROJECT_ROOT", unset = ""),
    getwd(),
    normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE)
  )

  for (candidate in candidates[nzchar(candidates)]) {
    if (file.exists(file.path(candidate, "config", "project_config.json"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Cannot find project root. Run from the project directory or set PROJECT_ROOT.")
}

project_root <- find_project_root()
tables_dir <- file.path(project_root, "output", "tables")
states_path <- file.path(project_root, "data", "processed", "curlew_states_decoded.csv")

trajectory_files <- list(
  trajectory = file.path(tables_dir, "14_trajectory_simulations.csv"),
  hourly_state = file.path(tables_dir, "14_trajectory_state_hourly.csv"),
  endpoints = file.path(tables_dir, "14_trajectory_endpoints.csv"),
  summary = file.path(tables_dir, "15_prediction_summary.csv"),
  endpoint_uncertainty = file.path(tables_dir, "15_endpoint_uncertainty.csv"),
  direction_comparison = file.path(tables_dir, "15_direction_comparison.csv")
)

state_palette <- c(
  "Stopover" = "#4c78a8",
  "Local activity" = "#59a14f",
  "Flight" = "#f28e2b",
  "Fast flight" = "#e15759"
)

percent_labels <- function(x) paste0(round(x * 100), "%")

make_state_metadata <- function(states_df = NULL) {
  if (is.null(states_df) || nrow(states_df) == 0 || !"state" %in% names(states_df)) {
    return(tibble(state = 1:4, state_label = names(state_palette)))
  }

  states_df |>
    filter(!is.na(state), !is.na(step)) |>
    group_by(state) |>
    summarise(mean_step = mean(step, na.rm = TRUE), .groups = "drop") |>
    arrange(mean_step) |>
    mutate(state_label = names(state_palette)[seq_len(n())])
}

ensure_state_labels <- function(df, meta, state_col = "state", label_col = "state_label") {
  if (is.null(df) || nrow(df) == 0 || !state_col %in% names(df)) return(df)

  label_map <- setNames(meta$state_label, as.character(meta$state))
  if (!label_col %in% names(df)) df[[label_col]] <- NA_character_
  missing_label <- is.na(df[[label_col]]) | !nzchar(as.character(df[[label_col]]))
  df[[label_col]][missing_label] <- unname(label_map[as.character(df[[state_col]][missing_label])])
  df[[label_col]][is.na(df[[label_col]])] <- paste("State", df[[state_col]][is.na(df[[label_col]])])
  df
}

empty_plot <- function(message) {
  plot.new()
  text(0.5, 0.5, message)
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

read_prediction_cache <- function(meta) {
  needed <- unlist(trajectory_files[c("trajectory", "hourly_state", "endpoints")], use.names = FALSE)
  if (!all(file.exists(needed))) return(NULL)

  out <- list(
    trajectory = read_csv(trajectory_files$trajectory, show_col_types = FALSE),
    hourly_state = read_csv(trajectory_files$hourly_state, show_col_types = FALSE),
    endpoints = read_csv(trajectory_files$endpoints, show_col_types = FALSE)
  )

  if (file.exists(trajectory_files$summary)) {
    out$summary <- read_csv(trajectory_files$summary, show_col_types = FALSE)
  }
  if (file.exists(trajectory_files$endpoint_uncertainty)) {
    out$endpoint_uncertainty <- read_csv(trajectory_files$endpoint_uncertainty, show_col_types = FALSE)
  }
  if (file.exists(trajectory_files$direction_comparison)) {
    out$direction_comparison <- read_csv(trajectory_files$direction_comparison, show_col_types = FALSE)
  }

  out$trajectory <- ensure_state_labels(out$trajectory, meta, "state", "state_label")
  out$hourly_state <- ensure_state_labels(out$hourly_state, meta, "state", "state_label")
  out$endpoints <- ensure_state_labels(out$endpoints, meta, "final_state", "final_state_label")
  out
}

build_transition_table <- function(states_df, meta) {
  transition_path <- file.path(tables_dir, "08_transition_matrix.csv")

  if (file.exists(transition_path) && file.info(transition_path)$size > 0) {
    mat <- suppressMessages(read_csv(transition_path, show_col_types = FALSE))
    mat <- as.data.frame(mat)
    if (nrow(mat) > 0 && ncol(mat) > 0) {
      if (!any(names(mat) %in% c("from_state", "state"))) mat$from_state <- seq_len(nrow(mat))
      names(mat) <- make.names(names(mat), unique = TRUE)
      from_col <- if ("from_state" %in% names(mat)) "from_state" else names(mat)[[ncol(mat)]]
      state_cols <- setdiff(names(mat), from_col)

      return(bind_rows(lapply(state_cols, function(col) {
        tibble(
          from_state = suppressWarnings(as.integer(mat[[from_col]])),
          to_state = suppressWarnings(as.integer(gsub("[^0-9]", "", col))),
          probability = suppressWarnings(as.numeric(mat[[col]]))
        )
      })) |>
        filter(!is.na(from_state), !is.na(to_state)) |>
        left_join(meta |> select(from_state = state, from_label = state_label), by = "from_state") |>
        left_join(meta |> select(to_state = state, to_label = state_label), by = "to_state") |>
        select(from_label, to_label, probability))
    }
  }

  if (nrow(states_df) == 0) return(tibble())

  df <- states_df |>
    filter(!is.na(state)) |>
    arrange(ID, ts) |>
    group_by(ID) |>
    mutate(to_state = lead(state)) |>
    ungroup() |>
    filter(!is.na(to_state))

  df |>
    count(state, to_state, name = "n") |>
    group_by(state) |>
    mutate(probability = n / sum(n)) |>
    ungroup() |>
    left_join(meta |> select(state, from_label = state_label), by = "state") |>
    left_join(meta |> select(to_state = state, to_label = state_label), by = "to_state") |>
    select(from_label, to_label, probability)
}

states_data <- read_states()
state_meta <- make_state_metadata(states_data)
prediction_cache <- read_prediction_cache(state_meta)
transition_table <- build_transition_table(states_data, state_meta)

available_ids <- if (nrow(states_data) > 0) {
  ids <- sort(unique(states_data$original_id))
  if (length(ids) == 0) sort(unique(states_data$ID)) else ids
} else {
  character()
}

date_limits <- if (nrow(states_data) > 0 && "ts" %in% names(states_data)) {
  range(as.Date(states_data$ts), na.rm = TRUE)
} else {
  c(Sys.Date() - 30, Sys.Date())
}

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { background: #f7f8fa; color: #1f2933; }
      .app-title { margin: 18px 0 4px; font-weight: 700; }
      .panel { background: #ffffff; border: 1px solid #dde3ea; border-radius: 8px; padding: 14px; margin-bottom: 14px; }
      .summary-number { font-size: 24px; font-weight: 700; line-height: 1.1; }
      .summary-label { color: #667085; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
    "))
  ),
  titlePanel(div(class = "app-title", "Curlew Results Viewer")),
  fluidRow(
    column(
      width = 12,
      div(
        class = "panel",
        div(class = "summary-label", "Read-only status"),
        textOutput("status")
      )
    )
  ),
  tabsetPanel(
    tabPanel(
      "Observed Tracks",
      fluidRow(
        column(
          width = 3,
          div(
            class = "panel",
            selectInput("obs_id", "Individual", choices = available_ids, selected = if (length(available_ids) > 0) available_ids[[1]] else NULL),
            dateRangeInput("obs_dates", "Date range", start = date_limits[[1]], end = date_limits[[2]], min = date_limits[[1]], max = date_limits[[2]]),
            selectInput(
              "obs_color",
              "Map color",
              choices = c("State" = "state_label", "NDVI" = "ndvi", "Wind support" = "wind_support", "Temperature" = "temp_C"),
              selected = "state_label"
            )
          ),
          div(class = "panel", div(class = "summary-label", "Observed points"), div(class = "summary-number", textOutput("obs_n", inline = TRUE)))
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
      "Predicted Tracks",
      fluidRow(
        column(
          width = 3,
          div(class = "panel", div(class = "summary-label", "Cached simulations"), div(class = "summary-number", textOutput("sim_count", inline = TRUE))),
          div(class = "panel", div(class = "summary-label", "Mean total distance"), div(class = "summary-number", textOutput("mean_distance", inline = TRUE))),
          div(class = "panel", div(class = "summary-label", "Cache files"), textOutput("cache_files"))
        ),
        column(
          width = 9,
          fluidRow(
            column(width = 5, div(class = "panel", plotOutput("final_state_plot", height = "260px"))),
            column(width = 7, div(class = "panel", plotOutput("pred_hourly_plot", height = "260px")))
          ),
          div(class = "panel", leafletOutput("pred_map", height = "560px")),
          div(class = "panel", tableOutput("pred_endpoint_table"))
        )
      )
    ),
    tabPanel(
      "Model Notes",
      div(
        class = "panel",
        tags$h4("How to read this page"),
        tags$p("This is a read-only viewer. It only loads existing outputs and never runs preprocessing, HMM fitting, trajectory simulation, or cache rebuilding."),
        tags$p("Observed Tracks visualizes decoded historical GPS/HMM states. Predicted Tracks visualizes cached simulated trajectories from output/tables/14_*.csv."),
        tags$p("Predicted trajectories are probabilistic movement envelopes. The endpoint cloud and state probabilities should be interpreted as uncertainty, not a single deterministic route."),
        tags$p("If predicted tracks are missing, run the prediction pipeline separately, then reopen this viewer.")
      )
    )
  )
)

server <- function(input, output, session) {
  output$status <- renderText({
    cache_msg <- if (is.null(prediction_cache)) {
      "Prediction cache missing: output/tables/14_*.csv not fully available."
    } else {
      "Prediction cache loaded."
    }

    paste("Project root:", project_root, "|", cache_msg)
  })

  observed_filtered <- reactive({
    req(nrow(states_data) > 0, input$obs_id, input$obs_dates)
    id_col <- if ("original_id" %in% names(states_data)) "original_id" else "ID"

    states_data |>
      filter(
        .data[[id_col]] == input$obs_id,
        as.Date(ts) >= input$obs_dates[[1]],
        as.Date(ts) <= input$obs_dates[[2]]
      )
  })

  output$obs_n <- renderText(nrow(observed_filtered()))

  output$observed_map <- renderLeaflet({
    df <- observed_filtered()
    if (nrow(df) == 0) return(leaflet() |> addProviderTiles(providers$CartoDB.Positron))
    df <- ensure_state_labels(df, state_meta, "state", "state_label")

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
    if (nrow(df) == 0) return(empty_plot("No observed points."))
    df <- ensure_state_labels(df, state_meta, "state", "state_label")
    ggplot(df, aes(x = state_label, fill = state_label)) +
      geom_bar(show.legend = FALSE) +
      scale_fill_manual(values = state_palette, na.value = "#9ca3af") +
      labs(x = NULL, y = "Points", title = "Observed state counts") +
      theme_minimal(base_size = 12)
  })

  output$observed_timeline_plot <- renderPlot({
    df <- observed_filtered()
    if (nrow(df) == 0) return(empty_plot("No observed points."))
    df <- ensure_state_labels(df, state_meta, "state", "state_label")
    ggplot(df, aes(x = ts, y = state_label, color = state_label)) +
      geom_point(size = 0.8, alpha = 0.8, show.legend = FALSE) +
      scale_color_manual(values = state_palette, na.value = "#9ca3af") +
      labs(x = NULL, y = NULL, title = "State sequence through time") +
      theme_minimal(base_size = 12)
  })

  output$transition_table <- renderTable({
    if (nrow(transition_table) == 0) return(tibble(note = "Transition matrix not available."))
    transition_table |>
      mutate(probability = round(probability, 3)) |>
      arrange(from_label, to_label)
  })

  output$sim_count <- renderText({
    if (is.null(prediction_cache)) return("0")
    nrow(prediction_cache$endpoints)
  })

  output$mean_distance <- renderText({
    if (is.null(prediction_cache)) return("NA")
    if ("summary" %in% names(prediction_cache)) {
      total <- prediction_cache$summary |> filter(metric == "total_distance_km") |> slice(1)
      return(paste0(round(total$mean[[1]], 1), " km"))
    }
    paste0(round(mean(prediction_cache$endpoints$total_distance_km, na.rm = TRUE), 1), " km")
  })

  output$cache_files <- renderText({
    required <- c("trajectory", "hourly_state", "endpoints")
    optional <- setdiff(names(trajectory_files), required)
    found <- names(trajectory_files)[file.exists(unlist(trajectory_files))]
    missing_required <- required[!file.exists(unlist(trajectory_files[required]))]
    missing_optional <- optional[!file.exists(unlist(trajectory_files[optional]))]
    paste(
      "Found:", paste(found, collapse = ", "),
      "| Missing required:", paste(missing_required, collapse = ", "),
      "| Missing optional:", paste(missing_optional, collapse = ", ")
    )
  })

  output$final_state_plot <- renderPlot({
    if (is.null(prediction_cache)) return(empty_plot("No prediction cache."))
    endpoints <- ensure_state_labels(prediction_cache$endpoints, state_meta, "final_state", "final_state_label")
    ggplot(endpoints, aes(x = final_state_label, fill = final_state_label)) +
      geom_bar(show.legend = FALSE) +
      scale_fill_manual(values = state_palette, na.value = "#9ca3af") +
      labs(x = NULL, y = "Endpoint count", title = "Final simulated state") +
      theme_minimal(base_size = 12)
  })

  output$pred_hourly_plot <- renderPlot({
    if (is.null(prediction_cache)) return(empty_plot("No prediction cache."))
    hourly <- ensure_state_labels(prediction_cache$hourly_state, state_meta, "state", "state_label")
    ggplot(hourly, aes(x = hour, y = probability, color = state_label)) +
      geom_line(linewidth = 0.8) +
      scale_color_manual(values = state_palette, na.value = "#9ca3af") +
      scale_y_continuous(labels = percent_labels, limits = c(0, 1)) +
      labs(x = "Hour", y = "Simulated state probability", color = NULL, title = "State probabilities over time") +
      theme_minimal(base_size = 12)
  })

  output$pred_map <- renderLeaflet({
    if (is.null(prediction_cache)) return(leaflet() |> addProviderTiles(providers$CartoDB.Positron))
    sim <- ensure_state_labels(prediction_cache$trajectory, state_meta, "state", "state_label")
    endpoints <- ensure_state_labels(prediction_cache$endpoints, state_meta, "final_state", "final_state_label")
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
    if (is.null(prediction_cache)) return(tibble(note = "No prediction cache."))
    if ("summary" %in% names(prediction_cache)) {
      return(
        prediction_cache$summary |>
          mutate(across(where(is.numeric), ~ round(.x, 3))) |>
          select(route_direction, metric, n_sims, mean, variance, sd, ci95_low, ci95_high, pi95_low, pi95_high)
      )
    }
    prediction_cache$endpoints |>
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
