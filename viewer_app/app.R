suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(readr)
})

project_root <- "D:/migration_project"
states_path <- file.path(project_root, "data", "processed", "curlew_states_decoded.csv")
tables_dir <- file.path(project_root, "output", "tables")

trajectory_files <- list(
  trajectory = file.path(tables_dir, "14_trajectory_simulations.csv"),
  hourly_state = file.path(tables_dir, "14_trajectory_state_hourly.csv"),
  endpoints = file.path(tables_dir, "14_trajectory_endpoints.csv"),
  summary = file.path(tables_dir, "15_prediction_summary.csv"),
  endpoint_uncertainty = file.path(tables_dir, "15_endpoint_uncertainty.csv"),
  direction_comparison = file.path(tables_dir, "15_direction_comparison.csv")
)

read_states <- function() {
  validate_path <- file.exists(states_path)
  if (!validate_path) {
    return(tibble(state = integer(), state_label = character(), step = numeric()))
  }

  read_csv(states_path, show_col_types = FALSE) |>
    mutate(state = as.integer(state))
}

make_state_metadata <- function(states_df) {
  if (nrow(states_df) == 0) {
    return(tibble(state = 1:4, state_label = c("Stopover", "Local activity", "Flight", "Fast flight")))
  }

  ranked <- states_df |>
    filter(!is.na(state), !is.na(step)) |>
    group_by(state) |>
    summarise(mean_step = mean(step, na.rm = TRUE), .groups = "drop") |>
    arrange(mean_step)

  labels <- c("Stopover", "Local activity", "Flight", "Fast flight")
  ranked$state_label <- labels[seq_len(nrow(ranked))]
  ranked$state_label[is.na(ranked$state_label)] <- paste("State", ranked$state[is.na(ranked$state_label)])
  ranked
}

read_cached_simulation <- function() {
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
  out
}

build_fallback_prediction <- function(states_df, metadata) {
  if (nrow(states_df) == 0 || !"state" %in% names(states_df)) {
    return(tibble(
      state = metadata$state,
      state_label = metadata$state_label,
      probability = rep(1 / nrow(metadata), nrow(metadata))
    ))
  }

  current_state <- states_df |>
    filter(!is.na(state)) |>
    slice_tail(n = 1) |>
    pull(state)

  df <- states_df |>
    filter(!is.na(state)) |>
    arrange(ID, ts) |>
    group_by(ID) |>
    mutate(next_state = lead(state)) |>
    ungroup() |>
    filter(!is.na(next_state), state == current_state)

  counts <- df |> count(next_state, name = "n")
  probs <- rep(0, nrow(metadata))
  names(probs) <- as.character(metadata$state)

  if (nrow(counts) > 0) {
    probs[as.character(counts$next_state)] <- counts$n / sum(counts$n)
  } else {
    probs[] <- 1 / length(probs)
  }

  tibble(
    state = metadata$state,
    state_label = metadata$state_label,
    probability = as.numeric(probs[as.character(metadata$state)])
  )
}

states_df <- read_states()
metadata <- make_state_metadata(states_df)
ensure_state_labels <- function(df, state_col = "state", label_col = "state_label") {
  if (is.null(df) || nrow(df) == 0 || !state_col %in% names(df)) return(df)
  label_map <- setNames(metadata$state_label, as.character(metadata$state))
  if (!label_col %in% names(df)) df[[label_col]] <- NA_character_
  missing_label <- is.na(df[[label_col]]) | !nzchar(as.character(df[[label_col]]))
  df[[label_col]][missing_label] <- unname(label_map[as.character(df[[state_col]][missing_label])])
  df[[label_col]][is.na(df[[label_col]])] <- paste("State", df[[state_col]][is.na(df[[label_col]])])
  df
}
prediction_df <- build_fallback_prediction(states_df, metadata)
simulation <- read_cached_simulation()
if (!is.null(simulation)) {
  simulation$trajectory <- ensure_state_labels(simulation$trajectory, "state", "state_label")
  simulation$hourly_state <- ensure_state_labels(simulation$hourly_state, "state", "state_label")
  simulation$endpoints <- ensure_state_labels(simulation$endpoints, "final_state", "final_state_label")
}

