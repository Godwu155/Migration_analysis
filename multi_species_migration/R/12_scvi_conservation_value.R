library(readr)
library(dplyr)
library(ggplot2)
library(tidyr)
library(scales)

source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

stops_path <- if (file.exists(paths$stopover_events_env_csv)) {
  paths$stopover_events_env_csv
} else {
  paths$stopovers_csv
}
projection_path <- file.path(paths$tables_dir, "11_climate_scenario_projection.csv")

out_table <- file.path(paths$tables_dir, "12_scvi_stopover_ranking.csv")
out_stability <- file.path(paths$tables_dir, "12_scvi_rank_stability.csv")
out_summary <- file.path(paths$tables_dir, "12_project_result_summary.csv")
out_fig_bar <- file.path(paths$figures_dir, "12_scvi_ranking_bar.png")
out_fig_map <- file.path(paths$figures_dir, "12_scvi_stopover_map.png")

# =========================
# 读取数据
# =========================
stops <- read_csv(stops_path, show_col_types = FALSE)
proj <- read_csv(projection_path, show_col_types = FALSE)

stops_use <- stops %>%
  filter(
    !is.na(lat_center),
    !is.na(lon_center),
    !is.na(duration_hr),
    duration_hr > 0,
    duration_hr <= cfg$stopover$max_duration_hr,
    !is.na(ndvi_arrive)
  )

cat("参与 SCVI 排序的停歇地数量:", nrow(stops_use), "\n")

# =========================
# 从 E 模块结果中提取气候脆弱性
# 以 NDVI 下降 20% 情景下的预测停留时长损失作为 vulnerability
# =========================
vuln <- proj %>%
  filter(scenario %in% c("current", "ndvi_minus_20")) %>%
  select(cluster_id, individual_id, scenario, pred_duration_hr) %>%
  pivot_wider(
    names_from = scenario,
    values_from = pred_duration_hr
  ) %>%
  mutate(
    climate_loss_hr = current - ndvi_minus_20,
    climate_loss_hr = ifelse(is.na(climate_loss_hr), 0, climate_loss_hr),
    climate_loss_hr = pmax(climate_loss_hr, 0)
  ) %>%
  select(cluster_id, individual_id, climate_loss_hr)

# =========================
# 合并
# =========================
scvi_df <- stops_use %>%
  left_join(vuln, by = c("cluster_id", "individual_id")) %>%
  mutate(
    climate_loss_hr = ifelse(is.na(climate_loss_hr), 0, climate_loss_hr),
    use_intensity = case_when(
      "n_state_points" %in% names(.) ~ n_state_points,
      "n_points" %in% names(.) ~ n_points,
      TRUE ~ 1
    ),
    resource_quality = ifelse(!is.na(ndvi_arrive), ndvi_arrive, ndvi_mean)
  )

# =========================
# 归一化函数
# =========================
rescale01 <- function(x) {
  if (all(is.na(x))) return(rep(NA_real_, length(x)))
  rng <- range(x, na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2]) || rng[1] == rng[2]) {
    return(rep(0.5, length(x)))
  }
  (x - rng[1]) / (rng[2] - rng[1])
}

score_scvi <- function(data, label, max_duration_hr = 240, weights = c(use = 0.25, duration = 0.30, resource = 0.25, vulnerability = 0.20)) {
  data |>
    mutate(
      scenario_label = label,
      duration_scvi_hr = pmin(duration_hr, max_duration_hr),
      use_score = rescale01(log1p(use_intensity)),
      duration_score = rescale01(log1p(duration_scvi_hr)),
      resource_score = rescale01(resource_quality),
      vulnerability_score = rescale01(climate_loss_hr),
      SCVI = weights[["use"]] * use_score +
        weights[["duration"]] * duration_score +
        weights[["resource"]] * resource_score +
        weights[["vulnerability"]] * vulnerability_score,
      conservation_class = case_when(
        SCVI >= quantile(SCVI, 0.80, na.rm = TRUE) ~ "高优先级",
        SCVI >= quantile(SCVI, 0.50, na.rm = TRUE) ~ "中优先级",
        TRUE ~ "低优先级"
      )
    ) |>
    arrange(desc(SCVI)) |>
    mutate(rank = row_number())
}

scvi_df <- score_scvi(
  scvi_df,
  label = "robust_duration_cap_240h",
  max_duration_hr = 240
)

scvi_sensitivity <- bind_rows(
  scvi_df,
  score_scvi(
    scvi_df |> filter(duration_hr <= 168),
    label = "strict_migration_168h",
    max_duration_hr = 168
  ),
  score_scvi(
    scvi_df,
    label = "balanced_weights_cap_240h",
    max_duration_hr = 240,
    weights = c(use = 0.25, duration = 0.25, resource = 0.25, vulnerability = 0.25)
  ),
  score_scvi(
    scvi_df,
    label = "resource_vulnerability_cap_240h",
    max_duration_hr = 240,
    weights = c(use = 0.15, duration = 0.20, resource = 0.35, vulnerability = 0.30)
  )
)

