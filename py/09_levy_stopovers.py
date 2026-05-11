#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import DBSCAN


EARTH_RADIUS_KM = 6371.0
STOP_LABELS = {"停歇", "局部活动/觅食"}


def find_project_root(start: Path) -> Path:
    start = start.resolve()
    for p in [start.parent, *start.parents]:
        if (p / "config" / "project_config.json").exists():
            return p
    raise FileNotFoundError(f"找不到 config/project_config.json，起始位置: {start}")


def load_config(project_root: Path) -> dict:
    return json.loads((project_root / "config" / "project_config.json").read_text(encoding="utf-8"))


def fit_levy(step_series: pd.Series) -> dict:
    import powerlaw

    flight = step_series.dropna()
    flight = flight[flight > 0.5]
    if len(flight) < 30:
        raise ValueError("飞行段样本过少，无法稳定进行 Lévy 拟合。")

    fit = powerlaw.Fit(flight.values, xmin=None, discrete=False, verbose=False)
    r_ln, p_ln = fit.distribution_compare("power_law", "lognormal")
    r_ex, p_ex = fit.distribution_compare("power_law", "exponential")
    return {
        "alpha": float(fit.alpha),
        "xmin": float(fit.xmin),
        "R_lognormal": float(r_ln),
        "p_lognormal": float(p_ln),
        "R_exponential": float(r_ex),
        "p_exponential": float(p_ex),
        "n_steps": int(len(flight)),
    }


def choose_flight_steps(df: pd.DataFrame) -> tuple[str, pd.Series]:
    labels = set(df["state_label"].dropna().astype(str))
    if "高速飞行" in labels and (df["state_label"] == "高速飞行").sum() >= 30:
        return "高速飞行", df.loc[df["state_label"] == "高速飞行", "step"]
    if "飞行" in labels:
        return "飞行", df.loc[df["state_label"] == "飞行", "step"]
    raise ValueError(f"状态标签中找不到飞行状态。实际标签: {sorted(labels)}")


def get_id_col(df: pd.DataFrame) -> str:
    for col in ["original_id", "id", "ID"]:
        if col in df.columns:
            return col
    raise ValueError("状态文件中找不到 original_id / id / ID")


def summarize_event(grp: pd.DataFrame, event_id: int, id_col: str) -> dict:
    grp = grp.sort_values("ts")
    arrive = pd.to_datetime(grp["ts"].iloc[0])
    depart = pd.to_datetime(grp["ts"].iloc[-1])
    duration_hr = (depart - arrive).total_seconds() / 3600.0
    ndvi_vals = grp["ndvi"] if "ndvi" in grp else pd.Series(dtype=float)

    return {
        "cluster_id": int(event_id),
        "event_id": int(event_id),
        "site_id": int(grp["site_id"].iloc[0]),
        "individual_id": grp[id_col].mode().iloc[0],
        "lat_center": float(grp["lat"].mean()),
        "lon_center": float(grp["lon"].mean()),
        "arrive_time": arrive.isoformat(),
        "depart_time": depart.isoformat(),
        "duration_hr": float(duration_hr),
        "ndvi_mean": float(ndvi_vals.mean()) if len(ndvi_vals) else np.nan,
        "ndvi_arrive": float(ndvi_vals.dropna().iloc[0]) if len(ndvi_vals.dropna()) else np.nan,
        "wind_support": float(grp["wind_support"].mean()) if "wind_support" in grp else np.nan,
        "n_points": int(len(grp)),
    }


