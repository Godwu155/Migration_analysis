#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(moveHMM)
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
source(file.path("R", "01_utils.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

hmm_path <- file.path(paths$models_dir, paste0(cfg$project$species_code, "_hmm_best.rds"))
if (!file.exists(hmm_path)) stop("找不到最优 HMM 模型: ", hmm_path)

fit <- read_rds(hmm_path)

df <- read_rds(paths$hmm_prep_rds) |>
  filter(!is.na(step), !is.na(angle), step <= cfg$hmm$max_step_km)

states <- viterbi(fit)
if (length(states) != nrow(df)) {
  stop("Viterbi 状态数量与输入数据行数不一致: states=", length(states), ", rows=", nrow(df))
}

df_out <- df
df_out$state <- states

# 使用项目已有函数给状态命名；如果函数不可用，则按 mean_step 从小到大命名
if (exists("order_state_labels")) {
  label_map <- order_state_labels(df_out)
  df_out$state_label <- unname(label_map[as.character(df_out$state)])
} else {
  state_order <- df_out |>
    group_by(state) |>
    summarise(mean_step = mean(step, na.rm = TRUE), .groups = "drop") |>
    arrange(mean_step) |>
    pull(state)
  labels <- c("停歇", "局部活动/觅食", "中距离移动", "长距离飞行")[seq_along(state_order)]
  label_tbl <- tibble(state = state_order, state_label = labels)
  df_out <- left_join(df_out, label_tbl, by = "state")
}

# 坐标列兼容：moveHMM 通常会保留 lon/lat，但 amt 轨迹常见 x_/y_
if (all(c("lon", "lat") %in% names(df_out))) {
  x_col <- "lon"
  y_col <- "lat"
} else if (all(c("x_", "y_") %in% names(df_out))) {
  df_out <- df_out |>
    mutate(lon = x_, lat = y_)
  x_col <- "lon"
  y_col <- "lat"
} else if (all(c("x", "y") %in% names(df_out))) {
  df_out <- df_out |>
    mutate(lon = x, lat = y)
  x_col <- "lon"
  y_col <- "lat"
} else {
  stop(
    "找不到坐标列。当前列名为: ",
    paste(names(df_out), collapse = ", "),
    "。需要 lon/lat、x_/y_ 或 x/y。"
  )
}

# 分组列兼容：优先 original_id，其次 id/ID
if ("original_id" %in% names(df_out)) {
  group_col <- "original_id"
} else if ("id" %in% names(df_out)) {
  group_col <- "id"
} else if ("ID" %in% names(df_out)) {
  group_col <- "ID"
} else {
  group_col <- NULL
}

# 时间列兼容
if (!"ts" %in% names(df_out) && "t_" %in% names(df_out)) {
  df_out <- df_out |> mutate(ts = t_)
}

write_csv(df_out, paths$states_csv)
write_csv(as.data.frame(fit$mle$gamma), file.path(paths$tables_dir, "08_transition_matrix.csv"))

state_summary <- df_out |>
  group_by(state, state_label) |>
  summarise(
    n = n(),
    mean_step = mean(step, na.rm = TRUE),
    median_step = median(step, na.rm = TRUE),
    max_step = max(step, na.rm = TRUE),
    mean_abs_angle = mean(abs(angle), na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(mean_step)

write_csv(state_summary, file.path(paths$tables_dir, "08_state_summary.csv"))

world_map <- if (requireNamespace("maps", quietly = TRUE)) {
  ggplot2::map_data("world")
} else {
  NULL
}

x_range <- range(df_out[[x_col]], na.rm = TRUE)
y_range <- range(df_out[[y_col]], na.rm = TRUE)
x_pad <- max(diff(x_range) * 0.08, 1)
y_pad <- max(diff(y_range) * 0.08, 1)

p <- ggplot() +
  {if (!is.null(world_map)) geom_polygon(
    data = world_map,
    aes(x = long, y = lat, group = group),
    fill = "#f1f5f9",
    color = "#cbd5e1",
    linewidth = 0.2
  )} +
  geom_path(
    data = df_out,
    aes(
      x = .data[[x_col]],
      y = .data[[y_col]],
      color = state_label,
      group = if (!is.null(group_col)) .data[[group_col]] else 1
    ),
    linewidth = 0.35,
    alpha = 0.72
  ) +
  coord_quickmap(
    xlim = c(x_range[1] - x_pad, x_range[2] + x_pad),
    ylim = c(y_range[1] - y_pad, y_range[2] + y_pad),
    expand = FALSE
  ) +
  theme_bw(base_size = 12) +
  theme(
    panel.background = element_rect(fill = "#eaf2fb", color = NA),
    panel.grid = element_line(color = "#dbe4ef", linewidth = 0.25)
  ) +
  labs(color = "行为状态", x = "Longitude", y = "Latitude")

ggsave(file.path(paths$figures_dir, "08_state_tracks.png"), p, width = 10, height = 6, dpi = 300)

cat("=== 状态解码完成 ===\n")
print(state_summary)
cat("状态结果输出: ", paths$states_csv, "\n", sep = "")
cat("状态摘要输出: ", file.path(paths$tables_dir, "08_state_summary.csv"), "\n", sep = "")
cat("轨迹图输出: ", file.path(paths$figures_dir, "08_state_tracks.png"), "\n", sep = "")
