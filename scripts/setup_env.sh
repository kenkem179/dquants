#!/usr/bin/env bash
# Sets up the KenKem Quant OS Python research environment.
# NATIVE arm64 Miniforge (conda-forge) + Python 3.11 + the research stack.
# Installed to ~/miniforge3 directly from the official installer — NOT via x86 Homebrew,
# so the env runs native on Apple Silicon (M-series) instead of under Rosetta.
# Idempotent: safe to re-run.
set -euo pipefail

ENV_NAME="kenkem"
PY_VERSION="3.11"
MF_DIR="$HOME/miniforge3"
ARCH="$(uname -m)"   # expect arm64 on M-series

echo "==> Architecture: ${ARCH}"
if [ "${ARCH}" != "arm64" ]; then
  echo "WARNING: not arm64 — this script targets native Apple Silicon." >&2
fi

# 1. Native Miniforge
if [ ! -x "${MF_DIR}/bin/conda" ]; then
  echo "==> Downloading native Miniforge (${ARCH})..."
  INSTALLER="/tmp/Miniforge3-MacOSX-${ARCH}.sh"
  curl -fsSL -o "${INSTALLER}" \
    "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-${ARCH}.sh"
  echo "==> Installing Miniforge to ${MF_DIR}..."
  bash "${INSTALLER}" -b -p "${MF_DIR}"
fi

source "${MF_DIR}/etc/profile.d/conda.sh"
echo "==> conda: $(conda --version) @ ${MF_DIR}"

# 2. Create env
if ! conda env list | grep -qE "^${ENV_NAME}\s"; then
  echo "==> Creating env '${ENV_NAME}' (python ${PY_VERSION})..."
  conda create -y -n "${ENV_NAME}" "python=${PY_VERSION}"
fi
conda activate "${ENV_NAME}"

# 3a. OpenMP-sensitive / compiled libs via conda-forge (proper arm64 builds + llvm-openmp).
#     Installing these through conda avoids the libomp.dylib hell that pip wheels cause.
echo "==> Installing compiled libs via conda-forge..."
conda install -y -c conda-forge \
  polars duckdb pyarrow pandas \
  numpy scipy statsmodels scikit-learn \
  lightgbm xgboost shap \
  optuna matplotlib plotly \
  jupyterlab ipykernel pytest pyyaml tqdm

# 3b. Pip-only / lighter libs.
echo "==> Installing pip-only libs..."
python -m pip install --upgrade pip
python -m pip install vectorbt ta streamlit hdbscan

# 4. Verify native + imports
echo "==> Smoke test..."
python - <<'PY'
import platform
print("python arch:", platform.machine())
import polars, duckdb, pyarrow, numpy, scipy, statsmodels, sklearn
import lightgbm, xgboost, shap, optuna, vectorbt, plotly, matplotlib, ta, pandas
print("Smoke test OK — all imports loaded")
PY

echo "==> DONE. Activate with:  source ${MF_DIR}/etc/profile.d/conda.sh && conda activate ${ENV_NAME}"