def detect_stopover_events(
    df: pd.DataFrame,
    eps_km: float,
    min_samples: int,
    max_gap_hr: float,
    min_duration_hr: float,
    max_duration_hr: float,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    id_col = get_id_col(df)
    df_stop = df[df["state_label"].isin(STOP_LABELS)].copy()
    if df_stop.empty:
        return pd.DataFrame(), pd.DataFrame()

    df_stop["ts"] = pd.to_datetime(df_stop["ts"], utc=True).dt.tz_localize(None)
    df_stop = df_stop.dropna(subset=["lat", "lon", "ts"]).sort_values([id_col, "ts"])

    coords_rad = np.radians(df_stop[["lat", "lon"]].to_numpy())
    db = DBSCAN(eps=eps_km / EARTH_RADIUS_KM, min_samples=min_samples, metric="haversine")
    df_stop["site_id"] = db.fit_predict(coords_rad)
    df_stop = df_stop[df_stop["site_id"] >= 0].copy()
    if df_stop.empty:
        return pd.DataFrame(), pd.DataFrame()

    events = []
    event_id = 0
    for _, by_id in df_stop.groupby(id_col, sort=False):
        by_id = by_id.sort_values("ts").copy()
        gap_hr = by_id["ts"].diff().dt.total_seconds().div(3600)
        new_event = gap_hr.isna() | (gap_hr > max_gap_hr) | (by_id["site_id"] != by_id["site_id"].shift())
        by_id["visit_event"] = new_event.cumsum()

        for _, grp in by_id.groupby("visit_event", sort=False):
            row = summarize_event(grp, event_id, id_col)
            if min_duration_hr <= row["duration_hr"] <= max_duration_hr:
                events.append(row)
                event_id += 1

    events_df = pd.DataFrame(events)
    site_rows = []
    for site_id, grp in df_stop.groupby("site_id"):
        site_events = events_df[events_df["site_id"] == site_id] if not events_df.empty else pd.DataFrame()
        first = grp["ts"].min()
        last = grp["ts"].max()
        site_rows.append({
            "site_id": int(site_id),
            "lat_center": float(grp["lat"].mean()),
            "lon_center": float(grp["lon"].mean()),
            "first_seen": first.isoformat(),
            "last_seen": last.isoformat(),
            "total_span_hr": float((last - first).total_seconds() / 3600.0),
            "n_points": int(len(grp)),
            "n_individuals": int(grp[id_col].nunique()),
            "n_events": int(len(site_events)),
            "event_duration_sum_hr": float(site_events["duration_hr"].sum()) if not site_events.empty else 0.0,
            "ndvi_mean": float(grp["ndvi"].mean()) if "ndvi" in grp else np.nan,
            "wind_support": float(grp["wind_support"].mean()) if "wind_support" in grp else np.nan,
        })

    return events_df, pd.DataFrame(site_rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Lévy 拟合与连续停歇事件识别")
    parser.add_argument("--project-root", default=None)
    parser.add_argument("--max-gap-hr", type=float, default=12.0, help="连续访问事件允许的最大时间间隔")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(__file__))
    cfg = load_config(project_root)
    sp = cfg["project"]["species_code"]

    processed_dir = project_root / "data" / "processed"
    states_env_path = processed_dir / f"{sp}_states_decoded_env.csv"
    states_path = states_env_path if states_env_path.exists() else processed_dir / f"{sp}_states_decoded.csv"
    if not states_path.exists():
        raise FileNotFoundError(f"找不到状态解码结果: {states_path}")

    processed_dir.mkdir(parents=True, exist_ok=True)
    df = pd.read_csv(states_path)
    if "ts" not in df.columns and "t_" in df.columns:
        df["ts"] = df["t_"]

    flight_definition, flight_steps = choose_flight_steps(df)
    levy = fit_levy(flight_steps)
    levy["flight_definition"] = flight_definition
    pd.DataFrame([levy]).to_csv(processed_dir / f"{sp}_levy_result.csv", index=False)

    stop_cfg = cfg["stopover"]
    events, sites = detect_stopover_events(
        df=df,
        eps_km=float(stop_cfg["eps_km"]),
        min_samples=int(stop_cfg["min_samples"]),
        max_gap_hr=float(stop_cfg.get("max_gap_hr", args.max_gap_hr)),
        min_duration_hr=float(stop_cfg.get("min_duration_hr", 1)),
        max_duration_hr=float(stop_cfg.get("max_duration_hr", 720)),
    )

    events.to_csv(processed_dir / f"{sp}_stopover_events.csv", index=False)
    sites.to_csv(processed_dir / f"{sp}_stopover_sites.csv", index=False)
    # 保留历史文件名，但现在它表示连续停歇事件，而非多年空间热点。
    events.to_csv(processed_dir / f"{sp}_stopovers.csv", index=False)

    print("Lévy 结果：")
    print(pd.DataFrame([levy]))
    print("连续停歇事件数量:", len(events))
    print("长期重复利用地点数量:", len(sites))


if __name__ == "__main__":
    main()
