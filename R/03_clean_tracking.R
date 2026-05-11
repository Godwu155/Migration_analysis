#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(geosphere)
  library(jsonlite)
})
source(file.path("R", "00_config.R"))
source(file.path("R", "01_utils.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

raw <- read_csv(paths$raw_csv, show_col_types = FALSE) |>
  standardize_movebank_columns() |>
  mutate(ts = parse_movebank_ts(timestamp, tz = cfg$project$timezone)) |>
  filter(!is.na(ts), !is.na(lat), !is.na(lon)) |>
  arrange(id, ts)

n_raw <- nrow(raw)

clean <- raw |>
  distinct(id, ts, .keep_all = TRUE) |>
  group_by(id) |>
  arrange(ts, .by_group = TRUE) |>
  mutate(
    dt_sec = as.numeric(difftime(ts, lag(ts), units = "secs")),
    calc_spd = haversine_speed(lag(lon), lag(lat), lon, lat, dt_sec)
  ) |>
  filter(is.na(calc_spd) | (dt_sec > 0 & calc_spd < cfg$cleaning$speed_max_ms)) |>
  ungroup() |>
  filter(dplyr::between(lat, -90, 90), dplyr::between(lon, -180, 180))

keep_ids <- clean |>
  count(id, name = "n_points") |>
  filter(n_points >= cfg$cleaning$min_points_per_id) |>
  pull(id)

clean <- clean |>
  filter(id %in% keep_ids)

write_csv(clean, paths$clean_csv)

summary_tbl <- clean |>
  group_by(id) |>
  summarise(
    n = n(),
    start_time = min(ts),
    end_time = max(ts),
    median_dt_min = median(dt_sec, na.rm = TRUE) / 60,
    max_speed_m_s = max(calc_spd, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(summary_tbl, file.path(paths$tables_dir, "03_clean_tracking_summary.csv"))

cat("=== 轨迹清洗完成 ===
")
cat("原始记录数:", n_raw, "
")
cat("清洗后记录数:", nrow(clean), "
")
cat("个体数:", n_distinct(clean$id), "
")
