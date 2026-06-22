#!/usr/bin/env bash
# run_grid_4mkts.sh — run one WF grid across all 4 KK-MasterVP markets (BTC/XAU x M3/M5) in parallel.
# Usage: run_grid_4mkts.sh '<grid-json>' <tag> [extra wf_mvp_generic args...]
set -euo pipefail
cd "$(dirname "$0")"
GRID="$1"; TAG="$2"; shift 2
EXTRA=("$@")   # save extra args BEFORE the loop ('set --' inside would clobber $@ -> the old bug)
OUT=tp1_2026-06-23
mkdir -p "$OUT"
for m in "xau m3" "xau m5" "btc m3" "btc m5"; do
  read -r sym tf <<< "$m"
  ( python3 wf_mvp_generic.py --symbol "$sym" --tf "$tf" --grid "$GRID" --tag "$TAG" --show-folds "${EXTRA[@]+"${EXTRA[@]}"}" \
      > "$OUT/${TAG}_${sym}_${tf}.out" 2>&1 ) &
done
wait
echo "=== grid [$TAG] ALL 4 MARKETS DONE ==="
for f in "$OUT/${TAG}_"*.out; do echo "############ $f"; sed -n '/=== RANKED/,$p' "$f"; echo; done
