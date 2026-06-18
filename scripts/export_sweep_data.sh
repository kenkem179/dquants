#!/usr/bin/env bash
# Export the bars/ticks CSVs the C++ engines replay, straight from the processed Parquet tick store.
# Produces EXACTLY the filenames the sweep + optimizers expect (see research/optimization/*.py SYM):
#   Monster needs   bars_<sym>_2025_{m3,m1,m5}.csv  +  the tick window CSV
#   KK-MasterVP uses bars_<sym>_2025_m3.csv          +  the tick window CSV
#
# Run with the kenkem env active (needs duckdb):  conda activate kenkem
# Usage:   bash scripts/export_sweep_data.sh [btc|xau|all] [--force]
# Idempotent: skips a CSV that already exists unless --force is given.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

WHICH="${1:-all}"
FORCE=0
[[ "${2:-}" == "--force" ]] && FORCE=1

command -v python >/dev/null || { echo "no 'python' on PATH — run: conda activate kenkem" >&2; exit 1; }
python -c "import duckdb" 2>/dev/null || { echo "duckdb missing — run: conda activate kenkem" >&2; exit 1; }

# Per-symbol window. bars are exported from parquet start up to END (warmup history included);
# ticks are restricted to [START,END). trade_from (inside the optimizer) gates the trading start.
# cols: parquet_sym  year  src   start        end          ticks_out_csv
declare -A CFG=(
  [btc]="btcusd 2025 clean 2025-08-11 2025-12-01 cpp_core/tools/ticks_btcusd_2025_window.csv"
  [xau]="xauusd 2025 clean 2025-08-01 2025-12-01 cpp_core/tools/ticks_xauusd_window.csv"
)

export_one() {
  local key="$1"; read -r SYM YEAR SRC START END TICKS <<<"${CFG[$key]}"
  local pq="data/processed/ticks_${SYM}_${YEAR}_clean.parquet"
  [[ -f "$pq" ]] || { echo "MISSING parquet: $pq — run the import pipeline first (/quant-1-import-data)"; exit 2; }
  echo "==> [$key] $SYM $START..$END"
  for tf in m3 m1 m5; do
    local out="cpp_core/tools/bars_${SYM}_${YEAR}_${tf}.csv"
    if [[ $FORCE -eq 0 && -f "$out" ]]; then echo "    skip $out (exists)"; continue; fi
    python cpp_core/tools/export_bars.py "$YEAR" "$SRC" "$END" "$out" "$SYM" "$tf"
  done
  if [[ $FORCE -eq 0 && -f "$TICKS" ]]; then echo "    skip $TICKS (exists)"; else
    python cpp_core/tools/export_ticks.py "$YEAR" "$SRC" "$START" "$END" "$TICKS" "$SYM"
  fi
}

case "$WHICH" in
  btc) export_one btc ;;
  xau) export_one xau ;;
  all) export_one btc; export_one xau ;;
  *)   echo "usage: bash scripts/export_sweep_data.sh [btc|xau|all] [--force]" >&2; exit 2 ;;
esac
echo "==> data ready under cpp_core/tools/"
