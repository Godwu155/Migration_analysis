`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

get_project_root <- function() {
  root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(root)) return(normalizePath(root, winslash = "/", mustWork = FALSE))
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

resolve_project_path <- function(path, root = get_project_root()) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(file.path(root, path), winslash = "/", mustWork = FALSE)
  }
}

recursive_merge <- function(base, override) {
  if (is.null(base)) return(override)
  if (is.null(override)) return(base)
  for (nm in names(override)) {
    if (is.list(base[[nm]]) && is.list(override[[nm]]) && is.null(attr(override[[nm]], "class"))) {
      base[[nm]] <- recursive_merge(base[[nm]], override[[nm]])
    } else {
      base[[nm]] <- override[[nm]]
    }
  }
  base
}

find_cfg_path <- function(config_path = NULL) {
  root <- get_project_root()
  if (!is.null(config_path) && nzchar(config_path)) {
    return(resolve_project_path(config_path, root))
  }

  env_path <- Sys.getenv("SPECIES_CONFIG", unset = "")
  if (nzchar(env_path)) return(resolve_project_path(env_path, root))

  args <- commandArgs(trailingOnly = TRUE)
  json_args <- args[grepl("\\.json$", args, ignore.case = TRUE)]
  if (length(json_args) > 0) return(resolve_project_path(json_args[[1]], root))

  legacy_path <- file.path(root, "config", "project_config.json")
  if (file.exists(legacy_path)) return(legacy_path)

  example_path <- file.path(root, "config", "species", "curlew.example.json")
  if (file.exists(example_path)) return(example_path)

  stop("找不到物种配置文件。请设置 SPECIES_CONFIG，或运行: Rscript scripts/run_species.R config/species/curlew.example.json")
}

load_cfg <- function(config_path = NULL) {
  root <- get_project_root()
  cfg_path <- find_cfg_path(config_path)
  if (!file.exists(cfg_path)) stop("配置文件不存在: ", cfg_path)

  cfg <- jsonlite::fromJSON(cfg_path, simplifyVector = TRUE)

  defaults_path <- file.path(root, "config", "default_parameters.json")
  group <- cfg$project$species_group %||% cfg$biology$species_group %||% NULL
  if (!is.null(group) && file.exists(defaults_path)) {
    defaults <- jsonlite::fromJSON(defaults_path, simplifyVector = TRUE)
    if (!is.null(defaults[[group]])) {
      cfg <- recursive_merge(defaults[[group]], cfg)
    }
  }

  cfg$config_path <- cfg_path
  cfg
}

project_paths <- function(cfg = load_cfg()) {
  root <- get_project_root()
  sp <- cfg$project$species_code
  if (is.null(sp) || !nzchar(sp)) stop("配置缺少 project.species_code")

  output_base <- cfg$output$base_dir %||% "output/species_outputs"
  species_dir <- resolve_project_path(file.path(output_base, sp), root)
  data_dir <- file.path(species_dir, "data")
  clean_dir <- file.path(data_dir, "clean")
  processed_dir <- file.path(data_dir, "processed")

  list(
    root = root,
    species_dir = species_dir,
    config_path = cfg$config_path,
    raw_csv = resolve_project_path(cfg$input$raw_csv %||% file.path("data", "raw", sp, "track.csv"), root),
    ndvi_csv = resolve_project_path(cfg$input$ndvi_csv %||% file.path("data", "raw", sp, "ndvi.csv"), root),
    clean_csv = file.path(clean_dir, paste0(sp, "_clean.csv")),
    regular_csv = file.path(clean_dir, paste0(sp, "_regular.csv")),
    env_csv = file.path(clean_dir, paste0(sp, "_env_matched.csv")),
    env_ndvi_csv = file.path(clean_dir, paste0(sp, "_env_matched_ndvi.csv")),
    hmm_prep_csv = file.path(processed_dir, paste0(sp, "_hmm_input.csv")),
    hmm_prep_rds = file.path(processed_dir, paste0(sp, "_hmm_input.rds")),
    states_csv = file.path(processed_dir, paste0(sp, "_states_decoded.csv")),
    states_env_csv = file.path(processed_dir, paste0(sp, "_states_decoded_env.csv")),
    stopovers_csv = file.path(processed_dir, paste0(sp, "_stopovers.csv")),
    stopover_events_csv = file.path(processed_dir, paste0(sp, "_stopover_events.csv")),
    stopover_events_env_csv = file.path(processed_dir, paste0(sp, "_stopover_events_env.csv")),
    stopover_sites_csv = file.path(processed_dir, paste0(sp, "_stopover_sites.csv")),
    levy_csv = file.path(processed_dir, paste0(sp, "_levy_result.csv")),
    models_dir = file.path(species_dir, "models"),
    figures_dir = file.path(species_dir, "figures"),
    tables_dir = file.path(species_dir, "tables"),
    climate_dir = resolve_project_path(cfg$input$climate_dir %||% "data/climate", root)
  )
}

init_project_dirs <- function(paths) {
  dirs <- c(
    paths$species_dir,
    dirname(paths$clean_csv),
    dirname(paths$hmm_prep_csv),
    paths$models_dir,
    paths$figures_dir,
    paths$tables_dir
  )
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
}
