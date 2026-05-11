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

env_path <- paths$env_csv
ndvi_path <- paths$ndvi_csv
out_path <- paths$env_ndvi_csv

if (!file.exists(env_path)) stop("找不到 ERA5 环境匹配文件: ", env_path)
if (!file.exists(ndvi_path)) stop("找不到 NDVI 原始文件: ", ndvi_path)

safe_time <- function(x) {
  if (inherits(x, "POSIXt")) return(as.POSIXct(x, tz = cfg$project$timezone))

  parse_date_time(
    as.character(x),
    orders = c(
      "Ymd HMS",
      "Y-m-d H:M:S",
      "Y/m/d H:M:S",
      "Ymd HM",
      "Y-m-d H:M",
      "Y/m/d H:M"
    ),
    tz = cfg$project$timezone,
    quiet = TRUE
  )
}

gps <- read_csv(env_path, show_col_types = FALSE)
ndvi_raw <- read_csv(ndvi_path, show_col_types = FALSE)

ndvi_col <- cfg$input$ndvi_value_col %||% "MODIS Land Vegetation Indices 1km Monthly Terra NDVI"
if (!ndvi_col %in% names(ndvi_raw)) {
  stop("NDVI 原始文件缺少列: ", ndvi_col)
}

ndvi_id_col <- cfg$input$ndvi_id_col %||% "individual-local-identifier"
ndvi_time_col <- cfg$input$ndvi_time_col %||% "timestamp"
ndvi_lon_col <- cfg$input$ndvi_lon_col %||% "location-long"
ndvi_lat_col <- cfg$input$ndvi_lat_col %||% "location-lat"
required_ndvi_cols <- c(ndvi_id_col, ndvi_time_col, ndvi_lon_col, ndvi_lat_col, ndvi_col)
miss_ndvi_cols <- setdiff(required_ndvi_cols, names(ndvi_raw))
if (length(miss_ndvi_cols) > 0) {
  stop("NDVI 原始文件缺少列: ", paste(miss_ndvi_cols, collapse = ", "))
}

gps <- gps |>
  select(-any_of(c("ndvi", "ndvi_raw", "ts_ndvi", "ndvi_time_diff_hr", "lon_ndvi", "lat_ndvi"))) |>
  mutate(
    ts = safe_time(ts),
    gps_sec = as.numeric(ts)
  ) |>
  filter(!is.na(id), !is.na(ts), is.finite(gps_sec)) |>
  arrange(id, ts)

ndvi <- ndvi_raw |>
  transmute(
    id = .data[[ndvi_id_col]],
    ts_ndvi = safe_time(.data[[ndvi_time_col]]),
    ndvi_sec = as.numeric(ts_ndvi),
    lon_ndvi = .data[[ndvi_lon_col]],
    lat_ndvi = .data[[ndvi_lat_col]],
    ndvi_raw = .data[[ndvi_col]]
  ) |>
  filter(!is.na(id), !is.na(ts_ndvi), is.finite(ndvi_sec), !is.na(ndvi_raw)) |>
  arrange(id, ts_ndvi)

ndvi_max <- max(ndvi$ndvi_raw, na.rm = TRUE)
if (is.finite(ndvi_max) && ndvi_max > 2) {
  ndvi <- ndvi |> mutate(ndvi = ndvi_raw / 10000)
} else {
  ndvi <- ndvi |> mutate(ndvi = ndvi_raw)
}

ndvi <- ndvi |>
  mutate(ndvi = if_else(ndvi < -0.2 | ndvi > 1, NA_real_, ndvi))

