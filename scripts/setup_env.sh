#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON_BIN="${PYTHON_BIN:-python3}"
RSCRIPT_BIN="${RSCRIPT_BIN:-Rscript}"
CREATE_VENV="${CREATE_VENV:-0}"
SKIP_PYTHON="${SKIP_PYTHON:-0}"
SKIP_R="${SKIP_R:-0}"

echo "Project root: $ROOT"

if [[ "$SKIP_PYTHON" != "1" ]]; then
  if [[ "$CREATE_VENV" == "1" ]]; then
    if [[ ! -d ".venv" ]]; then
      echo "Creating Python virtual environment: .venv"
      "$PYTHON_BIN" -m venv .venv
    fi
    PYTHON_BIN="$ROOT/.venv/bin/python"
  fi

  echo "Using Python: $PYTHON_BIN"
  "$PYTHON_BIN" -m pip install --upgrade pip
  "$PYTHON_BIN" -m pip install -r requirements.txt
fi

if [[ "$SKIP_R" != "1" ]]; then
  echo "Using Rscript: $RSCRIPT_BIN"
  "$RSCRIPT_BIN" scripts/install_r_packages.R
fi

echo "Environment setup complete."
