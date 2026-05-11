#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

if (!file.exists(paths$states_csv)) stop("找不到状态解码文件: ", paths$states_csv)
if (!file.exists(paths$env_ndvi_csv)) stop("找不到 NDVI 环境匹配文件: ", paths$env_ndvi_csv)

states <- read_csv(paths$states_csv, show_col_types = FALSE)
env <- read_csv(paths$env_ndvi_csv, show_col_types = FALSE)

if (!"ts" %in% names(states) && "t_" %in% names(states)) {
  states <- states |> mutate(ts = t_)
}

id_col <- c("original_id", "id", "ID")[c("original_id", "id", "ID") %in% names(states)][1]
if (is.na(id_col)) stop("states 文件中找不到 original_id / id / ID")

states <- states |> mutate(ts = as.POSIXct(ts, tz = cfg$project$timezone))
env <- env |>
  mutate(ts = as.POSIXct(ts, tz = cfg$project$timezone)) |>
  select(id, ts, ndvi, ndvi_raw, ts_ndvi, ndvi_time_diff_hr, lon_ndvi, lat_ndvi)

states_new <- states |>
  select(-any_of(c("ndvi", "ndvi_raw", "ts_ndvi", "ndvi_time_diff_hr", "lon_ndvi", "lat_ndvi"))) |>
  left_join(env, by = setNames(c("id", "ts"), c(id_col, "ts")))

write_csv(states_new, paths$states_env_csv)

qc <- states_new |>
  summarise(
    n = n(),
    ndvi_na = sum(is.na(ndvi)),
    ndvi_na_rate = mean(is.na(ndvi)),
    ndvi_median = median(ndvi, na.rm = TRUE)
  )

write_csv(qc, file.path(paths$tables_dir, "08b_states_ndvi_qc.csv"))
print(qc)
cat("已将 NDVI 补入状态文件，输出:", paths$states_env_csv, "\n")
