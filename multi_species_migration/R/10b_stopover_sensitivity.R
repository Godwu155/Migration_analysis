library(readr)
library(dplyr)
library(ggplot2)
library(broom)
library(tibble)

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

stop_path <- if (file.exists(paths$stopover_events_env_csv)) {
  paths$stopover_events_env_csv
} else {
  paths$stopovers_csv
}
out_table_dir <- paths$tables_dir
out_fig_dir <- paths$figures_dir

# =========================
# 读取数据
# =========================
stops <- read_csv(stop_path, show_col_types = FALSE)

# =========================
# 基础质检
# =========================
cat("=== stopovers 基本信息 ===\n")
cat("停歇地数量:", nrow(stops), "\n")
cat("列名:\n")
print(names(stops))

# 确保关键变量存在
need_cols <- c("duration_hr", "ndvi_arrive", "ndvi_mean", "wind_support")
miss_cols <- setdiff(need_cols, names(stops))

if (length(miss_cols) > 0) {
  stop("缺少必要列: ", paste(miss_cols, collapse = ", "))
}

# =========================
# 时长分布统计
# =========================
duration_summary <- stops %>%
  summarise(
    n = n(),
    duration_na = sum(is.na(duration_hr)),
    min = min(duration_hr, na.rm = TRUE),
    q25 = quantile(duration_hr, 0.25, na.rm = TRUE),
    median = median(duration_hr, na.rm = TRUE),
    mean = mean(duration_hr, na.rm = TRUE),
    q75 = quantile(duration_hr, 0.75, na.rm = TRUE),
    q90 = quantile(duration_hr, 0.90, na.rm = TRUE),
    q95 = quantile(duration_hr, 0.95, na.rm = TRUE),
    max = max(duration_hr, na.rm = TRUE)
  )

cat("=== 停歇时长分布 ===\n")
print(duration_summary)

write_csv(
  duration_summary,
  file.path(out_table_dir, "10b_stopover_duration_summary.csv")
)

# =========================
# 极端停歇地列表
# =========================
long_stopovers <- stops %>%
  arrange(desc(duration_hr)) %>%
  select(
    any_of(c(
      "cluster_id",
      "event_id",
      "site_id",
      "individual_id",
      "duration_hr",
      "ndvi_arrive",
      "ndvi_mean",
      "wind_support",
      "n_points",
      "n_state_points"
    )),
    everything()
  )

cat("=== 停歇时长从大到小排列 ===\n")
print(long_stopovers, n = Inf)

write_csv(
  long_stopovers,
  file.path(out_table_dir, "10b_stopovers_ordered_by_duration.csv")
)

# =========================
# 作图 1：停歇时长直方图
# =========================
p1 <- ggplot(stops, aes(x = duration_hr)) +
  geom_histogram(bins = 20) +
  theme_bw(base_size = 12) +
  labs(
    title = "停歇地停留时长分布",
    x = "Duration (hours)",
    y = "Count"
  )

ggsave(
  file.path(out_fig_dir, "10b_duration_histogram.png"),
  p1,
  width = 7,
  height = 5,
  dpi = 300
)

# =========================
# 作图 2：log 时长直方图
# =========================
p2 <- stops %>%
  filter(duration_hr > 0) %>%
  ggplot(aes(x = log(duration_hr))) +
  geom_histogram(bins = 20) +
  theme_bw(base_size = 12) +
  labs(
    title = "log(停歇时长) 分布",
    x = "log(Duration hours)",
    y = "Count"
  )

ggsave(
  file.path(out_fig_dir, "10b_log_duration_histogram.png"),
  p2,
  width = 7,
  height = 5,
  dpi = 300
)

# =========================
# 作图 3：箱线图
# =========================
p3 <- ggplot(stops, aes(y = duration_hr)) +
  geom_boxplot() +
  theme_bw(base_size = 12) +
  labs(
    title = "停歇时长箱线图",
    x = "",
    y = "Duration (hours)"
  )

ggsave(
  file.path(out_fig_dir, "10b_duration_boxplot.png"),
  p3,
  width = 5,
  height = 6,
  dpi = 300
)

# =========================
# 作图 4：NDVI 与停留时长
# =========================
p4 <- stops %>%
  filter(duration_hr > 0, !is.na(ndvi_arrive)) %>%
  ggplot(aes(x = ndvi_arrive, y = log(duration_hr))) +
  geom_point(size = 2, alpha = 0.8) +
  geom_smooth(method = "lm", se = TRUE) +
  theme_bw(base_size = 12) +
  labs(
    title = "NDVI 与 log(停留时长)",
    x = "NDVI at arrival",
    y = "log(Duration hours)"
  )

ggsave(
  file.path(out_fig_dir, "10b_ndvi_vs_log_duration.png"),
  p4,
  width = 7,
  height = 5,
  dpi = 300
)