required_trajectory_files <- trajectory_files[c("trajectory", "hourly_state", "endpoints")]
missing_files <- names(required_trajectory_files)[!file.exists(unlist(required_trajectory_files))]
existing_14 <- list.files(tables_dir, pattern = "^14_.*\\.csv$", full.names = FALSE)

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
  titlePanel(div(class = "app-title", "Curlew Trajectory Result Viewer")),
  fluidRow(
    column(
      width = 3,
      div(
        class = "panel",
        div(class = "summary-label", "Mode"),
        div(class = "summary-number", "Viewer Only"),
        tags$p("This app only reads cached CSV files. It does not fit HMM models or simulate trajectories.")
      ),
      div(
        class = "panel",
        div(class = "summary-label", "Cache Status"),
        textOutput("cache_status")
      )
    ),
    column(
      width = 9,
      fluidRow(
        column(width = 4, div(class = "panel", div(class = "summary-label", "Most likely next state"), div(class = "summary-number", textOutput("top_state", inline = TRUE)))),
        column(width = 4, div(class = "panel", div(class = "summary-label", "Mean total distance"), div(class = "summary-number", textOutput("mean_distance", inline = TRUE)))),
        column(width = 4, div(class = "panel", div(class = "summary-label", "Source"), div(textOutput("source_label", inline = TRUE))))
      ),
      fluidRow(
        column(width = 5, div(class = "panel", plotOutput("state_prob_plot", height = "260px"))),
        column(width = 7, div(class = "panel", plotOutput("hourly_state_plot", height = "260px")))
      ),
      div(class = "panel", leafletOutput("trajectory_map", height = "560px")),
      div(class = "panel", tableOutput("endpoint_table"))
    )
  )
)

server <- function(input, output, session) {
  output$cache_status <- renderText({
    if (is.null(simulation)) {
      found <- if (length(existing_14) == 0) "none" else paste(existing_14, collapse = ", ")
      return(paste(
        "Required trajectory cache is incomplete.",
        "Missing:", paste(missing_files, collapse = ", "),
        "Found 14_*.csv:", found
      ))
    }
    "Loaded output/tables/14_trajectory_simulations.csv, 14_trajectory_state_hourly.csv, and 14_trajectory_endpoints.csv."
  })

  output$top_state <- renderText({
    prediction_df$state_label[which.max(prediction_df$probability)]
  })

  output$source_label <- renderText({
    if (is.null(simulation)) "state CSV only" else "cached trajectory CSV"
  })

  output$mean_distance <- renderText({
    validate(need(!is.null(simulation), "No trajectory cache loaded"))
    if ("summary" %in% names(simulation)) {
      total <- simulation$summary |> filter(metric == "total_distance_km") |> slice(1)
      return(paste0(round(total$mean[[1]], 1), " km"))
    }
    paste0(round(mean(simulation$endpoints$total_distance_km, na.rm = TRUE), 1), " km")
  })

  output$state_prob_plot <- renderPlot({
    prediction_df <- ensure_state_labels(prediction_df, "state", "state_label")
    ggplot(prediction_df, aes(x = reorder(state_label, probability), y = probability, fill = state_label)) +
      geom_col(width = 0.7, show.legend = FALSE) +
      coord_flip() +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(x = NULL, y = "Next-hour probability", title = "State transition from cached states") +
      theme_minimal(base_size = 12)
  })

  output$hourly_state_plot <- renderPlot({
    validate(need(!is.null(simulation), "No trajectory cache loaded"))
    ggplot(simulation$hourly_state, aes(x = hour, y = probability, color = state_label)) +
      geom_line(linewidth = 0.8) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(x = "Hour", y = "Simulated state probability", color = NULL, title = "State probabilities over time") +
      theme_minimal(base_size = 12)
  })

  output$trajectory_map <- renderLeaflet({
    validate(need(!is.null(simulation), "No trajectory cache loaded"))
    sim <- simulation$trajectory
    endpoints <- simulation$endpoints

    pal <- colorFactor(
      palette = c("#4c78a8", "#59a14f", "#f28e2b", "#e15759"),
      domain = metadata$state_label
    )

    start_point <- sim |>
      filter(hour == min(hour, na.rm = TRUE)) |>
      slice(1)

    m <- leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addCircleMarkers(
        lng = start_point$lon[[1]],
        lat = start_point$lat[[1]],
        radius = 6,
        stroke = FALSE,
        fillOpacity = 1,
        fillColor = "#111827",
        label = "Start"
      )

    sampled_ids <- sort(unique(sim$sim_id))
    if (length(sampled_ids) > 250) sampled_ids <- sample(sampled_ids, 250)

    for (sid in sampled_ids) {
      one <- sim |> filter(sim_id == sid) |> arrange(hour)
      m <- m |>
        addPolylines(
          data = one,
          lng = ~lon,
          lat = ~lat,
          color = "#2563eb",
          weight = 1,
          opacity = 0.18
        )
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
      addLegend(
        position = "bottomright",
        pal = pal,
        values = metadata$state_label,
        title = "Final state"
      )
  })

  output$endpoint_table <- renderTable({
    validate(need(!is.null(simulation), "No trajectory cache loaded"))
    if ("summary" %in% names(simulation)) {
      return(
        simulation$summary |>
          mutate(across(where(is.numeric), ~ round(.x, 3))) |>
          select(route_direction, metric, n_sims, mean, variance, sd, ci95_low, ci95_high, pi95_low, pi95_high)
      )
    }
    simulation$endpoints |>
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
