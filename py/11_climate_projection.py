#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr
from scipy.stats import linregress


def load_config(project_root: Path) -> dict:
    return json.loads((project_root / "config" / "project_config.json").read_text(encoding="utf-8"))


def extract_nearest_series(ds: xr.Dataset, lat: float, lon: float) -> np.ndarray:
    lat_name = "lat" if "lat" in ds.coords else "latitude"
    lon_name = "lon" if "lon" in ds.coords else "longitude"
    var = list(ds.data_vars)[0]
    return ds[var].sel({lat_name: lat, lon_name: lon}, method="nearest").to_numpy()


def main() -> None:
    parser = argparse.ArgumentParser(description="CMIP6 气候情景预测骨架")
    parser.add_argument("--project-root", default=None)
    parser.add_argument("--scenario-pattern", default="*.nc", help="例如 '*ssp585*.nc'")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve() if args.project_root else Path.cwd()
    cfg = load_config(project_root)
    sp = cfg["project"]["species_code"]

    stopovers_path = project_root / "data" / "processed" / f"{sp}_stopovers.csv"
    os_params_path = project_root / "output" / "tables" / "10_optimal_stopping_params.csv"
    env_hist_path = project_root / "data" / "clean" / f"{sp}_env_matched.csv"
    climate_files = sorted(glob.glob(str(project_root / "data" / "climate" / args.scenario_pattern)))

    if not stopovers_path.exists():
        raise FileNotFoundError(f"找不到 stopovers 文件: {stopovers_path}")
    if not os_params_path.exists():
        raise FileNotFoundError(f"找不到最优停止参数文件: {os_params_path}")
    if not climate_files:
        raise FileNotFoundError("未发现符合模式的 CMIP6/气候文件")

    stops = pd.read_csv(stopovers_path)
    hist = pd.read_csv(env_hist_path)
    params = pd.read_csv(os_params_path).iloc[0]
    lam_col = "lambda_proxy" if "lambda_proxy" in params.index else "lambda"
    qstar_col = "Qstar_proxy" if "Qstar_proxy" in params.index else "Qstar"
    if lam_col not in params.index or qstar_col not in params.index:
        raise KeyError(
            "最优停止参数文件缺少 lambda_proxy/Qstar_proxy 或 lambda/Qstar 列"
        )
    lam = float(params[lam_col])
    qstar = float(params[qstar_col])

    projections = []
    for nc_path in climate_files:
        ds = xr.open_dataset(nc_path)
        var = list(ds.data_vars)[0]
        for _, row in stops.iterrows():
            ts = extract_nearest_series(ds, row["lat_center"], row["lon_center"])

            # 历史关系：用全局 temp_C -> ndvi 做最简骨架，后续可改为按停歇地/月份建模
            sub = hist[["temp_C", "ndvi"]].dropna() if set(["temp_C", "ndvi"]).issubset(hist.columns) else pd.DataFrame()
            if len(sub) >= 10:
                slope, intercept, *_ = linregress(sub["temp_C"], sub["ndvi"])
            else:
                slope, intercept = 0.01, 0.3

            temp_c = np.asarray(ts) - 273.15
            ndvi_pred = np.clip(slope * temp_c + intercept, qstar + 0.001, 1.0)
            duration_pred = np.log(ndvi_pred / qstar) / lam

            projections.append({
                "source_file": Path(nc_path).name,
                "cluster_id": row["cluster_id"],
                "mean_temp_c": float(np.nanmean(temp_c)),
                "mean_ndvi_pred": float(np.nanmean(ndvi_pred)),
                "mean_duration_pred_hr": float(np.nanmean(duration_pred)),
            })
        ds.close()

    out = pd.DataFrame(projections)
    out_path = project_root / "output" / "tables" / "11_climate_projection.csv"
    out.to_csv(out_path, index=False)
    print(f"已输出: {out_path}")
    print(out.head())


if __name__ == "__main__":
    main()
