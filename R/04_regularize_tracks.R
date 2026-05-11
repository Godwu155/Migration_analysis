library(readr)
library(dplyr)
library(lubridate)
library(amt)
library(sf)
library(purrr)
library(tibble)

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

infile <- paths$clean_csv
outfile <- paths$regular_csv

# ===== 读取数据 =====
df <- read_csv(infile, show_col_types = FALSE)

# ===== 安全处理 ts =====
# 如果 ts 已经是 datetime，就不要再 ymd_hms()
if (inherits(df$ts, "POSIXt")) {
  df <- df %>%
    mutate(ts_raw = as.character(ts),
           ts = as.POSIXct(ts, tz = "UTC"))
} else {
  df <- df %>%
    mutate(ts_raw = as.character(ts),
           ts = parse_date_time(
             ts_raw,
             orders = c("Ymd HMS", "Y-m-d H:M:S", "Y/m/d H:M:S"),
             tz = "UTC",
             quiet = TRUE
           ))
}

# ===== 检查坏时间 =====
bad_ts <- df %>% filter(is.na(ts))
cat("无法解析的时间行数:", nrow(bad_ts), "\n")
if (nrow(bad_ts) > 0) {
  print(bad_ts %>% select(id, ts_raw, lat, lon), n = 20)
  write_csv(bad_ts, file.path(paths$tables_dir, "bad_ts_rows.csv"))
}

# ===== 基础清理 =====
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

# ===== 自动选择 amt 的规则化函数 =====
resample_fun <- NULL

if ("track_resample" %in% getNamespaceExports("amt")) {
  resample_fun <- amt::track_resample
} else if ("trk_resample" %in% getNamespaceExports("amt")) {
  resample_fun <- amt::trk_resample
} else {
  stop("你的 amt 包里既没有 track_resample() 也没有 trk_resample()，请先更新 amt：install.packages('amt')")
}

# ===== 安全规则化 =====
safe_regularize <- function(x) {
  x <- x %>%
    arrange(ts) %>%
    filter(!is.na(ts)) %>%
    distinct(ts, .keep_all = TRUE)
  
  # 至少两个点
  if (nrow(x) < 2) return(NULL)
  
  # 时间必须有限
  if (any(!is.finite(as.numeric(x$ts)))) return(NULL)
  
  # 时间跨度必须大于0
  if (min(x$ts) >= max(x$ts)) return(NULL)
  
  # 转为 track
  trk <- make_track(x, lon, lat, ts, crs = 4326)
  
  # 规则化
  out <- resample_fun(
    trk,
    rate = hours(1),
    tolerance = minutes(20)
  )
  
  if (nrow(out) == 0) return(NULL)
  
  out <- as_tibble(out)
  
  # 某些版本 amt 不一定保留 id，这里补回去
  if (!"id" %in% names(out)) {
    out$id <- x$id[1]
  }
  
  out
}

# ===== 分个体规则化 =====
split_list <- df %>% group_by(id) %>% group_split()

df_reg_list <- map(split_list, safe_regularize)

kept_n <- map_int(df_reg_list, ~ if (is.null(.x)) 0 else nrow(.x))
skipped_ids <- map_chr(split_list[kept_n == 0], ~ as.character(.x$id[1]))

cat("被跳过的个体数:", length(skipped_ids), "\n")
if (length(skipped_ids) > 0) {
  print(skipped_ids)
  write_csv(tibble(id = skipped_ids), file.path(paths$tables_dir, "skipped_ids_regularize.csv"))
}

df_reg <- bind_rows(df_reg_list)

# ===== 结果检查 =====
# amt 输出通常有 t_ 列；如果没有，就退回 ts
time_col <- if ("t_" %in% names(df_reg)) "t_" else "ts"

check_tbl <- df_reg %>%
  group_by(id) %>%
  summarise(
    n = n(),
    dt_med = median(diff(as.numeric(.data[[time_col]])) / 3600, na.rm = TRUE),
    .groups = "drop"
  )

print(check_tbl, n = Inf)

write_csv(df_reg, outfile)
write_csv(check_tbl, file.path(paths$tables_dir, "regularize_check.csv"))

cat("规则化完成，输出行数:", nrow(df_reg), "\n")
cat("输出文件:", outfile, "\n")
