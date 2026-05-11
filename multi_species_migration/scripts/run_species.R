#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
})

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
if (length(args) < 1) {
  stop("Usage: Rscript scripts/run_species.R config/species/curlew.example.json")
}

config_candidate <- args[[1]]
config_path <- if (grepl("^[A-Za-z]:[/\\\\]|^/", config_candidate)) {
  normalizePath(config_candidate, winslash = "/", mustWork = FALSE)
} else if (file.exists(file.path(project_root, config_candidate))) {
  normalizePath(file.path(project_root, config_candidate), winslash = "/", mustWork = FALSE)
} else {
  normalizePath(file.path(original_wd, config_candidate), winslash = "/", mustWork = FALSE)
}
Sys.setenv(PROJECT_ROOT = project_root, SPECIES_CONFIG = config_path)

source(file.path("R", "00_config.R"))
cfg <- load_cfg(config_path)
paths <- project_paths(cfg)
init_project_dirs(paths)

rscript <- Sys.getenv("RSCRIPT_BIN", unset = file.path(R.home("bin"), "Rscript"))
python_default <- if (nzchar(Sys.which("python"))) {
  "python"
} else if (nzchar(Sys.which("py"))) {
  "py"
} else {
  "python"
}
python <- Sys.getenv("PYTHON_BIN", unset = python_default)

check_file <- function(path, label) {
  if (!file.exists(path)) stop("步骤没有生成预期文件 [", label, "]: ", path)
  invisible(path)
}

check_csv <- function(path, label, required = character()) {
  check_file(path, label)
  cols <- names(readr::read_csv(path, n_max = 0, show_col_types = FALSE))
  miss <- setdiff(required, cols)
  if (length(miss) > 0) {
    stop("文件缺少关键列 [", label, "]: ", paste(miss, collapse = ", "), "\n", path)
  }
  invisible(path)
}

run_step <- function(label, command, args, checks = list()) {
  cat("\n=== ", label, " ===\n", sep = "")
  status <- system2(command, args)
  if (!identical(status, 0L)) stop("步骤失败: ", label)
  invisible(lapply(checks, function(x) do.call(x$fn, x$args)))
}

csv_check <- function(path, label, required = character()) {
  list(fn = check_csv, args = list(path = path, label = label, required = required))
}

file_check <- function(path, label) {
  list(fn = check_file, args = list(path = path, label = label))
}

cat("Project root: ", project_root, "\n", sep = "")
cat("Species config: ", config_path, "\n", sep = "")
cat("Species: ", cfg$project$common_name %||% cfg$project$species_code, " (", cfg$project$species_code, ")\n", sep = "")
cat("Output directory: ", paths$species_dir, "\n", sep = "")

run_step("A0 raw data check", rscript, c("R/02_check_raw.R"), list(
  csv_check(file.path(paths$tables_dir, "00_raw_summary.csv"), "raw summary")
))

run_step("A1 clean tracking data", rscript, c("R/03_clean_tracking.R"), list(
  csv_check(paths$clean_csv, "clean tracks", c("id", "ts", "lat", "lon"))
))

run_step("A2 regularize tracks", rscript, c("R/04_regularize_tracks.R"), list(
  csv_check(paths$regular_csv, "regular tracks", c("id"))
))

run_step("B1 match ERA5", python, c("py/05_match_era5.py", "--project-root", project_root, "--config", config_path), list(
  csv_check(paths$env_csv, "ERA5 matched tracks", c("id", "temp_C", "wind_support", "wind_speed"))
))

run_step("B2 match NDVI", rscript, c("R/05b_match_ndvi.R"), list(
  csv_check(paths$env_ndvi_csv, "NDVI matched tracks", c("id", "ndvi"))
))

run_step("C1 prepare HMM data", rscript, c("R/06_prepare_hmm_data.R"), list(
  csv_check(paths$hmm_prep_csv, "HMM input", c("ID", "original_id", "step", "angle"))
))

run_step("C2 fit HMM models", rscript, c("R/07_fit_hmm_models.R"), list(
  file_check(file.path(paths$models_dir, paste0(cfg$project$species_code, "_hmm_best.rds")), "best HMM"),
  csv_check(file.path(paths$tables_dir, "07_hmm_bic_compare.csv"), "HMM model comparison", c("states", "AIC", "BIC"))
))

run_step("C3 decode HMM states", rscript, c("R/08_decode_hmm.R"), list(
  csv_check(paths$states_csv, "decoded states", c("state", "state_label", "step"))
))

run_step("C4 backfill NDVI to states", rscript, c("R/08b_add_ndvi_to_states.R"), list(
  csv_check(paths$states_env_csv, "decoded states with NDVI", c("state", "state_label", "ndvi"))
))

run_step("D1 Lévy analysis and stopover detection", python, c("py/09_levy_stopovers.py", "--project-root", project_root, "--config", config_path), list(
  csv_check(paths$levy_csv, "Lévy result", c("alpha", "xmin", "flight_definition")),
  csv_check(paths$stopover_events_csv, "stopover events", c("event_id", "site_id", "individual_id", "duration_hr")),
  csv_check(paths$stopover_sites_csv, "stopover sites", c("site_id", "n_events"))
))

run_step("D2 rebuild stopover environment", rscript, c("R/09b_rebuild_stopovers_env.R"), list(
  csv_check(paths$stopover_events_env_csv, "stopover events with environment", c("event_id", "duration_hr", "ndvi_arrive", "wind_support"))
))

run_step("D3 stopover duration model", rscript, c("R/10_optimal_stopping.R"), list(
  csv_check(file.path(paths$tables_dir, "10_optimal_stopping_params.csv"), "stopover model parameters")
))

run_step("D4 stopover sensitivity", rscript, c("R/10b_stopover_sensitivity.R"), list(
  csv_check(file.path(paths$tables_dir, "10b_stopover_sensitivity_summary.csv"), "stopover sensitivity")
))

run_step("E resource scenario projection", rscript, c("R/11_climate_scenario_projection.R"), list(
  csv_check(file.path(paths$tables_dir, "11_climate_scenario_projection.csv"), "scenario projection")
))

run_step("F SCVI ranking", rscript, c("R/12_scvi_conservation_value.R"), list(
  csv_check(file.path(paths$tables_dir, "12_scvi_stopover_ranking.csv"), "SCVI ranking", c("rank", "SCVI", "conservation_class"))
))

cat("\n=== Pipeline completed ===\n")
cat("Output directory: ", paths$species_dir, "\n", sep = "")
