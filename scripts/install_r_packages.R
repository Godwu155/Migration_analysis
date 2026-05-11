#!/usr/bin/env Rscript

cran_repo <- Sys.getenv("CRAN_REPO", unset = "https://cloud.r-project.org")
repos <- getOption("repos")
repos["CRAN"] <- cran_repo
options(repos = repos)

required_packages <- c(
  "readr",
  "dplyr",
  "lubridate",
  "jsonlite",
  "geosphere",
  "amt",
  "sf",
  "purrr",
  "tibble",
  "moveHMM",
  "ggplot2",
  "broom",
  "tidyr",
  "scales",
  "shiny",
  "leaflet",
  "maps"
)

installed <- rownames(installed.packages())
missing <- setdiff(required_packages, installed)

cat("CRAN mirror:", cran_repo, "\n")
cat("Required R packages:", paste(required_packages, collapse = ", "), "\n")

if (length(missing) == 0) {
  cat("All required R packages are already installed.\n")
  quit(status = 0)
}

cat("Installing missing R packages:", paste(missing, collapse = ", "), "\n")
install.packages(missing, dependencies = TRUE)

still_missing <- setdiff(required_packages, rownames(installed.packages()))
if (length(still_missing) > 0) {
  stop("These R packages are still missing after install: ", paste(still_missing, collapse = ", "))
}

cat("R package setup complete.\n")
