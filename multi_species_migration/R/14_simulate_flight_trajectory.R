#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

if (!exists("load_prediction_context")) {
  source(file.path("R", "13_predict_flight_state.R"))
}

trajectory_output_paths <- function(paths) {
  list(
    trajectory_csv = file.path(paths$tables_dir, "14_trajectory_simulations.csv"),
    trajectory_hourly_csv = file.path(paths$tables_dir, "14_trajectory_state_hourly.csv"),
    trajectory_endpoint_csv = file.path(paths$tables_dir, "14_trajectory_endpoints.csv")
  )
}

wrap_bearing <- function(x) {
  x <- x %% 360
  x[x < 0] <- x[x < 0] + 360
  x
}

build_movement_pool <- function(context) {
  if (!requireNamespace("geosphere", quietly = TRUE)) {
    stop("Package 'geosphere' is required for trajectory simulation.")
  }

  context$states |>
    filter(!is.na(lon), !is.na(lat), !is.na(step), !is.na(state)) |>
    arrange(ID, ts) |>
    group_by(ID) |>
    mutate(
      prev_lon = lag(lon),
      prev_lat = lag(lat),
      bearing = geosphere::bearing(cbind(prev_lon, prev_lat), cbind(lon, lat))
    ) |>
    ungroup() |>
    filter(is.finite(step), step >= 0, is.finite(bearing)) |>
    select(state, step, angle, bearing)
}

sample_movement <- function(pool, state_num, previous_bearing = NA_real_) {
  state_pool <- pool |>
    filter(state == state_num, is.finite(step))

  if (nrow(state_pool) == 0) {
    state_pool <- pool |> filter(is.finite(step))
  }

  row <- state_pool[sample.int(nrow(state_pool), 1), , drop = FALSE]
  step_km <- max(0, as.numeric(row$step[[1]]))

  if (is.finite(previous_bearing) && is.finite(row$angle[[1]])) {
    bearing <- wrap_bearing(previous_bearing + as.numeric(row$angle[[1]]) * 180 / pi)
  } else {
    bearing <- wrap_bearing(as.numeric(row$bearing[[1]]))
  }

  list(step_km = step_km, bearing = bearing)
}

simulate_flight_trajectory <- function(
  start_lon,
  start_lat,
  current_state,
  temp_C,
  wind_support,
  wind_speed,
  ndvi = NA_real_,
  horizon_hr = 24,
  n_sims = 200,
  context = NULL,
  seed = 42,
  env_weight = 0.35
) {
  if (!requireNamespace("geosphere", quietly = TRUE)) {
    stop("Package 'geosphere' is required for trajectory simulation.")
  }
  if (is.null(context)) context <- load_prediction_context()

  set.seed(seed)
  movement_pool <- build_movement_pool(context)
  current_state_num <- resolve_state(current_state, context$metadata)
  horizon_hr <- as.integer(horizon_hr)
  n_sims <- as.integer(n_sims)

  if (!is.finite(start_lon) || !is.finite(start_lat)) stop("start_lon/start_lat must be finite.")
  if (horizon_hr < 1) stop("horizon_hr must be at least 1.")
  if (n_sims < 1) stop("n_sims must be at least 1.")

  state_lookup <- setNames(context$metadata$state_label, as.character(context$metadata$state))
  rows <- vector("list", n_sims * (horizon_hr + 1))
  idx <- 1

  for (sim_id in seq_len(n_sims)) {
    lon <- as.numeric(start_lon)
    lat <- as.numeric(start_lat)
    state_num <- current_state_num
    bearing <- NA_real_

    rows[[idx]] <- tibble(
      sim_id = sim_id,
      hour = 0L,
      state = state_num,
      state_label = state_lookup[[as.character(state_num)]],
      lon = lon,
      lat = lat,
      step_km = 0,
      bearing = NA_real_
    )
    idx <- idx + 1

    for (hour in seq_len(horizon_hr)) {
      probs <- predict_flight_state(
        current_state = state_num,
        temp_C = temp_C,
        wind_support = wind_support,
        wind_speed = wind_speed,
        ndvi = ndvi,
        context = context,
        env_weight = env_weight
      )

      state_num <- sample(probs$state, size = 1, prob = probs$probability)
      movement <- sample_movement(movement_pool, state_num, bearing)
      dest <- geosphere::destPoint(
        p = c(lon, lat),
        b = movement$bearing,
        d = movement$step_km * 1000
      )

      lon <- as.numeric(dest[1])
      lat <- as.numeric(dest[2])
      bearing <- movement$bearing

      rows[[idx]] <- tibble(
        sim_id = sim_id,
        hour = as.integer(hour),
        state = state_num,
        state_label = state_lookup[[as.character(state_num)]],
        lon = lon,
        lat = lat,
        step_km = movement$step_km,
        bearing = bearing
      )
      idx <- idx + 1
    }
  }

  sim <- bind_rows(rows)

  hourly <- sim |>
    count(hour, state, state_label, name = "n") |>
    group_by(hour) |>
    mutate(probability = n / sum(n)) |>
    ungroup() |>
    arrange(hour, state)

  endpoints <- sim |>
    filter(hour == max(hour)) |>
    group_by(sim_id) |>
    summarise(
      endpoint_lon = last(lon),
      endpoint_lat = last(lat),
      final_state = last(state),
      final_state_label = last(state_label),
      total_distance_km = sum(step_km, na.rm = TRUE),
      .groups = "drop"
    )

  list(
    trajectory = sim,
    hourly_state = hourly,
    endpoints = endpoints,
    context = context
  )
}

write_trajectory_example <- function() {
  context <- load_prediction_context()
  out_paths <- trajectory_output_paths(context$paths)
  example_row <- context$states |>
    filter(!is.na(lon), !is.na(lat), !is.na(temp_C), !is.na(wind_support), !is.na(wind_speed)) |>
    slice_tail(n = 1)

  res <- simulate_flight_trajectory(
    start_lon = example_row$lon[[1]],
    start_lat = example_row$lat[[1]],
    current_state = example_row$state[[1]],
    temp_C = example_row$temp_C[[1]],
    wind_support = example_row$wind_support[[1]],
    wind_speed = example_row$wind_speed[[1]],
    ndvi = if ("ndvi" %in% names(example_row)) example_row$ndvi[[1]] else NA_real_,
    horizon_hr = 24,
    n_sims = 100,
    context = context,
    seed = 42
  )

  write_csv(res$trajectory, out_paths$trajectory_csv)
  write_csv(res$hourly_state, out_paths$trajectory_hourly_csv)
  write_csv(res$endpoints, out_paths$trajectory_endpoint_csv)

  message("Wrote: ", out_paths$trajectory_csv)
  message("Wrote: ", out_paths$trajectory_hourly_csv)
  message("Wrote: ", out_paths$trajectory_endpoint_csv)
  invisible(res)
}

is_running_this_script <- function(path) {
  cmd_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(cmd_file) == 0) return(FALSE)
  cmd_file <- sub("^--file=", "", cmd_file[[1]])
  identical(
    normalizePath(cmd_file, winslash = "/", mustWork = FALSE),
    normalizePath(path, winslash = "/", mustWork = FALSE)
  )
}

if (is_running_this_script(file.path("R", "14_simulate_flight_trajectory.R"))) {
  write_trajectory_example()
}
