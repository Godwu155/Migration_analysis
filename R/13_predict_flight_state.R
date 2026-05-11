#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(jsonlite)
})

ensure_project_root <- function() {
  if (file.exists(file.path("R", "00_config.R"))) return(invisible(getwd()))

  root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(root) && file.exists(file.path(root, "R", "00_config.R"))) {
    setwd(root)
    return(invisible(getwd()))
  }

  stop("Please run from the project root, or set PROJECT_ROOT to the project root.")
}

ensure_project_root()
source(file.path("R", "00_config.R"))

prediction_output_paths <- function(paths) {
  list(
    state_prediction_csv = file.path(paths$tables_dir, "13_state_prediction.csv"),
    prediction_context_rds = file.path(paths$models_dir, "curlew_prediction_context.rds")
  )
}

safe_scale_value <- function(x, center, scale) {
  if (!is.finite(scale) || scale == 0) return(0)
  (x - center) / scale
}

normalize_probs <- function(x) {
  x[!is.finite(x)] <- 0
  s <- sum(x)
  if (s <= 0) return(rep(1 / length(x), length(x)))
  x / s
}

make_state_metadata <- function(states_df) {
  ranked <- states_df |>
    filter(!is.na(state), !is.na(step)) |>
    group_by(state) |>
    summarise(
      mean_step = mean(step, na.rm = TRUE),
      median_step = median(step, na.rm = TRUE),
      n = n(),
      .groups = "drop"
    ) |>
    arrange(mean_step)

  role_labels <- c("Stopover", "Local activity", "Flight", "Fast flight")
  ranked$state_label <- role_labels[seq_len(nrow(ranked))]
  ranked$state_label[is.na(ranked$state_label)] <- paste("State", ranked$state[is.na(ranked$state_label)])
  ranked
}

build_empirical_transition <- function(states_df, alpha = 0.5) {
  df <- states_df |>
    filter(!is.na(state)) |>
    arrange(ID, ts) |>
    group_by(ID) |>
    mutate(next_state = lead(state)) |>
    ungroup() |>
    filter(!is.na(next_state))

  state_levels <- sort(unique(states_df$state[!is.na(states_df$state)]))
  mat <- matrix(
    alpha,
    nrow = length(state_levels),
    ncol = length(state_levels),
    dimnames = list(as.character(state_levels), as.character(state_levels))
  )

  if (nrow(df) > 0) {
    counts <- df |>
      count(state, next_state, name = "n")

    for (i in seq_len(nrow(counts))) {
      mat[as.character(counts$state[[i]]), as.character(counts$next_state[[i]])] <-
        mat[as.character(counts$state[[i]]), as.character(counts$next_state[[i]])] + counts$n[[i]]
    }
  }

  sweep(mat, 1, rowSums(mat), "/")
}

