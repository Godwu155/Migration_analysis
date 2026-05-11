#!/usr/bin/env Rscript

cmd_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(cmd_file) > 0) {
  script_path <- normalizePath(sub("^--file=", "", cmd_file[[1]]), winslash = "/", mustWork = TRUE)
  project_root <- dirname(dirname(script_path))
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

setwd(project_root)

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop("Package 'shiny' is required. Install it before running the prediction app.")
}

shiny::runApp(project_root, host = "127.0.0.1", port = 3838, launch.browser = TRUE)