match_one_id <- function(gps_i, ndvi_i, max_diff_hr = 24 * 20) {
  gps_i <- gps_i |> arrange(ts)

  if (nrow(ndvi_i) == 0) {
    gps_i$ndvi <- NA_real_
    gps_i$ndvi_raw <- NA_real_
    gps_i$ts_ndvi <- as.POSIXct(NA, tz = cfg$project$timezone)
    gps_i$ndvi_time_diff_hr <- NA_real_
    gps_i$lon_ndvi <- NA_real_
    gps_i$lat_ndvi <- NA_real_
    return(gps_i)
  }

  ndvi_i <- ndvi_i |> arrange(ts_ndvi)
  gps_sec <- gps_i$gps_sec
  ndvi_sec <- ndvi_i$ndvi_sec

  idx_left <- findInterval(gps_sec, ndvi_sec)
  idx_right <- idx_left + 1
  idx_left[idx_left < 1] <- NA_integer_
  idx_right[idx_right > length(ndvi_sec)] <- NA_integer_

  diff_left <- rep(Inf, length(gps_sec))
  diff_right <- rep(Inf, length(gps_sec))
  ok_left <- !is.na(idx_left)
  ok_right <- !is.na(idx_right)
  diff_left[ok_left] <- abs(gps_sec[ok_left] - ndvi_sec[idx_left[ok_left]])
  diff_right[ok_right] <- abs(gps_sec[ok_right] - ndvi_sec[idx_right[ok_right]])

  idx_best <- idx_left
  idx_best[diff_right < diff_left] <- idx_right[diff_right < diff_left]

  time_diff_hr <- rep(NA_real_, length(gps_sec))
  ok_best <- !is.na(idx_best)
  time_diff_hr[ok_best] <- abs(gps_sec[ok_best] - ndvi_sec[idx_best[ok_best]]) / 3600
  ok_keep <- ok_best & time_diff_hr <= max_diff_hr

  gps_i$ndvi <- NA_real_
  gps_i$ndvi_raw <- NA_real_
  gps_i$ts_ndvi <- as.POSIXct(NA, tz = cfg$project$timezone)
  gps_i$ndvi_time_diff_hr <- time_diff_hr
  gps_i$lon_ndvi <- NA_real_
  gps_i$lat_ndvi <- NA_real_

  gps_i$ndvi[ok_keep] <- ndvi_i$ndvi[idx_best[ok_keep]]
  gps_i$ndvi_raw[ok_keep] <- ndvi_i$ndvi_raw[idx_best[ok_keep]]
  gps_i$ts_ndvi[ok_keep] <- ndvi_i$ts_ndvi[idx_best[ok_keep]]
  gps_i$lon_ndvi[ok_keep] <- ndvi_i$lon_ndvi[idx_best[ok_keep]]
  gps_i$lat_ndvi[ok_keep] <- ndvi_i$lat_ndvi[idx_best[ok_keep]]

  gps_i
}

out <- map_dfr(sort(unique(gps$id)), function(one_id) {
  gps_i <- gps |> filter(id == one_id)
  ndvi_i <- ndvi |> filter(id == one_id)
  cat("匹配个体:", one_id, " GPS:", nrow(gps_i), " NDVI:", nrow(ndvi_i), "\n")
  match_one_id(gps_i, ndvi_i)
}) |>
  select(-gps_sec)

write_csv(out, out_path)

qc <- out |>
  summarise(
    n = n(),
    ndvi_na = sum(is.na(ndvi)),
    ndvi_na_rate = mean(is.na(ndvi)),
    ndvi_min = min(ndvi, na.rm = TRUE),
    ndvi_median = median(ndvi, na.rm = TRUE),
    ndvi_mean = mean(ndvi, na.rm = TRUE),
    ndvi_max = max(ndvi, na.rm = TRUE),
    median_time_diff_hr = median(ndvi_time_diff_hr, na.rm = TRUE),
    max_time_diff_hr = max(ndvi_time_diff_hr, na.rm = TRUE)
  )

by_id <- out |>
  group_by(id) |>
  summarise(
    n = n(),
    ndvi_na = sum(is.na(ndvi)),
    ndvi_na_rate = mean(is.na(ndvi)),
    median_ndvi = median(ndvi, na.rm = TRUE),
    median_time_diff_hr = median(ndvi_time_diff_hr, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(qc, file.path(paths$tables_dir, "05b_ndvi_match_qc.csv"))
write_csv(by_id, file.path(paths$tables_dir, "05b_ndvi_match_by_id.csv"))

cat("NDVI 匹配完成，输出:", out_path, "\n")
print(qc)
