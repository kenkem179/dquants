#!/bin/bash
# KK-MasterVP-Profiler — MQL5-Market edition builder
# ----------------------------------------------------------------------------
# The Profiler #includes the EA stack (KK-MasterVP/Inputs.mqh) so its trade
# markers replay the EA's OWN logic (single-source parity). A side effect: the
# 52 user-facing `input` params in Inputs.mqh leak into the Profiler's dialog —
# fine for the DEV build (drive the indicator from the EA .set), wrong for a
# MARKET buyer who'd see a wall of strategy params they shouldn't touch on an
# indicator.
#
# This builds the MARKET edition: every `input` in Inputs.mqh is stripped to a
# plain global (its compiled-in default = the lock value, so behaviour is
# IDENTICAL and the markers stay EA-exact), hiding all 52 from the dialog. The
# Profiler's OWN ~25 display knobs (InpSet*/InpShow*/InpHist*/InpEma*Len/InpViz*/
# InpApplyTheme, declared in the .mq5) stay visible. Inputs.mqh is copied first
# and restored byte-identical afterwards (shasum-checked) — the EA dev source is
# never altered.
#
# Output: KK-MasterVP-Profiler-Market.ex5 next to the dev .ex5 (gitignored).
#   ./scripts/make_profiler_market.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROF_DIR="$ROOT/mql5/indicators/KK-MasterVP-Profiler"
SRC="$PROF_DIR/KK-MasterVP-Profiler.mq5"
INPUTS="$ROOT/mql5/experts/KK-MasterVP/Inputs.mqh"
DEV_EX5="$PROF_DIR/KK-MasterVP-Profiler.ex5"
MKT_EX5="$PROF_DIR/KK-MasterVP-Profiler-Market.ex5"

[ -f "$SRC" ]    || { echo "✗ missing $SRC"; exit 1; }
[ -f "$INPUTS" ] || { echo "✗ missing $INPUTS"; exit 1; }

BACKUP="$INPUTS.profmkt.bak"
SUM_BEFORE="$(shasum "$INPUTS" | awk '{print $1}')"
cp -f "$INPUTS" "$BACKUP"

restore() {
  if [ -f "$BACKUP" ]; then
    cp -f "$BACKUP" "$INPUTS" && rm -f "$BACKUP"
    local sum_after; sum_after="$(shasum "$INPUTS" | awk '{print $1}')"
    if [ "$sum_after" != "$SUM_BEFORE" ]; then
      echo "✗ SAFETY: Inputs.mqh not restored byte-identical ($SUM_BEFORE -> $sum_after)"; exit 2
    fi
    echo "  ✓ Inputs.mqh restored byte-identical"
  fi
}
trap restore EXIT

echo "[1/3] Stripping the EA's 'input' surface from Inputs.mqh (market hide)..."
# Drop the dialog separators (input group ...) and the `input ` keyword on each
# `input <type> Inp...` declaration -> plain global, default (= lock) preserved.
VISIBLE_BEFORE="$(grep -cE '^[[:space:]]*input ' "$INPUTS" || true)"
perl -i -pe 's{^(\s*)input(\s+group\b)}{$1//input$2};        # comment out group separators
             s{^(\s*)input(\s+\w[\w\*]*\s+Inp)}{$1$2};'     "$INPUTS"  # input <type> Inp.. -> <type> Inp..
VISIBLE_AFTER="$(grep -cE '^[[:space:]]*input ' "$INPUTS" || true)"
echo "  ✓ Inputs.mqh dialog inputs: $VISIBLE_BEFORE -> $VISIBLE_AFTER (target 0)"

echo "[2/3] Compiling the market edition..."
bash "$ROOT/scripts/compile_mql5.sh" "$SRC" | tail -2
[ -f "$DEV_EX5" ] || { echo "✗ compile produced no .ex5"; exit 3; }
mv -f "$DEV_EX5" "$MKT_EX5"
echo "  ✓ $MKT_EX5"

echo "[3/3] Restoring dev source + rebuilding the dev .ex5..."
restore; trap - EXIT
bash "$ROOT/scripts/compile_mql5.sh" "$SRC" | tail -1
PROF_VISIBLE="$(grep -cE '^[[:space:]]*input ' "$SRC" || true)"
echo ""
echo "✓ Market Profiler built: $MKT_EX5"
echo "  visible dialog inputs = the Profiler's own $PROF_VISIBLE display knobs (EA params hidden+baked)"
echo "  dev .ex5 rebuilt; working tree unchanged (Inputs.mqh byte-identical)."
