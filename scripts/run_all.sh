#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT="$ROOT"
cd "$ROOT"

SP="${SPECIES_CODE:-curlew}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
PYTHON_BIN="${PYTHON_BIN:-python}"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "缺少文件: $path" >&2
    exit 1
  fi
}

check_csv() {
  local path="$1"
  shift
  require_file "$path"
  "$PYTHON_BIN" - "$path" "$@" <<'PY'
import sys
from pathlib import Path
import pandas as pd

path = Path(sys.argv[1])
required = sys.argv[2:]
df = pd.read_csv(path, nrows=5)
missing = [c for c in required if c not in df.columns]
if missing:
    raise SystemExit(f"{path} 缺少关键列: {', '.join(missing)}")
rows = sum(1 for _ in path.open("r", encoding="utf-8", errors="ignore")) - 1
print(f"检查通过: {path} rows={max(rows, 0)} columns={len(df.columns)}")
PY
}

run_step() {
  local name="$1"
  shift
  echo
  echo "=== $name ==="
  "$@"
}

run_step "A0 原始数据检查" "$RSCRIPT_BIN" R/02_check_raw.R
check_csv "output/tables/00_raw_summary.csv"

run_step "A1 轨迹清洗" "$RSCRIPT_BIN" R/03_clean_tracking.R
check_csv "data/clean/${SP}_clean.csv" id ts lat lon

run_step "A2 轨迹规则化" "$RSCRIPT_BIN" R/04_regularize_tracks.R
check_csv "data/clean/${SP}_regular.csv" id

run_step "B1 ERA5 环境匹配" "$PYTHON_BIN" py/05_match_era5.py --project-root "$ROOT"
check_csv "data/clean/${SP}_env_matched.csv" id ts lat lon temp_C wind_support wind_speed

run_step "B2 NDVI 匹配" "$RSCRIPT_BIN" R/05b_match_ndvi.R
check_csv "data/clean/${SP}_env_matched_ndvi.csv" id ts lat lon temp_C wind_support wind_speed ndvi

run_step "C1 HMM 输入准备" "$RSCRIPT_BIN" R/06_prepare_hmm_data.R
check_csv "data/processed/${SP}_hmm_input.csv" ID original_id ts lon lat temp_C wind_support ndvi step angle

run_step "C2 HMM 模型拟合" "$RSCRIPT_BIN" R/07_fit_hmm_models.R
require_file "output/models/${SP}_hmm_best.rds"
check_csv "output/tables/07_hmm_bic_compare.csv" states AIC BIC

run_step "C3 HMM 状态解码" "$RSCRIPT_BIN" R/08_decode_hmm.R
check_csv "data/processed/${SP}_states_decoded.csv" state state_label step

run_step "C4 状态 NDVI 回填" "$RSCRIPT_BIN" R/08b_add_ndvi_to_states.R
check_csv "data/processed/${SP}_states_decoded_env.csv" state state_label step ndvi

run_step "D1 Lévy 拟合与停歇事件识别" "$PYTHON_BIN" py/09_levy_stopovers.py --project-root "$ROOT"
check_csv "data/processed/${SP}_levy_result.csv" alpha xmin flight_definition
check_csv "data/processed/${SP}_stopover_events.csv" cluster_id event_id site_id individual_id duration_hr
check_csv "data/processed/${SP}_stopover_sites.csv" site_id total_span_hr n_events

run_step "D2 停歇事件环境回填" "$RSCRIPT_BIN" R/09b_rebuild_stopovers_env.R
check_csv "data/processed/${SP}_stopover_events_env.csv" cluster_id event_id site_id individual_id duration_hr ndvi_arrive wind_support

run_step "D3 最优停止模型" "$RSCRIPT_BIN" R/10_optimal_stopping.R
check_csv "output/tables/10_optimal_stopping_params.csv" lambda_proxy Qstar_proxy

run_step "D4 停歇敏感性分析" "$RSCRIPT_BIN" R/10b_stopover_sensitivity.R
check_csv "output/tables/10b_stopover_sensitivity_summary.csv" model_name n

run_step "E 气候/资源情景预测" "$RSCRIPT_BIN" R/11_climate_scenario_projection.R
check_csv "output/tables/11_climate_scenario_projection.csv" scenario cluster_id pred_duration_hr

run_step "F SCVI 稳健保育排序" "$RSCRIPT_BIN" R/12_scvi_conservation_value.R
check_csv "output/tables/12_scvi_stopover_ranking.csv" rank cluster_id duration_scvi_hr SCVI conservation_class
check_csv "output/tables/12_scvi_rank_stability.csv"

echo
echo "=== 完整 A-F pipeline 运行完成 ==="
