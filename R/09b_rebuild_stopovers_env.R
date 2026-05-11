#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(purrr)
})

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

states_path <- if (file.exists(paths$states_env_csv)) paths$states_env_csv else paths$states_csv
stops_path <- if (file.exists(paths$stopover_events_csv)) paths$stopover_events_csv else paths$stopovers_csv
out_path <- paths$stopover_events_env_csv

if (!file.exists(states_path)) stop("找不到状态文件: ", states_path)
if (!file.exists(stops_path)) stop("找不到 stopover 事件文件: ", stops_path)

states <- read_csv(states_path, show_col_types = FALSE)
stops <- read_csv(stops_path, show_col_types = FALSE)

if (!"ts" %in% names(states) && "t_" %in% names(states)) {
  states <- states |> mutate(ts = t_)
}

states <- states |> mutate(ts = as.POSIXct(ts, tz = cfg$project$timezone))
stops <- stops |>
  mutate(
    arrive_time = as.POSIXct(arrive_time, tz = cfg$project$timezone),
    depart_time = as.POSIXct(depart_time, tz = cfg$project$timezone)
  )

id_col <- c("original_id", "id", "ID")[c("original_id", "id", "ID") %in% names(states)][1]
if (is.na(id_col)) stop("states 文件中找不到 original_id / id / ID")

ndvi_col <- c("ndvi", "NDVI", "ndvi_mean")[c("ndvi", "NDVI", "ndvi_mean") %in% names(states)][1]
if (is.na(ndvi_col)) stop("states 文件中找不到 NDVI 列，请先运行 R/08b_add_ndvi_to_states.R")

fill_one_stop <- function(one_stop) {
  sub <- states |>
    filter(
      .data[[id_col]] == one_stop$individual_id,
      ts >= one_stop$arrive_time,
      ts <= one_stop$depart_time
    ) |>
    arrange(ts)

  if (nrow(sub) == 0) {
    return(tibble(
      ndvi_mean = NA_real_,
      ndvi_arrive = NA_real_,
      wind_support = NA_real_,
      n_state_points = 0L
    ))
  }

  ndvi_vals <- sub[[ndvi_col]]
  first_ndvi <- ndvi_vals[!is.na(ndvi_vals)]

  tibble(
    ndvi_mean = mean(ndvi_vals, na.rm = TRUE),
    ndvi_arrive = if (length(first_ndvi) == 0) NA_real_ else first_ndvi[1],
    wind_support = mean(sub$wind_support, na.rm = TRUE),
    n_state_points = nrow(sub)
  )
}

env_new <- map_dfr(seq_len(nrow(stops)), function(i) fill_one_stop(stops[i, ]))

stops_new <- stops |>
  select(-any_of(c("ndvi_mean", "ndvi_arrive", "wind_support", "n_state_points"))) |>
  bind_cols(env_new) |>
  mutate(
    ndvi_mean = ifelse(is.nan(ndvi_mean), NA_real_, ndvi_mean),
    ndvi_arrive = ifelse(is.nan(ndvi_arrive), NA_real_, ndvi_arrive),
    wind_support = ifelse(is.nan(wind_support), NA_real_, wind_support)
  )

write_csv(stops_new, out_path)

qc <- stops_new |>
  summarise(
    n = n(),
    ndvi_mean_na = sum(is.na(ndvi_mean)),
    ndvi_arrive_na = sum(is.na(ndvi_arrive)),
    wind_support_na = sum(is.na(wind_support)),
    min_duration = min(duration_hr, na.rm = TRUE),
    median_duration = median(duration_hr, na.rm = TRUE),
    max_duration = max(duration_hr, na.rm = TRUE)
  )

write_csv(qc, file.path(paths$tables_dir, "09b_stopover_events_env_qc.csv"))
print(qc)
cat("已回填连续停歇事件环境变量，输出:", out_path, "\n")
