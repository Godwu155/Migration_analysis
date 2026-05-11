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
    trajectory_endpoint_csv = file.path(paths$tables_dir, "14_trajectory_endpoints.csv"),
    trajectory_summary_csv = file.path(paths$tables_dir, "15_prediction_summary.csv"),
    endpoint_uncertainty_csv = file.path(paths$tables_dir, "15_endpoint_uncertainty.csv"),
    direction_comparison_csv = file.path(paths$tables_dir, "15_direction_comparison.csv")
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
    select(state, step, angle, bearing, migration_direction)
}

sample_movement <- function(pool, state_num, previous_bearing = NA_real_, route_direction = "global", min_direction_n = 20) {
  route_direction <- resolve_route_direction(route_direction)
  state_pool <- pool |>
    filter(state == state_num, is.finite(step))

  if (route_direction %in% c("northbound", "southbound")) {
    directional_pool <- state_pool |> filter(migration_direction == route_direction)
    if (nrow(directional_pool) >= min_direction_n) {
      state_pool <- directional_pool
    }
  }

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

ci_for_mean <- function(x, level = 0.95) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n == 0) return(c(low = NA_real_, high = NA_real_))
  m <- mean(x)
  if (n == 1) return(c(low = m, high = m))
  se <- stats::sd(x) / sqrt(n)
  alpha <- 1 - level
  delta <- stats::qt(1 - alpha / 2, df = n - 1) * se
  c(low = m - delta, high = m + delta)
}

prediction_interval <- function(x, level = 0.95) {
  x <- x[is.finite(x)]
  if (length(x) == 0) return(c(low = NA_real_, high = NA_real_))
  alpha <- 1 - level
  as.numeric(stats::quantile(x, probs = c(alpha / 2, 1 - alpha / 2), na.rm = TRUE, names = FALSE)) |>
    setNames(c("low", "high"))
}

add_endpoint_displacement <- function(endpoints, start_lon, start_lat) {
  if (!requireNamespace("geosphere", quietly = TRUE)) {
    stop("Package 'geosphere' is required for endpoint displacement summaries.")
  }
  bearing <- geosphere::bearing(
    cbind(rep(start_lon, nrow(endpoints)), rep(start_lat, nrow(endpoints))),
    cbind(endpoints$endpoint_lon, endpoints$endpoint_lat)
  )
  displacement_km <- geosphere::distHaversine(
    cbind(rep(start_lon, nrow(endpoints)), rep(start_lat, nrow(endpoints))),
    cbind(endpoints$endpoint_lon, endpoints$endpoint_lat)
  ) / 1000
  endpoints |>
    mutate(
      endpoint_bearing = wrap_bearing(bearing),
      displacement_km = displacement_km,
      dx_km = displacement_km * sin(endpoint_bearing * pi / 180),
      dy_km = displacement_km * cos(endpoint_bearing * pi / 180)
    )
}

summarise_numeric_prediction <- function(df, value_col, label, route_direction, horizon_hr) {
  x <- df[[value_col]]
  ci <- ci_for_mean(x)
  pi <- prediction_interval(x)
  tibble(
    route_direction = route_direction,
    horizon_hr = horizon_hr,
    metric = label,
    n_sims = sum(is.finite(x)),
    mean = mean(x, na.rm = TRUE),
    variance = stats::var(x, na.rm = TRUE),
    sd = stats::sd(x, na.rm = TRUE),
    ci95_low = ci[["low"]],
    ci95_high = ci[["high"]],
    pi95_low = pi[["low"]],
    pi95_high = pi[["high"]]
  )
}

