#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(jsonlite)
})

if (!file.exists(file.path("R", "00_config.R"))) {
  root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(root) && file.exists(file.path(root, "R", "00_config.R"))) {
    setwd(root)
  } else {
    stop("请从项目根目录运行，或设置 PROJECT_ROOT 指向项目根目录。")
  }
}

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

if (!file.exists(paths$stopovers_csv)) {
  stop("找不到 stopovers 文件: ", paths$stopovers_csv)
}

stopovers_path <- if (file.exists(paths$stopover_events_env_csv)) {
  paths$stopover_events_env_csv
} else {
  paths$stopovers_csv
}

stops_raw <- read_csv(stopovers_path, show_col_types = FALSE)

cat("=== stopovers 原始信息 ===\n")
cat("文件:", stopovers_path, "\n")
cat("原始停歇地数量:", nrow(stops_raw), "\n")
cat("列名:\n")
print(names(stops_raw))

# 兼容不同字段命名
stops <- stops_raw

if (!"individual_id" %in% names(stops)) {
  if ("id" %in% names(stops)) {
    stops <- stops |> mutate(individual_id = id)
  } else if ("original_id" %in% names(stops)) {
    stops <- stops |> mutate(individual_id = original_id)
  } else {
    stops <- stops |> mutate(individual_id = "unknown")
  }
}

# duration 字段兼容
if (!"duration_hr" %in% names(stops)) {
  if (all(c("arrive_time", "depart_time") %in% names(stops))) {
    stops <- stops |>
      mutate(
        arrive_time = as.POSIXct(arrive_time, tz = cfg$project$timezone),
        depart_time = as.POSIXct(depart_time, tz = cfg$project$timezone),
        duration_hr = as.numeric(difftime(depart_time, arrive_time, units = "hours"))
      )
  } else {
    stop("stopovers 文件中没有 duration_hr，也没有 arrive_time/depart_time，无法计算停留时长。")
  }
}

# 资源质量变量：优先 NDVI；如果没有，则用 temp_C/temp_mean 作为临时替代资源/环境变量。
resource_source <- NA_character_
if ("ndvi_arrive" %in% names(stops) && sum(!is.na(stops$ndvi_arrive)) >= 5) {
  stops <- stops |> mutate(resource_raw = ndvi_arrive)
  resource_source <- "ndvi_arrive"
} else if ("ndvi_mean" %in% names(stops) && sum(!is.na(stops$ndvi_mean)) >= 5) {
  stops <- stops |> mutate(resource_raw = ndvi_mean)
  resource_source <- "ndvi_mean"
} else if ("temp_C" %in% names(stops) && sum(!is.na(stops$temp_C)) >= 5) {
  stops <- stops |> mutate(resource_raw = temp_C)
  resource_source <- "temp_C"
} else if ("temp_mean" %in% names(stops) && sum(!is.na(stops$temp_mean)) >= 5) {
  stops <- stops |> mutate(resource_raw = temp_mean)
  resource_source <- "temp_mean"
} else {
  stops <- stops |> mutate(resource_raw = NA_real_)
}

# 风变量兼容
if (!"wind_support" %in% names(stops)) {
  if ("wind_support_mean" %in% names(stops)) {
    stops <- stops |> mutate(wind_support = wind_support_mean)
  } else {
    stops <- stops |> mutate(wind_support = NA_real_)
  }
}

qc <- tibble(
  n_raw = nrow(stops),
  duration_na = sum(is.na(stops$duration_hr)),
  duration_nonpositive = sum(!is.na(stops$duration_hr) & stops$duration_hr <= 0),
  resource_source = resource_source,
  resource_na = sum(is.na(stops$resource_raw)),
  wind_support_na = sum(is.na(stops$wind_support)),
  min_duration_hr = suppressWarnings(min(stops$duration_hr, na.rm = TRUE)),
  median_duration_hr = suppressWarnings(median(stops$duration_hr, na.rm = TRUE)),
  max_duration_hr = suppressWarnings(max(stops$duration_hr, na.rm = TRUE))
)
write_csv(qc, file.path(paths$tables_dir, "10_stopovers_qc.csv"))
cat("=== stopovers 质检 ===\n")
print(qc)

# 基础过滤：先不强制 NDVI，避免 0 行
stops_model <- stops |>
  filter(
    !is.na(duration_hr),
    duration_hr >= cfg$stopover$min_duration_hr,
    duration_hr <= cfg$stopover$max_duration_hr,
    duration_hr >= 2,
    duration_hr <= 240,
    !is.na(ndvi_arrive),
    !is.na(wind_support)
  )

# 如果资源变量有效，用资源变量；否则只用风；如果风也不够，就只做描述，不拟合。
use_resource <- "resource_raw" %in% names(stops_model) && sum(!is.na(stops_model$resource_raw)) >= 5
use_wind <- "wind_support" %in% names(stops_model) && sum(!is.na(stops_model$wind_support)) >= 5