rank_stability <- scvi_sensitivity |>
  select(scenario_label, cluster_id, individual_id, rank, SCVI) |>
  pivot_wider(
    names_from = scenario_label,
    values_from = c(rank, SCVI)
  )

write_csv(rank_stability, out_stability)

scvi_df <- scvi_df %>%
  mutate(
    duration_capped = duration_hr > duration_scvi_hr
  )

# =========================
# 输出排序表
# =========================
scvi_out <- scvi_df %>%
  select(
    any_of(c(
      "rank",
      "cluster_id",
      "event_id",
      "site_id",
      "individual_id",
      "lat_center",
      "lon_center",
      "duration_hr",
      "duration_scvi_hr",
      "duration_capped",
      "ndvi_arrive",
      "ndvi_mean",
      "wind_support",
      "n_points",
      "n_state_points",
      "climate_loss_hr",
      "use_score",
      "duration_score",
      "resource_score",
      "vulnerability_score",
      "SCVI",
      "scenario_label",
      "conservation_class"
    ))
  )

write_csv(scvi_out, out_table)

print(scvi_out, n = Inf)

# =========================
# 汇总表
# =========================
summary_tbl <- tibble(
  item = c(
    "参与 SCVI 排序的停歇地数量",
    "高优先级停歇地数量",
    "中优先级停歇地数量",
    "低优先级停歇地数量",
    "SCVI 最高值",
    "SCVI 中位数",
    "平均停留时长",
    "SCVI duration 上限小时",
    "duration 被截尾的停歇事件数量",
    "平均 NDVI",
    "平均气候损失小时",
    "SCVI 稳健性表"
  ),
  value = c(
    nrow(scvi_df),
    sum(scvi_df$conservation_class == "高优先级", na.rm = TRUE),
    sum(scvi_df$conservation_class == "中优先级", na.rm = TRUE),
    sum(scvi_df$conservation_class == "低优先级", na.rm = TRUE),
    round(max(scvi_df$SCVI, na.rm = TRUE), 3),
    round(median(scvi_df$SCVI, na.rm = TRUE), 3),
    round(mean(scvi_df$duration_hr, na.rm = TRUE), 2),
    240,
    sum(scvi_df$duration_capped, na.rm = TRUE),
    round(mean(scvi_df$resource_quality, na.rm = TRUE), 3),
    round(mean(scvi_df$climate_loss_hr, na.rm = TRUE), 2),
    out_stability
  )
)

write_csv(summary_tbl, out_summary)
print(summary_tbl, n = Inf)

# =========================
# 图 1：SCVI 排序条形图
# =========================
top_n <- min(15, nrow(scvi_df))

p_bar <- scvi_df %>%
  slice_head(n = top_n) %>%
  mutate(stopover_label = paste0("C", cluster_id, "_", individual_id)) %>%
  ggplot(aes(
    x = reorder(stopover_label, SCVI),
    y = SCVI,
    fill = conservation_class
  )) +
  geom_col(width = 0.7) +
  coord_flip() +
  theme_bw() +
  labs(
    title = "停歇地保育价值指数 SCVI 排序",
    x = "停歇地",
    y = "SCVI",
    fill = "保育优先级"
  )

ggsave(out_fig_bar, p_bar, width = 9, height = 6, dpi = 300)

# =========================
# 图 2：停歇地空间分布图
# =========================
world_map <- if (requireNamespace("maps", quietly = TRUE)) {
  ggplot2::map_data("world")
} else {
  NULL
}

x_range <- range(scvi_df$lon_center, na.rm = TRUE)
y_range <- range(scvi_df$lat_center, na.rm = TRUE)
x_pad <- max(diff(x_range) * 0.18, 2)
y_pad <- max(diff(y_range) * 0.18, 2)

p_map <- ggplot() +
  {if (!is.null(world_map)) geom_polygon(
    data = world_map,
    aes(x = long, y = lat, group = group),
    fill = "#f1f5f9",
    color = "#cbd5e1",
    linewidth = 0.2
  )} +
  geom_point(
    data = scvi_df,
    aes(
      x = lon_center,
      y = lat_center,
      size = SCVI,
      shape = conservation_class
    ),
    alpha = 0.85,
    color = "#1f2937"
  ) +
  coord_quickmap(
    xlim = c(x_range[1] - x_pad, x_range[2] + x_pad),
    ylim = c(y_range[1] - y_pad, y_range[2] + y_pad),
    expand = FALSE
  ) +
  theme_bw() +
  theme(
    panel.background = element_rect(fill = "#eaf2fb", color = NA),
    panel.grid = element_line(color = "#dbe4ef", linewidth = 0.25)
  ) +
  labs(
    title = "停歇地 SCVI 空间分布",
    x = "Longitude",
    y = "Latitude",
    size = "SCVI",
    shape = "保育优先级"
  )

ggsave(out_fig_map, p_map, width = 8, height = 6, dpi = 300)

cat("=== F 模块 SCVI 完成 ===\n")
cat("SCVI 排序表:", out_table, "\n")
cat("项目结果汇总:", out_summary, "\n")
cat("SCVI 排序图:", out_fig_bar, "\n")
cat("SCVI 空间图:", out_fig_map, "\n")
