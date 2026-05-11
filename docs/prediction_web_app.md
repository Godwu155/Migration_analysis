# Flight State and Trajectory Prediction App

This module adds an exploratory prediction layer on top of the existing curlew HMM workflow.

## Files

- `R/13_predict_flight_state.R`: loads decoded HMM states, labels records as northbound/southbound/unknown, builds route-aware prediction context, and predicts next-hour state probabilities.
- `R/14_simulate_flight_trajectory.R`: simulates future trajectories from route-aware state probabilities and state-specific movement pools, then summarizes uncertainty.
- `app.R`: Shiny web interface for interactive inputs, state probability charts, and trajectory maps.
- `scripts/run_prediction_app.R`: helper script to launch the Shiny app.

## Run

Interactive prediction app:

```r
shiny::runApp("D:/migration_project/predictor_app")
```

Cached result viewer:

```r
shiny::runApp("D:/migration_project/viewer_app")
```

From R or RStudio:

```r
shiny::runApp("D:/migration_project")
```

Or, if `Rscript` is available:

```bash
Rscript scripts/run_prediction_app.R
```

Launching the app does not need to rerun `R/14_simulate_flight_trajectory.R`. The app first looks for cached files:

- `output/tables/14_trajectory_simulations.csv`
- `output/tables/14_trajectory_state_hourly.csv`
- `output/tables/14_trajectory_endpoints.csv`
- `output/tables/15_prediction_summary.csv`
- `output/tables/15_endpoint_uncertainty.csv`
- `output/tables/15_direction_comparison.csv`

If those files exist, the page opens with the cached trajectory result. Click `Run prediction` only when you want to recompute trajectories for new inputs.

## Inputs

The app asks for current longitude, latitude, current state, temperature, wind support, wind speed, NDVI, migration direction, simulation horizon, and number of simulated tracks.

## Outputs

- Next-hour state probabilities.
- Simulated state probabilities through time.
- A map of simulated trajectories and endpoints.
- Endpoint summary statistics, including means, variances, standard deviations, 95% confidence intervals for the mean, and 95% prediction intervals.
- Northbound versus southbound route comparison in `15_direction_comparison.csv`.

## Interpretation

The trajectory layer is a scenario simulator, not a deterministic forecast. It samples state transitions and state-specific step/turn behavior from the existing decoded tracks, so results should be interpreted as likely movement envelopes under the supplied conditions.

For route-aware predictions, the model uses directional historical subsets when `Migration direction` is set to northbound or southbound. Because the current dataset is small, directional transition matrices are blended with the global transition matrix to avoid unstable zero-probability routes.
