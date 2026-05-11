standardize_movebank_columns <- function(df) {
  name_map <- list(
    id = c("individual-local-identifier", "individual_id", "id"),
    lat = c("location-lat", "lat", "latitude"),
    lon = c("location-long", "lon", "longitude"),
    timestamp = c("timestamp", "study-local-timestamp", "event-id")
  )

  pick_first <- function(cands) {
    hit <- intersect(cands, names(df))
    if (length(hit) == 0) return(NA_character_)
    hit[[1]]
  }

  selected <- vapply(name_map, pick_first, character(1))
  required <- c("id", "lat", "lon", "timestamp")
  if (any(is.na(selected[required]))) {
    stop("无法自动识别必要列。当前列名为: ", paste(names(df), collapse = ", "))
  }

  dplyr::rename(
    df,
    id = !!selected[["id"]],
    lat = !!selected[["lat"]],
    lon = !!selected[["lon"]],
    timestamp = !!selected[["timestamp"]]
  )
}

parse_movebank_ts <- function(x, tz = "UTC") {
  if (inherits(x, "POSIXt")) {
    return(lubridate::with_tz(x, tzone = tz))
  }
  out <- suppressWarnings(lubridate::ymd_hms(x, tz = tz, quiet = TRUE))
  bad <- is.na(out)
  if (any(bad)) {
    out2 <- suppressWarnings(lubridate::parse_date_time(
      x[bad],
      orders = c("Ymd HMS", "Y-m-d H:M:S", "Y/m/d H:M:S", "Ymd HM", "Y-m-d H:M", "YmdTHMS", "Y-m-dTH:M:S"),
      tz = tz,
      quiet = TRUE
    ))
    out[bad] <- as.POSIXct(out2, tz = tz)
  }
  as.POSIXct(out, tz = tz)
}

haversine_speed <- function(lon_prev, lat_prev, lon, lat, dt_sec) {
  dist_m <- geosphere::distHaversine(cbind(lon_prev, lat_prev), cbind(lon, lat))
  dist_m / dt_sec
}

order_state_labels <- function(df, state_col = "state", step_col = "step") {
  state_sym <- rlang::sym(state_col)
  step_sym <- rlang::sym(step_col)

  ranked <- df |>
    dplyr::group_by(!!state_sym) |>
    dplyr::summarise(mean_step = mean(!!step_sym, na.rm = TRUE), .groups = "drop") |>
    dplyr::arrange(mean_step)

  labels <- c("停歇", "局部活动/觅食", "飞行", "高速飞行")
  setNames(labels[seq_len(nrow(ranked))], ranked[[state_col]])
}
