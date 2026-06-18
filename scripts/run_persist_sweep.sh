#!/usr/bin/env bash
# Feature #1 (entry-persistence / DI-spread proxy) — one-stop sweep runner.
# After `conda activate kenkem`, this is the only command you need: it builds the C++ engines,
# exports any missing bar/tick CSVs from the Parquet store, then sweeps the gate (N×min grid +
# baseline) on BOTH engines (Monster first, then KK-MasterVP) for the requested symbol(s), on the
# same BTC/XAU M3 basis as MONSTER-FINDINGS. Results: research/optimization/sweep_persist_<eng>_<sym>.csv
#
# Usage:
#   conda activate kenkem
#   bash scripts/run_persist_sweep.sh [btc|xau|all] [--force-export]
#
# Skips cleanly with an actionable message if the env or the Parquet store is missing.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

WHICH="${1:-all}"
FORCE_EXPORT="${2:-}"

command -v python >/dev/null || { echo "no 'python' — run: conda activate kenkem" >&2; exit 1; }
python -c "import duckdb" 2>/dev/null || { echo "duckdb missing — run: conda activate kenkem (or bash scripts/setup_env.sh)" >&2; exit 1; }

case "$WHICH" in btc) SYMS=(btc);; xau) SYMS=(xau);; all) SYMS=(btc xau);; *)
  echo "usage: bash scripts/run_persist_sweep.sh [btc|xau|all] [--force-export]" >&2; exit 2;; esac

echo "==> 1/3 build C++ engines"
make -C cpp_core monster backtester >/dev/null
echo "    ok: cpp_core/build/{monster_backtester,backtester}"

echo "==> 2/3 ensure bar/tick data"
for s in "${SYMS[@]}"; do bash scripts/export_sweep_data.sh "$s" ${FORCE_EXPORT:+--force}; done

echo "==> 3/3 sweep (Monster first, then KK-MasterVP)"
LOG=research/optimization
for s in "${SYMS[@]}"; do
  for eng in monster masterv; do
    echo "----- $eng / $s -----"
    python research/optimization/sweep_entry_persist.py "$eng" "$s" | tee "$LOG/sweep_persist_${eng}_${s}.log"
  done
done
echo "==> done. tables: $LOG/sweep_persist_*.csv  (logs: sweep_persist_*.log)"
