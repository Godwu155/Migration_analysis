#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(jsonlite)
})
source(file.path("R", "00_config.R"))
source(file.path("R", "01_utils.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

if (!file.exists(paths$raw_csv)) stop("找不到原始数据: ", paths$raw_csv)

raw <- read_csv(paths$raw_csv, show_col_types = FALSE)
raw_std <- standardize_movebank_columns(raw) |>
  mutate(ts = parse_movebank_ts(timestamp, tz = cfg$project$timezone))

summary_tbl <- tibble(
  rows = nrow(raw_std),
  individuals = n_distinct(raw_std$id),
  time_min = as.character(min(raw_std$ts, na.rm = TRUE)),
  time_max = as.character(max(raw_std$ts, na.rm = TRUE)),
  lat_na = sum(is.na(raw_std$lat)),
  lon_na = sum(is.na(raw_std$lon)),
  ts_na = sum(is.na(raw_std$ts))
)

write_csv(summary_tbl, file.path(paths$tables_dir, "00_raw_summary.csv"))
cat("=== 原始数据检查完成 ===
")
print(summary_tbl)
