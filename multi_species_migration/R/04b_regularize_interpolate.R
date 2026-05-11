library(readr)
library(dplyr)
library(lubridate)
library(purrr)
library(tibble)

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

infile <- paths$clean_csv
outfile <- file.path(dirname(paths$regular_csv), paste0(cfg$project$species_code, "_regular_1h.csv"))

df <- read_csv(infile, show_col_types = FALSE)

# ts 安全处理
if (inherits(df$ts, "POSIXt")) {
  df <- df %>%
    mutate(ts = as.POSIXct(ts, tz = "UTC"))
} else {
  df <- df %>%
    mutate(
      ts = parse_date_time(
        as.character(ts),
        orders = c("Ymd HMS", "Y-m-d H:M:S", "Y/m/d H:M:S"),
        tz = "UTC",
        quiet = TRUE
      )
    )
}

df <- df %>%
  filter(
    !is.na(ts),
    !is.na(lat), !is.na(lon),
    is.finite(lat), is.finite(lon),
    between(lat, -90, 90),
    between(lon, -180, 180)
  ) %>%
  arrange(id, ts) %>%
  distinct(id, ts, .keep_all = TRUE)

# 单个 burst 内做严格 1h 插值
interp_one_burst <- function(x) {
  x <- x %>% arrange(ts)
  
  if (nrow(x) < 2) return(NULL)
  
  sec <- as.numeric(x$ts)
  
  start_sec <- ceiling(min(sec) / 3600) * 3600
  end_sec   <- floor(max(sec) / 3600) * 3600
  
  if (!is.finite(start_sec) || !is.finite(end_sec) || start_sec >= end_sec) {
    return(NULL)
  }
  
  grid_sec <- seq(from = start_sec, to = end_sec, by = 3600)
  
  if (length(grid_sec) < 2) return(NULL)
  
  lon_i <- approx(sec, x$lon, xout = grid_sec, method = "linear", ties = "ordered")$y
  lat_i <- approx(sec, x$lat, xout = grid_sec, method = "linear", ties = "ordered")$y
  
  tibble(
    id  = x$id[1],
    ts  = as.POSIXct(grid_sec, origin = "1970-01-01", tz = "UTC"),
    lon = lon_i,
    lat = lat_i,
    burst_id = x$burst_id[1]
  )
}

# 先按大时间断裂切 burst，避免跨很长空档乱插值
make_regular_id <- function(x, gap_hours = 3) {
  x <- x %>% arrange(ts)
  
  if (nrow(x) < 2) return(NULL)
  
  dt_hr <- c(NA, diff(as.numeric(x$ts)) / 3600)
  
  x <- x %>%
    mutate(
      dt_hr = dt_hr,
      burst_id = cumsum(if_else(is.na(dt_hr) | dt_hr > gap_hours, 1L, 0L))
    )
  
  burst_list <- x %>% group_by(burst_id) %>% group_split()
  
  out <- map(burst_list, interp_one_burst) %>% bind_rows()
  
  if (nrow(out) == 0) return(NULL)
  out
}

split_list <- df %>% group_by(id) %>% group_split()

reg_list <- map(split_list, make_regular_id)
df_reg <- bind_rows(reg_list)

check_tbl <- df_reg %>%
  group_by(id) %>%
  summarise(
    n = n(),
    dt_med = median(diff(as.numeric(ts)) / 3600, na.rm = TRUE),
    .groups = "drop"
  )

print(check_tbl, n = Inf)

write_csv(df_reg, outfile)
write_csv(check_tbl, file.path(paths$tables_dir, "regularize_check_1h.csv"))

cat("严格1小时规则化完成，输出行数:", nrow(df_reg), "\n")
cat("输出文件:", outfile, "\n")
