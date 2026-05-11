#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(moveHMM)
  library(purrr)
  library(jsonlite)
})
source(file.path("R", "00_config.R"))

cfg <- load_cfg()
paths <- project_paths(cfg)
init_project_dirs(paths)

df <- read_rds(paths$hmm_prep_rds)
df$step[df$step == 0] <- 1e-6

df_fit <- df |>
  filter(!is.na(step), !is.na(angle), step <= cfg$hmm$max_step_km)

get_init <- function(k) {
  if (k == 2) return(list(mu = c(0.05, 8), sd = c(0.05, 8), kappa = c(0.1, 1.0)))
  if (k == 3) return(list(mu = c(0.03, 0.3, 8.0), sd = c(0.03, 0.3, 8.0), kappa = c(0.1, 0.3, 1.0)))
  if (k == 4) return(list(mu = c(0.03, 0.3, 3, 15), sd = c(0.03, 0.3, 3, 15), kappa = c(0.1, 0.3, 0.8, 1.5)))
  stop("未定义状态数的初值: ", k)
}

fit_one <- function(k) {
  init <- get_init(k)
  fitHMM(
    data = df_fit,
    nbStates = k,
    stepPar0 = c(init$mu, init$sd),
    anglePar0 = c(rep(0, k), init$kappa),
    formula = ~ temp_z + wind_support_z,
    #retryFits = 2,
    verbose = 0
  )
}

states_to_try <- cfg$hmm$candidate_states
fits <- list()
for (k in states_to_try) {
  cat("正在拟合", k, "状态模型...
")
  fits[[as.character(k)]] <- fit_one(k)
}

bic_tbl <- tibble(
  states = states_to_try,
  AIC = map_dbl(fits, AIC),
  BIC = map_dbl(fits, ~ AIC(.x, k = log(nrow(df_fit))))
) |>
  arrange(BIC)

best_k <- bic_tbl$states[[1]]
best_fit <- fits[[as.character(best_k)]]

write_csv(bic_tbl, file.path(paths$tables_dir, "07_hmm_bic_compare.csv"))
write_rds(best_fit, file.path(paths$models_dir, paste0("", cfg$project$species_code, "_hmm_best.rds")))
for (nm in names(fits)) {
  write_rds(fits[[nm]], file.path(paths$models_dir, paste0(cfg$project$species_code, "_hmm_", nm, "state.rds")))
}

cat("=== HMM 比较完成 ===
")
print(bic_tbl)
cat("最优状态数:", best_k, "
")
