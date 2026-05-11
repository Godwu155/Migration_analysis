library(readr)
library(dplyr)
library(ggplot2)
library(tidyr)

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

stops_path <- if (file.exists(paths$stopover_events_env_csv)) {
  paths$stopover_events_env_csv
} else {
  paths$stopovers_csv
}

out_table <- file.path(paths$tables_dir, "11_climate_scenario_projection.csv")
out_summary <- file.path(paths$tables_dir, "11_climate_scenario_summary.csv")
out_fig <- file.path(paths$figures_dir, "11_climate_scenario_projection.png")

# =========================
# 读取停歇地
# =========================
stops <- read_csv(stops_path, show_col_types = FALSE)

params_path <- file.path(paths$tables_dir, "10_optimal_stopping_params.csv")
if (!file.exists(params_path)) stop("找不到 D 模块参数文件: ", params_path)

params <- read_csv(params_path, show_col_types = FALSE)
lambda_proxy <- params$lambda_proxy[[1]]
Qstar_proxy <- params$Qstar_proxy[[1]]
if (!is.finite(lambda_proxy) || !is.finite(Qstar_proxy)) {
  stop("D 模块参数 lambda_proxy/Qstar_proxy 不可用，请先检查 10_optimal_stopping_params.csv")
}

# =========================
# 基础筛选
# 保持和敏感性模型一致
# =========================
stops_model <- stops %>%
  filter(
    duration_hr > 0,
    duration_hr <= 240,
    !is.na(ndvi_arrive),
    !is.na(wind_support)
  ) %>%
  mutate(
    Q0_current = pmin(pmax(ndvi_arrive, 0.001), 1)
  )

cat("进入 E 模块的停歇地数量:", nrow(stops_model), "\n")

# =========================
# 最优停止预测函数
# Δt* = log(Q0 / Q*) / λ
# 注意：当 Q0 <= Q* 时，理论预测会小于等于 0
# 这里设置最低预测停留时长为 0
# =========================
predict_duration <- function(Q0, lambda, Qstar) {
  Q0_safe <- pmin(pmax(Q0, 0.001), 1)
  pred <- log(Q0_safe / Qstar) / lambda
  pmax(pred, 0)
}

# =========================
# 设置资源变化情景
# =========================
scenarios <- tibble(
  scenario = c(
    "current",
    "ndvi_minus_5",
    "ndvi_minus_10",
    "ndvi_minus_20",
    "ndvi_plus_5"
  ),
  ndvi_multiplier = c(
    1.00,
    0.95,
    0.90,
    0.80,
    1.05
  ),
  scenario_label = c(
    "当前 NDVI",
    "NDVI 下降 5%",
    "NDVI 下降 10%",
    "NDVI 下降 20%",
    "NDVI 上升 5%"
  )
)

# =========================
# 情景预测
# =========================
projection <- tidyr::crossing(
  stops_model,
  scenarios
) %>%
  mutate(
    ndvi_projected = pmin(pmax(ndvi_arrive * ndvi_multiplier, 0.001), 1),
    pred_duration_hr = predict_duration(
      Q0 = ndvi_projected,
      lambda = lambda_proxy,
      Qstar = Qstar_proxy
    ),
    pred_duration_current = predict_duration(
      Q0 = Q0_current,
      lambda = lambda_proxy,
      Qstar = Qstar_proxy
    ),
    duration_change_hr = pred_duration_hr - pred_duration_current,
    duration_change_pct = ifelse(
      pred_duration_current > 0,
      duration_change_hr / pred_duration_current * 100,
      NA_real_
    ),
    risk_class = case_when(
      ndvi_projected < Qstar_proxy ~ "高风险：低于离开阈值",
      ndvi_projected < Qstar_proxy * 1.1 ~ "中风险：接近离开阈值",
      TRUE ~ "低风险"
    )
  )

# =========================
# 汇总结果
# =========================
summary_tbl <- projection %>%
  group_by(scenario, scenario_label) %>%
  summarise(
    n = n(),
    mean_ndvi = mean(ndvi_projected, na.rm = TRUE),
    median_ndvi = median(ndvi_projected, na.rm = TRUE),
    mean_pred_duration_hr = mean(pred_duration_hr, na.rm = TRUE),
    median_pred_duration_hr = median(pred_duration_hr, na.rm = TRUE),
    mean_change_hr = mean(duration_change_hr, na.rm = TRUE),
    median_change_hr = median(duration_change_hr, na.rm = TRUE),
    high_risk_n = sum(risk_class == "高风险：低于离开阈值", na.rm = TRUE),
    medium_risk_n = sum(risk_class == "中风险：接近离开阈值", na.rm = TRUE),
    low_risk_n = sum(risk_class == "低风险", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(match(
    scenario,
    c("current", "ndvi_minus_5", "ndvi_minus_10", "ndvi_minus_20", "ndvi_plus_5")
  ))

print(summary_tbl, n = Inf)

write_csv(projection, out_table)
write_csv(summary_tbl, out_summary)

# =========================
# 绘图
# =========================
p <- ggplot(summary_tbl, aes(
  x = scenario_label,
  y = mean_pred_duration_hr
)) +
  geom_col(width = 0.65) +
  geom_text(
    aes(label = round(mean_pred_duration_hr, 1)),
    vjust = -0.4,
    size = 4
  ) +
  theme_bw() +
  labs(
    title = "不同 NDVI 情景下的预测停留时长",
    x = "气候/资源情景",
    y = "平均预测停留时长（小时）"
  ) +
  theme(
    axis.text.x = element_text(angle = 25, hjust = 1)
  )

ggsave(out_fig, p, width = 8, height = 5, dpi = 300)

cat("=== E 模块探索性情景预测完成 ===\n")
cat("详细预测输出:", out_table, "\n")
cat("情景汇总输出:", out_summary, "\n")
cat("图像输出:", out_fig, "\n")
