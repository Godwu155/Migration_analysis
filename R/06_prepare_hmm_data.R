#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(moveHMM)
  library(jsonlite)
})
source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

if (!file.exists(paths$env_csv)) stop("找不到环境匹配结果: ", paths$env_csv)
if (!file.exists(paths$env_ndvi_csv)) {
  stop("找不到 NDVI 环境匹配结果: ", paths$env_ndvi_csv, "。请先运行 R/05b_match_ndvi.R")
}

df <- read_csv(paths$env_ndvi_csv, show_col_types = FALSE) |>
  mutate(ts = ymd_hms(ts, tz = cfg$project$timezone)) |>
  filter(!is.na(ts), !is.na(lat), !is.na(lon)) |>
  arrange(id, ts)

required_covs <- c("temp_C", "wind_support", "wind_speed", "ndvi")
miss <- setdiff(required_covs, names(df))
if (length(miss) > 0) stop("缺少列: ", paste(miss, collapse = ", "))

df <- df |>
  group_by(id) |>
  mutate(
    dt_hr = as.numeric(difftime(ts, lag(ts), units = "hours")),
    new_burst = is.na(dt_hr) | dt_hr < 0.9 | dt_hr > 1.1,
    burst_no = cumsum(new_burst),
    burst_id = paste(id, burst_no, sep = "_")
  ) |>
  ungroup()

keep_bursts <- df |>
  count(burst_id, name = "n") |>
  filter(n >= cfg$hmm$min_burst_n) |>
  pull(burst_id)

df_hmm <- df |>
  filter(burst_id %in% keep_bursts) |>
  transmute(
    ID = burst_id,
    original_id = id,
    ts = ts,
    lon = lon,
    lat = lat,
    temp_C = temp_C,
    wind_support = wind_support,
    wind_speed = wind_speed,
    ndvi = ndvi,
    temp_z = as.numeric(scale(temp_C)),
    wind_support_z = as.numeric(scale(wind_support)),
    wind_speed_z = as.numeric(scale(wind_speed))
  )

prep <- prepData(df_hmm, type = "LL", coordNames = c("lon", "lat")) |>
  filter(is.na(step) | step <= cfg$hmm$max_step_km)

write_csv(prep, paths$hmm_prep_csv)
write_rds(prep, paths$hmm_prep_rds)

summary_tbl <- tibble(
  rows = nrow(prep),
  bursts = n_distinct(prep$ID),
  original_ids = n_distinct(prep$original_id),
  step_na = sum(is.na(prep$step)),
  angle_na = sum(is.na(prep$angle)),
  max_step = max(prep$step, na.rm = TRUE)
)
write_csv(summary_tbl, file.path(paths$tables_dir, "06_prepare_hmm_summary.csv"))
cat("=== HMM 输入数据完成 ===
")
print(summary_tbl)
