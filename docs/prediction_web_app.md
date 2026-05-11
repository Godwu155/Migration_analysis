# Flight State and Trajectory Prediction App

This module adds an exploratory prediction layer on top of the existing curlew HMM workflow.

## Files

- `R/13_predict_flight_state.R`: loads decoded HMM states, builds a prediction context, and predicts next-hour state probabilities.
- `R/14_simulate_flight_trajectory.R`: simulates future trajectories from the state probabilities and state-specific movement pools.
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

If those files exist, the page opens with the cached trajectory result. Click `Run prediction` only when you want to recompute trajectories for new inputs.

## Inputs

The app asks for current longitude, latitude, current state, temperature, wind support, wind speed, NDVI, simulation horizon, and number of simulated tracks.

## Outputs

- Next-hour state probabilities.
- Simulated state probabilities through time.
- A map of simulated trajectories and endpoints.
- Endpoint summary statistics.

## Interpretation

The trajectory layer is a scenario simulator, not a deterministic forecast. It samples state transitions and state-specific step/turn behavior from the existing decoded tracks, so results should be interpreted as likely movement envelopes under the supplied conditions.
