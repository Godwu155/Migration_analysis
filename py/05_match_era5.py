#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
from pathlib import Path
from typing import Iterable, List

import numpy as np
import pandas as pd
import xarray as xr
import json


def find_project_root(start: Path) -> Path:
    start = start.resolve()
    for p in [start.parent, *start.parents]:
        if (p / "config" / "project_config.json").exists():
            return p
    raise FileNotFoundError(
        f"找不到 config/project_config.json，起始位置: {start}"
    )

def load_config(project_root: Path):
    config_path = project_root / "config" / "project_config.json"
    return json.loads(config_path.read_text(encoding="utf-8"))


def find_var(ds: xr.Dataset, candidates: Iterable[str]) -> str:
    for name in candidates:
        if name in ds.data_vars:
            return name
    raise ValueError(f"找不到变量，候选名为: {list(candidates)}，实际变量: {list(ds.data_vars)}")


def calc_bearing(lat1, lon1, lat2, lon2):
    lat1 = np.radians(lat1)
    lat2 = np.radians(lat2)
    dlon = np.radians(lon2 - lon1)
    x = np.sin(dlon) * np.cos(lat2)
    y = np.cos(lat1) * np.sin(lat2) - np.sin(lat1) * np.cos(lat2) * np.cos(dlon)
    bearing = np.degrees(np.arctan2(x, y))
    return (bearing + 360.0) % 360.0


def chunked_extract(ds: xr.Dataset, gps: pd.DataFrame, time_name: str, lat_name: str, lon_name: str,
                    temp_var: str, u_var: str, v_var: str, chunk_size: int = 5000) -> pd.DataFrame:
    temps: List[np.ndarray] = []
    us: List[np.ndarray] = []
    vs: List[np.ndarray] = []

    for start in range(0, len(gps), chunk_size):
        end = min(start + chunk_size, len(gps))
        part = gps.iloc[start:end]
        point = ds.sel(
            {
                time_name: xr.DataArray(part["ts"].to_numpy(), dims="points"),
                lat_name: xr.DataArray(part["lat"].to_numpy(), dims="points"),
                lon_name: xr.DataArray(part["lon_for_era"].to_numpy(), dims="points"),
            },
            method="nearest",
        )
        temps.append(point[temp_var].to_numpy())
        us.append(point[u_var].to_numpy())
        vs.append(point[v_var].to_numpy())
        print(f"匹配进度: {end}/{len(gps)}")

    gps["temp_K"] = np.concatenate(temps)
    gps["u"] = np.concatenate(us)
    gps["v"] = np.concatenate(vs)
    return gps


def main() -> None:
    parser = argparse.ArgumentParser(description="匹配 ERA5 环境变量到规则化 GPS 数据")
    parser.add_argument("--project-root", default=None)
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(__file__))
    print("project_root =", project_root)

    cfg = load_config(project_root)
    sp = cfg["project"]["species_code"]

    gps_path = project_root / "data" / "clean" / f"{sp}_regular.csv"
    out_path = project_root / "data" / "clean" / f"{sp}_env_matched.csv"
    nc_files = sorted(glob.glob(str(project_root / "data" / "climate" / "*.nc")))

    if not gps_path.exists():
        raise FileNotFoundError(f"找不到 GPS 文件: {gps_path}")
    if not nc_files:
        raise FileNotFoundError(f"data/climate 下没有 .nc 文件: {project_root / 'data' / 'climate'}")

    print("读取 GPS 数据...")
    gps = pd.read_csv(gps_path)
    gps["ts"] = pd.to_datetime(gps["ts"], utc=True).dt.tz_localize(None)

    print("读取 ERA5 NetCDF...")
    ds = xr.open_mfdataset(nc_files, combine="by_coords")

    time_name = "time" if "time" in ds.coords else "valid_time"
    lat_name = "latitude" if "latitude" in ds.coords else "lat"
    lon_name = "longitude" if "longitude" in ds.coords else "lon"

    temp_var = find_var(ds, ["t2m", "2m_temperature", "temperature_2m"])
    u_var = find_var(ds, ["u10", "u", "u_component_of_wind", "10m_u_component_of_wind"])
    v_var = find_var(ds, ["v10", "v", "v_component_of_wind", "10m_v_component_of_wind"])

    print("变量使用：", temp_var, u_var, v_var)

    era_lon = ds[lon_name]
    if float(era_lon.max()) > 180:
        gps["lon_for_era"] = gps["lon"] % 360
    else:
        gps["lon_for_era"] = gps["lon"]

    gps = chunked_extract(ds, gps, time_name, lat_name, lon_name, temp_var, u_var, v_var)
    gps["temp_C"] = gps["temp_K"] - 273.15
    gps["wind_speed"] = np.sqrt(gps["u"] ** 2 + gps["v"] ** 2)

    gps = gps.sort_values(["id", "ts"]).reset_index(drop=True)
    if "heading" not in gps.columns:
        gps["heading"] = gps.groupby("id", group_keys=False).apply(
            lambda g: pd.Series(
                calc_bearing(g["lat"].shift(1).to_numpy(), g["lon"].shift(1).to_numpy(), g["lat"].to_numpy(), g["lon"].to_numpy()),
                index=g.index,
            )
        )

    heading_rad = np.radians(gps["heading"])
    # 正值表示顺风分量，负值表示逆风分量
    gps["wind_support"] = gps["u"] * np.sin(heading_rad) + gps["v"] * np.cos(heading_rad)

    gps = gps.drop(columns=["lon_for_era"], errors="ignore")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    gps.to_csv(out_path, index=False)

    print(f"完成，输出: {out_path}")
    print(gps[["temp_C", "u", "v", "wind_speed", "wind_support"]].describe())


if __name__ == "__main__":
    main()
