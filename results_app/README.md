# Curlew Results Viewer

Run this app when you only want to inspect existing results:

```r
shiny::runApp("D:/migration_project/results_app")
```

This viewer is read-only. It does not run preprocessing, HMM fitting, trajectory simulation, or cache rebuilding.

It reads:

- `data/processed/curlew_states_decoded.csv`
- `output/tables/14_trajectory_simulations.csv`
- `output/tables/14_trajectory_state_hourly.csv`
- `output/tables/14_trajectory_endpoints.csv`
- `output/tables/08_transition_matrix.csv`, when available

Tabs:

- `Observed Tracks`: historical GPS/HMM state tracks with filters.
- `Predicted Tracks`: cached simulated trajectory results.
- `Model Notes`: interpretation notes and limitations.
