#!/usr/bin/env Rscript

script_path <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_path)) sub("^--file=", "", script_path[[1]]) else NA_character_
original_wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
project_root <- if (!is.na(script_path)) {
  normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = FALSE)
} else {
  original_wd
}
setwd(project_root)

args <- commandArgs(trailingOnly = TRUE)
configs <- if (length(args) > 0) {
  vapply(args, function(x) {
    if (grepl("^[A-Za-z]:[/\\\\]|^/", x)) {
      normalizePath(x, winslash = "/", mustWork = FALSE)
    } else if (file.exists(file.path(project_root, x))) {
      normalizePath(file.path(project_root, x), winslash = "/", mustWork = FALSE)
    } else {
      normalizePath(file.path(original_wd, x), winslash = "/", mustWork = FALSE)
    }
  }, character(1))
} else {
  list.files(file.path("config", "species"), pattern = "^[^.].*\\.json$", full.names = TRUE)
}

configs <- configs[!grepl("\\.example\\.json$", configs)]
if (length(configs) == 0) {
  stop("没有找到可批量运行的物种配置。请复制 example 配置并去掉 .example 后缀。")
}

for (cfg in configs) {
  cat("\n\n##### Running species config: ", cfg, " #####\n", sep = "")
  status <- system2(file.path(R.home("bin"), "Rscript"), c("scripts/run_species.R", cfg))
  if (!identical(status, 0L)) stop("物种流程失败: ", cfg)
}