# =========================
# 作图 5：风支持与停留时长
# =========================
p5 <- stops %>%
  filter(duration_hr > 0, !is.na(wind_support)) %>%
  ggplot(aes(x = wind_support, y = log(duration_hr))) +
  geom_point(size = 2, alpha = 0.8) +
  geom_smooth(method = "lm", se = TRUE) +
  theme_bw(base_size = 12) +
  labs(
    title = "风支持与 log(停留时长)",
    x = "Wind support",
    y = "log(Duration hours)"
  )

ggsave(
  file.path(out_fig_dir, "10b_wind_vs_log_duration.png"),
  p5,
  width = 7,
  height = 5,
  dpi = 300
)

# =========================
# 模型函数
# =========================
fit_sensitivity_model <- function(data, model_name) {
  dat <- data %>%
    filter(
      !is.na(duration_hr),
      duration_hr > 0,
      !is.na(ndvi_arrive),
      !is.na(wind_support)
    ) %>%
    mutate(
      log_duration = log(duration_hr),
      ndvi_z = as.numeric(scale(ndvi_arrive)),
      wind_z = as.numeric(scale(wind_support))
    )
  
  if (nrow(dat) < 8) {
    return(list(
      summary = tibble(
        model_name = model_name,
        n = nrow(dat),
        formula = NA_character_,
        r2 = NA_real_,
        adj_r2 = NA_real_,
        aic = NA_real_,
        note = "样本量过小，未建模"
      ),
      coef = tibble()
    ))
  }
  
  fit <- lm(log_duration ~ ndvi_z + wind_z, data = dat)
  
  s <- summary(fit)
  
  summary_tbl <- tibble(
    model_name = model_name,
    n = nrow(dat),
    formula = "log(duration_hr) ~ ndvi_arrive_z + wind_support_z",
    r2 = s$r.squared,
    adj_r2 = s$adj.r.squared,
    aic = AIC(fit),
    ndvi_estimate = coef(s)["ndvi_z", "Estimate"],
    ndvi_p = coef(s)["ndvi_z", "Pr(>|t|)"],
    wind_estimate = coef(s)["wind_z", "Estimate"],
    wind_p = coef(s)["wind_z", "Pr(>|t|)"],
    note = "完成"
  )
  
  coef_tbl <- broom::tidy(fit) %>%
    mutate(
      model_name = model_name,
      n = nrow(dat)
    ) %>%
    select(model_name, n, everything())
  
  list(
    summary = summary_tbl,
    coef = coef_tbl,
    data = dat,
    fit = fit
  )
}

# =========================
# 三组敏感性数据
# =========================
data_all <- stops %>%
  filter(duration_hr >= 2)

data_no_extreme <- stops %>%
  filter(
    duration_hr >= 2,
    duration_hr <= 240
  )

data_migration_strict <- stops %>%
  filter(
    duration_hr >= 2,
    duration_hr <= 168
  )

# =========================
# 拟合模型
# =========================
res_all <- fit_sensitivity_model(
  data_all,
  "全部可用停歇地 duration >= 2h"
)

res_no_extreme <- fit_sensitivity_model(
  data_no_extreme,
  "排除极长停留 2h <= duration <= 240h"
)

res_strict <- fit_sensitivity_model(
  data_migration_strict,
  "严格迁徙停歇 2h <= duration <= 168h"
)

summary_all <- bind_rows(
  res_all$summary,
  res_no_extreme$summary,
  res_strict$summary
)

coef_all <- bind_rows(
  res_all$coef,
  res_no_extreme$coef,
  res_strict$coef
)

cat("=== 敏感性模型汇总 ===\n")
print(summary_all)

cat("=== 敏感性模型系数 ===\n")
print(coef_all)

write_csv(
  summary_all,
  file.path(out_table_dir, "10b_stopover_sensitivity_summary.csv")
)

write_csv(
  coef_all,
  file.path(out_table_dir, "10b_stopover_sensitivity_coefficients.csv")
)

# =========================
# 输出每个子集的样本数量
# =========================
subset_count <- tibble(
  subset = c(
    "全部原始停歇地",
    "duration >= 2h",
    "2h <= duration <= 240h",
    "2h <= duration <= 168h"
  ),
  n = c(
    nrow(stops),
    nrow(data_all),
    nrow(data_no_extreme),
    nrow(data_migration_strict)
  )
)

print(subset_count)

write_csv(
  subset_count,
  file.path(out_table_dir, "10b_stopover_subset_counts.csv")
)

cat("=== 停歇时长分布与敏感性模型完成 ===\n")
cat("输出表格目录:", out_table_dir, "\n")
cat("输出图片目录:", out_fig_dir, "\n")