build_env_stats <- function(states_df) {
  env_cols <- intersect(c("temp_C", "wind_support", "wind_speed", "ndvi"), names(states_df))

  global <- lapply(env_cols, function(col) {
    vals <- states_df[[col]]
    list(
      mean = mean(vals, na.rm = TRUE),
      sd = sd(vals, na.rm = TRUE)
    )
  })
  names(global) <- env_cols

  by_state <- states_df |>
    group_by(state) |>
    summarise(
      across(
        all_of(env_cols),
        list(mean = ~ mean(.x, na.rm = TRUE), sd = ~ sd(.x, na.rm = TRUE)),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )

  list(global = global, by_state = by_state, env_cols = env_cols)
}

load_prediction_context <- function(save_context = FALSE) {
  cfg <- load_cfg()
  paths <- project_paths(cfg)
  init_project_dirs(paths)
  out_paths <- prediction_output_paths(paths)

  if (!file.exists(paths$states_csv)) {
    stop("Decoded state file not found: ", paths$states_csv)
  }

  states_df <- read_csv(paths$states_csv, show_col_types = FALSE) |>
    mutate(
      ts = as.POSIXct(ts, tz = cfg$project$timezone),
      state = as.integer(state)
    ) |>
    arrange(ID, ts)

  metadata <- make_state_metadata(states_df)
  transition <- build_empirical_transition(states_df)
  env_stats <- build_env_stats(states_df)

  model_path <- file.path(paths$models_dir, paste0(cfg$project$species_code, "_hmm_best.rds"))
  hmm_fit <- NULL
  if (file.exists(model_path)) {
    hmm_fit <- tryCatch(readRDS(model_path), error = function(e) NULL)
  }

  context <- list(
    cfg = cfg,
    paths = paths,
    out_paths = out_paths,
    states = states_df,
    metadata = metadata,
    transition = transition,
    env_stats = env_stats,
    hmm_fit = hmm_fit,
    model_path = model_path
  )

  if (isTRUE(save_context)) {
    saveRDS(context, out_paths$prediction_context_rds)
  }

  context
}

resolve_state <- function(current_state, metadata) {
  if (is.numeric(current_state) && length(current_state) == 1) {
    state_num <- as.integer(current_state)
    if (state_num %in% metadata$state) return(state_num)
  }

  current_state_chr <- tolower(trimws(as.character(current_state)))
  label_match <- metadata$state[tolower(metadata$state_label) == current_state_chr]
  if (length(label_match) == 1) return(label_match[[1]])

  numeric_state <- suppressWarnings(as.integer(current_state_chr))
  if (!is.na(numeric_state) && numeric_state %in% metadata$state) return(numeric_state)

  stop("Unknown current_state: ", current_state)
}

try_hmm_transition <- function(context, current_state, covariates) {
  fit <- context$hmm_fit
  if (is.null(fit)) return(NULL)
  if (!requireNamespace("moveHMM", quietly = TRUE)) return(NULL)

  env <- context$env_stats$global
  covs <- data.frame(
    temp_z = safe_scale_value(covariates$temp_C, env$temp_C$mean, env$temp_C$sd),
    wind_support_z = safe_scale_value(covariates$wind_support, env$wind_support$mean, env$wind_support$sd),
    wind_speed_z = safe_scale_value(covariates$wind_speed, env$wind_speed$mean, env$wind_speed$sd)
  )

  ns <- asNamespace("moveHMM")

  # moveHMM does not expose a stable public prediction helper in all versions.
  # These guarded calls let the project use the fitted HMM when available, while
  # falling back cleanly to the empirical transition model otherwise.
  out <- tryCatch({
    res <- NULL
    if (exists("getTrProbs", envir = ns, inherits = FALSE)) {
      fn <- get("getTrProbs", envir = ns)
      probs <- fn(fit, covs = covs)
      if (length(dim(probs)) == 3) res <- probs[current_state, , 1]
      if (is.matrix(probs)) res <- probs[current_state, ]
    }
    res
  }, error = function(e) NULL)

  if (!is.null(out)) return(normalize_probs(as.numeric(out)))
  NULL
}

environment_adjustment <- function(context, covariates, env_weight = 0.35) {
  stats <- context$env_stats
  by_state <- stats$by_state
  score <- rep(0, nrow(by_state))

  for (col in stats$env_cols) {
    if (!col %in% names(covariates)) next
    x <- covariates[[col]]
    if (!is.finite(x)) next

    center_col <- paste0(col, "_mean")
    global_sd <- stats$global[[col]]$sd
    if (!is.finite(global_sd) || global_sd == 0) next

    diff_z <- (x - by_state[[center_col]]) / global_sd
    score <- score - 0.5 * diff_z^2
  }

  adj <- exp(env_weight * score)
  names(adj) <- as.character(by_state$state)
  adj
}

predict_flight_state <- function(
  current_state,
  temp_C,
  wind_support,
  wind_speed,
  ndvi = NA_real_,
  context = NULL,
  env_weight = 0.35,
  prefer_hmm = TRUE
) {
  if (is.null(context)) context <- load_prediction_context()

  state_num <- resolve_state(current_state, context$metadata)
  state_keys <- as.character(context$metadata$state)
  covariates <- list(
    temp_C = as.numeric(temp_C),
    wind_support = as.numeric(wind_support),
    wind_speed = as.numeric(wind_speed),
    ndvi = as.numeric(ndvi)
  )

  hmm_probs <- NULL
  if (isTRUE(prefer_hmm)) {
    hmm_probs <- try_hmm_transition(context, state_num, covariates)
  }

  if (!is.null(hmm_probs) && length(hmm_probs) == length(state_keys)) {
    probs <- hmm_probs
    source <- "moveHMM transition model"
  } else {
    base <- context$transition[as.character(state_num), state_keys]
    adj <- environment_adjustment(context, covariates, env_weight = env_weight)[state_keys]
    probs <- normalize_probs(as.numeric(base) * as.numeric(adj))
    source <- "empirical transition + environment similarity"
  }

  tibble(
    current_state = state_num,
    state = context$metadata$state,
    state_label = context$metadata$state_label,
    probability = probs,
    model_source = source,
    temp_C = covariates$temp_C,
    wind_support = covariates$wind_support,
    wind_speed = covariates$wind_speed,
    ndvi = covariates$ndvi
  )
}

write_state_prediction_example <- function() {
  context <- load_prediction_context(save_context = TRUE)
  example_row <- context$states |>
    filter(!is.na(temp_C), !is.na(wind_support), !is.na(wind_speed)) |>
    slice_tail(n = 1)

  pred <- predict_flight_state(
    current_state = example_row$state[[1]],
    temp_C = example_row$temp_C[[1]],
    wind_support = example_row$wind_support[[1]],
    wind_speed = example_row$wind_speed[[1]],
    ndvi = if ("ndvi" %in% names(example_row)) example_row$ndvi[[1]] else NA_real_,
    context = context
  )

  write_csv(pred, context$out_paths$state_prediction_csv)
  message("Wrote: ", context$out_paths$state_prediction_csv)
  invisible(pred)
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

if (is_running_this_script(file.path("R", "13_predict_flight_state.R"))) {
  write_state_prediction_example()
}
