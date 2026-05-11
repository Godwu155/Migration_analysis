suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
})

project_root <- "D:/migration_project"
Sys.setenv(PROJECT_ROOT = project_root)
setwd(project_root)

source(file.path(project_root, "R", "13_predict_flight_state.R"))
source(file.path(project_root, "R", "14_simulate_flight_trajectory.R"))

context <- load_prediction_context()
metadata <- context$metadata
state_choices <- setNames(
  as.character(metadata$state),
  paste(metadata$state_label, "(state", metadata$state, ")")
)

example_row <- context$states |>
  filter(!is.na(lon), !is.na(lat), !is.na(temp_C), !is.na(wind_support), !is.na(wind_speed)) |>
  slice_tail(n = 1)

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
  titlePanel(div(class = "app-title", "Curlew Flight State Predictor")),
  fluidRow(
    column(
      width = 3,
      div(
        class = "panel",
        numericInput("lon", "Current longitude", value = round(example_row$lon[[1]], 5), step = 0.01),
        numericInput("lat", "Current latitude", value = round(example_row$lat[[1]], 5), step = 0.01),
        selectInput("state", "Current state", choices = state_choices, selected = as.character(example_row$state[[1]])),
        numericInput("temp_C", "Temperature (C)", value = round(example_row$temp_C[[1]], 2), step = 0.5),
        numericInput("wind_support", "Wind support", value = round(example_row$wind_support[[1]], 2), step = 0.1),
        numericInput("wind_speed", "Wind speed", value = round(example_row$wind_speed[[1]], 2), step = 0.1),
        numericInput("ndvi", "NDVI", value = if ("ndvi" %in% names(example_row)) round(example_row$ndvi[[1]], 3) else 0.5, step = 0.01, min = 0, max = 1),
        selectInput(
          "route_direction",
          "Migration direction",
          choices = c("Global" = "global", "Northbound" = "northbound", "Southbound" = "southbound"),
          selected = "global"
        ),
        sliderInput("horizon", "Simulation horizon (hours)", min = 6, max = 72, value = 24, step = 6),
        sliderInput("n_sims", "Number of simulated tracks", min = 20, max = 500, value = 100, step = 20),
        numericInput("seed", "Random seed", value = 42, step = 1),
        actionButton("run", "Predict and simulate", class = "btn-primary"),
        tags$p(
          style = "margin-top: 10px; color: #667085; font-size: 12px;",
          "This app predicts from the existing decoded HMM output. It does not fit HMM models."
        )
      )
    ),
    column(
      width = 9,
      fluidRow(
        column(width = 4, div(class = "panel", div(class = "summary-label", "Most likely next state"), div(class = "summary-number", textOutput("top_state", inline = TRUE)))),
        column(width = 4, div(class = "panel", div(class = "summary-label", "Mean total distance"), div(class = "summary-number", textOutput("mean_distance", inline = TRUE)))),
        column(width = 4, div(class = "panel", div(class = "summary-label", "95% CI mean distance"), div(class = "summary-number", textOutput("distance_ci", inline = TRUE))))
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
  prediction <- reactiveVal(NULL)
  simulation <- reactiveVal(NULL)

  observeEvent(input$run, {
    withProgress(message = "Predicting from current inputs", value = 0, {
      incProgress(0.25, detail = "State probabilities")
      prediction(
        predict_flight_state(
          current_state = as.integer(input$state),
          temp_C = input$temp_C,
          wind_support = input$wind_support,
          wind_speed = input$wind_speed,
          ndvi = input$ndvi,
          context = context,
          route_direction = input$route_direction
        )
      )

      incProgress(0.5, detail = "Trajectory simulation")
      simulation(
        simulate_flight_trajectory(
          start_lon = input$lon,
          start_lat = input$lat,
          current_state = as.integer(input$state),
          temp_C = input$temp_C,
          wind_support = input$wind_support,
          wind_speed = input$wind_speed,
          ndvi = input$ndvi,
          horizon_hr = input$horizon,
          n_sims = input$n_sims,
          context = context,
          seed = input$seed,
          route_direction = input$route_direction
        )
      )
    })
  }, ignoreInit = TRUE)

  output$top_state <- renderText({
    validate(need(!is.null(prediction()), "Click Predict and simulate"))
    pred <- prediction()
    pred$state_label[which.max(pred$probability)]
  })

  output$model_source <- renderText({
    validate(need(!is.null(prediction()), "Waiting for input"))
    unique(prediction()$model_source)[[1]]
  })

  output$mean_distance <- renderText({
    validate(need(!is.null(simulation()), "Click Predict and simulate"))
    total <- simulation()$summary |> filter(metric == "total_distance_km") |> slice(1)
    paste0(round(total$mean[[1]], 1), " km")
  })

  output$distance_ci <- renderText({
    validate(need(!is.null(simulation()), "Click Predict and simulate"))
    total <- simulation()$summary |> filter(metric == "total_distance_km") |> slice(1)
    paste0(round(total$ci95_low[[1]], 1), "-", round(total$ci95_high[[1]], 1), " km")
  })

  output$state_prob_plot <- renderPlot({
    validate(need(!is.null(prediction()), "Click Predict and simulate"))
    pred <- prediction()
    ggplot(pred, aes(x = reorder(state_label, probability), y = probability, fill = state_label)) +
      geom_col(width = 0.7, show.legend = FALSE) +
      coord_flip() +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(x = NULL, y = "Next-hour probability", title = "State prediction") +
      theme_minimal(base_size = 12)
  })

  output$hourly_state_plot <- renderPlot({
    validate(need(!is.null(simulation()), "Click Predict and simulate"))
    hourly <- simulation()$hourly_state
    ggplot(hourly, aes(x = hour, y = probability, color = state_label)) +
      geom_line(linewidth = 0.8) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(x = "Hour", y = "Simulated state probability", color = NULL, title = "State probabilities over time") +
      theme_minimal(base_size = 12)
  })

  output$trajectory_map <- renderLeaflet({
    validate(need(!is.null(simulation()), "Click Predict and simulate"))
    sim <- simulation()$trajectory
    endpoints <- simulation()$endpoints
    pal <- colorFactor(
      palette = c("#4c78a8", "#59a14f", "#f28e2b", "#e15759"),
      domain = metadata$state_label
    )

    start_point <- sim |> filter(hour == min(hour, na.rm = TRUE)) |> slice(1)

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
    validate(need(!is.null(simulation()), "Click Predict and simulate"))
    simulation()$summary |>
      mutate(across(where(is.numeric), ~ round(.x, 3))) |>
      select(route_direction, metric, n_sims, mean, variance, sd, ci95_low, ci95_high, pi95_low, pi95_high)
  })
}

shinyApp(ui, server)
