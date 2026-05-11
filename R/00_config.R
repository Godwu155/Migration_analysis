get_project_root <- function() {
  root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(root)) return(normalizePath(root, winslash = "/", mustWork = FALSE))
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

load_cfg <- function() {
  root <- get_project_root()
  cfg_path <- file.path(root, "config", "project_config.json")
  if (!file.exists(cfg_path)) {
    stop("配置文件不存在: ", cfg_path)
  }
  jsonlite::fromJSON(cfg_path, simplifyVector = TRUE)
}

project_paths <- function(cfg = load_cfg()) {
  root <- get_project_root()
  sp <- cfg$project$species_code
  list(
    root = root,
    raw_csv = file.path(root, "data", "raw", paste0(sp, "_raw.csv")),
    clean_csv = file.path(root, "data", "clean", paste0(sp, "_clean.csv")),
    regular_csv = file.path(root, "data", "clean", paste0(sp, "_regular.csv")),
    env_csv = file.path(root, "data", "clean", paste0(sp, "_env_matched.csv")),
    env_ndvi_csv = file.path(root, "data", "clean", paste0(sp, "_env_matched_ndvi.csv")),
    hmm_prep_csv = file.path(root, "data", "processed", paste0(sp, "_hmm_input.csv")),
    hmm_prep_rds = file.path(root, "data", "processed", paste0(sp, "_hmm_input.rds")),
    states_csv = file.path(root, "data", "processed", paste0(sp, "_states_decoded.csv")),
    states_env_csv = file.path(root, "data", "processed", paste0(sp, "_states_decoded_env.csv")),
    stopovers_csv = file.path(root, "data", "processed", paste0(sp, "_stopovers.csv")),
    stopover_events_csv = file.path(root, "data", "processed", paste0(sp, "_stopover_events.csv")),
    stopover_events_env_csv = file.path(root, "data", "processed", paste0(sp, "_stopover_events_env.csv")),
    stopover_sites_csv = file.path(root, "data", "processed", paste0(sp, "_stopover_sites.csv")),
    levy_csv = file.path(root, "data", "processed", paste0(sp, "_levy_result.csv")),
    models_dir = file.path(root, "output", "models"),
    figures_dir = file.path(root, "output", "figures"),
    tables_dir = file.path(root, "output", "tables"),
    climate_dir = file.path(root, "data", "climate")
  )
}

init_project_dirs <- function(paths) {
  dirs <- c(
    dirname(paths$clean_csv),
    dirname(paths$hmm_prep_csv),
    paths$models_dir,
    paths$figures_dir,
    paths$tables_dir
  )
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
}
