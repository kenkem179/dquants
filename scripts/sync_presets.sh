#!/usr/bin/env bash
# sync_presets.sh — (re)build the organized MT5 preset tree + the MT5 Tester symlink.
#
# WHAT THIS DOES
#   1. Rebuilds  mql5/experts/Presets/<EXPERT>/<name>.set  as a tidy, by-expert VIEW
#      of the canonical deploy/A-B presets. The Presets/ entries are SYMLINKS, never
#      copies — the source of truth stays where the docs/release.conf already point:
#        - KK-MasterVP, KK-MasterVP-Monster, KK-KenKem : the EA folder's own *.set
#        - KK-KenKem deploy-candidate winners (D3/D4)   : research/kenkem_parity/*.set
#      (Symlinks => zero drift. Edit the source .set; the view updates for free.)
#   2. (Re)creates the MT5 Strategy-Tester symlink so the whole tree shows up in the
#      Tester's "Load" dialog organized by expert:
#        MQL5/Profiles/Tester/dquants -> dquants/mql5/experts/Presets
#      (Profiles/Tester is itself a symlink into the kenkem repo; that's expected.)
#
# RUN THIS after: cloning fresh, adding a new deploy .set to an EA folder, or if the
# MT5 link is missing. Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPERTS="$ROOT/mql5/experts"
PRESETS="$EXPERTS/Presets"
MT5_TESTER="/Users/tokyotechies/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Profiles/Tester"

# Experts whose top-level *.set are surfaced verbatim:
EA_EXPERTS=(KK-MasterVP KK-MasterVP-Monster KK-KenKem)

# Extra KK-KenKem deploy candidates whose canonical home is research/kenkem_parity:
KENKEM_RESEARCH_SETS=(
  KK-KenKem-XAUUSD-M1-D3-noE4.set   # ⭐ current LOCK
  KK-KenKem-XAUUSD-M1-D3.set
  KK-KenKem-XAUUSD-M1-D4.set
  KK-KenKem-XAUUSD-M1-D4-E5.set
  KK-KenKem-XAUUSD-M1-D4-E4.set        # E4 re-test A/B (engine exits fictional → MT5 decides)
  KK-KenKem-XAUUSD-M1-D4-E2RR14.set    # D4 + E2_RR 1.4 refinement (survived d5 joint test)
)

echo "==> rebuilding $PRESETS"
rm -rf "$PRESETS"
for ea in "${EA_EXPERTS[@]}"; do
  mkdir -p "$PRESETS/$ea"
  shopt -s nullglob
  for f in "$EXPERTS/$ea"/*.set; do
    b="$(basename "$f")"
    ln -sfn "../../$ea/$b" "$PRESETS/$ea/$b"
    echo "   $ea/$b -> ../../$ea/$b"
  done
  shopt -u nullglob
done

# KK-KenKem research winners (path: Presets/KK-KenKem/ -> dquants/ is ../../../../)
for b in "${KENKEM_RESEARCH_SETS[@]}"; do
  src="$ROOT/research/kenkem_parity/$b"
  [ -f "$src" ] || { echo "   !! missing $src (skipped)"; continue; }
  ln -sfn "../../../../research/kenkem_parity/$b" "$PRESETS/KK-KenKem/$b"
  echo "   KK-KenKem/$b -> ../../../../research/kenkem_parity/$b"
done

echo "==> linking MT5 Tester: $MT5_TESTER/dquants"
if [ -d "$MT5_TESTER" ] || [ -L "$MT5_TESTER" ]; then
  ln -sfn "$PRESETS" "$MT5_TESTER/dquants"
  echo "   ok -> $PRESETS"
else
  echo "   !! MT5 Tester dir not found (MT5 not installed here?) — skipped"
fi

echo "==> done. In MT5 Strategy Tester -> Inputs -> Load, open the 'dquants/<expert>/' folder."