if (use_resource) {
  stops_model <- stops_model |> filter(!is.na(resource_raw))
}
if (use_wind) {
  stops_model <- stops_model |> filter(!is.na(wind_support))
}

cat("可用于模型的停歇地数量:", nrow(stops_model), "\n")

if (nrow(stops_model) < 5) {
  write_csv(stops_model, file.path(paths$tables_dir, "10_optimal_stopping_model_input_empty.csv"))
  stop("可用停歇地少于 5 个，无法建模。请查看 output/tables/10_stopovers_qc.csv。最常见原因是 NDVI/temp/wind 字段缺失。")
}

# 构造建模变量
stops_model <- stops_model |>
  mutate(
    log_dur = log(duration_hr),
    resource_z = if (use_resource) as.numeric(scale(resource_raw)) else NA_real_,
    wind_z = if (use_wind) as.numeric(scale(wind_support)) else NA_real_
  )

# 根据可用变量自动选择公式
if (use_resource && use_wind) {
  form <- log_dur ~ resource_z + wind_z
  formula_text <- paste0("log(duration_hr) ~ ", resource_source, "_z + wind_support_z")
} else if (use_resource) {
  form <- log_dur ~ resource_z
  formula_text <- paste0("log(duration_hr) ~ ", resource_source, "_z")
} else if (use_wind) {
  form <- log_dur ~ wind_z
  formula_text <- "log(duration_hr) ~ wind_support_z"
} else {
  form <- log_dur ~ 1
  formula_text <- "log(duration_hr) ~ 1"
}

# 33 个停歇地样本偏少，默认先用 lm；lmer 容易因为有效样本或个体数不足报错。
m1 <- lm(form, data = stops_model)
model_summary <- summary(m1)
print(model_summary)

saveRDS(m1, file.path(paths$models_dir, paste0(cfg$project$species_code, "_os_lm.rds")))

coef_tbl <- as.data.frame(coef(model_summary))
coef_tbl$term <- rownames(coef_tbl)
rownames(coef_tbl) <- NULL
coef_tbl <- coef_tbl |> relocate(term)
write_csv(coef_tbl, file.path(paths$tables_dir, "10_optimal_stopping_lm_coefficients.csv"))

stops_model <- stops_model |>
  mutate(
    pred_log_dur = predict(m1),
    pred_duration_hr = exp(pred_log_dur)
  )

rmse <- sqrt(mean((stops_model$duration_hr - stops_model$pred_duration_hr)^2, na.rm = TRUE))
r2 <- suppressWarnings(cor(stops_model$duration_hr, stops_model$pred_duration_hr, use = "complete.obs")^2)

# 如果存在资源变量，额外给出一个近似阈值模型结果，作为“最优停止”接口。
# 注意：没有 NDVI 时，这只是临时环境代理模型，不应解释为正式资源质量阈值。
if (use_resource) {
  rescaled_Q0 <- scales::rescale(stops_model$resource_raw, to = c(0.01, 1.0))
  qstar <- stats::quantile(rescaled_Q0, probs = 0.25, na.rm = TRUE)
  lambda <- 1 / max(stats::sd(stops_model$duration_hr, na.rm = TRUE), 1e-6)
} else {
  qstar <- NA_real_
  lambda <- NA_real_
}

params <- tibble(
  model = formula_text,
  n = nrow(stops_model),
  resource_source = resource_source,
  lambda_proxy = lambda,
  Qstar_proxy = as.numeric(qstar),
  rmse = rmse,
  r2 = r2,
  note = ifelse(resource_source %in% c("ndvi_arrive", "ndvi_mean"),
                "NDVI resource model",
                "temporary proxy model; add NDVI for formal optimal stopping")
)

write_csv(params, file.path(paths$tables_dir, "10_optimal_stopping_params.csv"))
write_csv(stops_model, file.path(paths$tables_dir, "10_optimal_stopping_predictions.csv"))

p <- ggplot(stops_model, aes(duration_hr, pred_duration_hr)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = 2) +
  theme_bw(base_size = 12) +
  labs(
    x = "Observed stopover duration (hr)",
    y = "Predicted stopover duration (hr)",
    title = "Stopover duration model",
    subtitle = formula_text
  )

ggsave(file.path(paths$figures_dir, "10_optimal_stopping_pred_obs.png"), p, width = 7, height = 5, dpi = 300)

cat("=== 最优停止/停歇时长模型完成 ===\n")
print(params)
cat("系数输出: ", file.path(paths$tables_dir, "10_optimal_stopping_lm_coefficients.csv"), "\n", sep = "")
cat("预测输出: ", file.path(paths$tables_dir, "10_optimal_stopping_predictions.csv"), "\n", sep = "")
cat("质检输出: ", file.path(paths$tables_dir, "10_stopovers_qc.csv"), "\n", sep = "")