summarise_endpoint_uncertainty <- function(endpoints, route_direction, horizon_hr) {
  metrics <- list(
    total_distance_km = "total_distance_km",
    displacement_km = "displacement_km",
    east_west_dx_km = "dx_km",
    north_south_dy_km = "dy_km",
    endpoint_lon = "endpoint_lon",
    endpoint_lat = "endpoint_lat"
  )
  out <- bind_rows(lapply(names(metrics), function(label) {
    summarise_numeric_prediction(endpoints, metrics[[label]], label, route_direction, horizon_hr)
  }))

  cov_xy <- stats::cov(endpoints[, c("dx_km", "dy_km")], use = "complete.obs")
  ellipse_area_95 <- if (all(is.finite(cov_xy)) && nrow(endpoints) > 2) {
    pi * stats::qchisq(0.95, df = 2) * sqrt(max(det(cov_xy), 0))
  } else {
    NA_real_
  }

  out |>
    mutate(endpoint_ellipse_area_95_km2 = ellipse_area_95)
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
  env_weight = 0.35,
  route_direction = "global"
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
  route_direction <- resolve_route_direction(route_direction)

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
      bearing = NA_real_,
      route_direction = route_direction
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
        env_weight = env_weight,
        route_direction = route_direction
      )

      state_num <- sample(probs$state, size = 1, prob = probs$probability)
      movement <- sample_movement(movement_pool, state_num, bearing, route_direction = route_direction)
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
        bearing = bearing,
        route_direction = route_direction
      )
      idx <- idx + 1
    }
  }

  sim <- bind_rows(rows)

  hourly <- sim |>
    count(hour, state, state_label, name = "n") |>
    group_by(hour) |>
    mutate(
      n_sims = sum(n),
      probability = n / n_sims,
      ci95_low = pmax(0, probability - 1.96 * sqrt(probability * (1 - probability) / n_sims)),
      ci95_high = pmin(1, probability + 1.96 * sqrt(probability * (1 - probability) / n_sims)),
      route_direction = route_direction
    ) |>
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
      route_direction = route_direction,
      .groups = "drop"
    ) |>
    add_endpoint_displacement(start_lon, start_lat)

  endpoint_uncertainty <- summarise_endpoint_uncertainty(endpoints, route_direction, horizon_hr)
  summary <- endpoint_uncertainty |>
    filter(metric %in% c("total_distance_km", "displacement_km", "east_west_dx_km", "north_south_dy_km")) |>
    select(route_direction, horizon_hr, metric, n_sims, mean, variance, sd, ci95_low, ci95_high, pi95_low, pi95_high, endpoint_ellipse_area_95_km2)

  list(
    trajectory = sim,
    hourly_state = hourly,
    endpoints = endpoints,
    endpoint_uncertainty = endpoint_uncertainty,
    summary = summary,
    context = context
  )
}

compare_migration_directions <- function(
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
  if (is.null(context)) context <- load_prediction_context()
  bind_rows(lapply(c("northbound", "southbound"), function(direction) {
    res <- simulate_flight_trajectory(
      start_lon = start_lon,
      start_lat = start_lat,
      current_state = current_state,
      temp_C = temp_C,
      wind_support = wind_support,
      wind_speed = wind_speed,
      ndvi = ndvi,
      horizon_hr = horizon_hr,
      n_sims = n_sims,
      context = context,
      seed = seed,
      env_weight = env_weight,
      route_direction = direction
    )
    res$summary
  }))
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
    seed = 42,
    route_direction = "global"
  )

  write_csv(res$trajectory, out_paths$trajectory_csv)
  write_csv(res$hourly_state, out_paths$trajectory_hourly_csv)
  write_csv(res$endpoints, out_paths$trajectory_endpoint_csv)
  write_csv(res$summary, out_paths$trajectory_summary_csv)
  write_csv(res$endpoint_uncertainty, out_paths$endpoint_uncertainty_csv)

  direction_comparison <- compare_migration_directions(
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
  write_csv(direction_comparison, out_paths$direction_comparison_csv)

  message("Wrote: ", out_paths$trajectory_csv)
  message("Wrote: ", out_paths$trajectory_hourly_csv)
  message("Wrote: ", out_paths$trajectory_endpoint_csv)
  message("Wrote: ", out_paths$trajectory_summary_csv)
  message("Wrote: ", out_paths$endpoint_uncertainty_csv)
  message("Wrote: ", out_paths$direction_comparison_csv)
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
