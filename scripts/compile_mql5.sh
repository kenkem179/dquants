#!/bin/bash
# Headless MQL5 compiler for macOS — borrowed from ../kenkem scripts/launch_mt5.sh.
# Compiles a .mq5 via the bundled wine64 + MetaEditor64.exe and prints the log.
# Usage: scripts/compile_mql5.sh <absolute-or-repo path to .mq5>
# Exit 0 on success (.ex5 produced), 1 on failure. Errors/warnings echoed.
set -u

MT5_PATH="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
MT5_PROG="$MT5_PATH/drive_c/Program Files/MetaTrader 5"
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64"

SRC="${1:?usage: compile_mql5.sh <file.mq5>}"
[ -f "$SRC" ] || { echo "✗ not found: $SRC"; exit 1; }
SRC_ABS="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"

# MQL5 Market validator rejects non-Latin chars in displayed strings/labels
# (error NON_LATIN: "All program messages must be in English"). Comments after
# an `input` become the on-screen parameter label, so they count too. Catch any
# non-ASCII byte locally before it reaches the Market. We scan the .mq5 plus the
# .mqh it pulls in (resolved relative to its dir) so an include can't smuggle a
# stray em-dash past us. Pure ASCII source can never trip NON_LATIN.
SCAN_FILES="$SRC_ABS"
while IFS= read -r inc; do
  cand="$(cd "$(dirname "$SRC_ABS")" && cd "$(dirname "$inc")" 2>/dev/null && pwd)/$(basename "$inc")"
  [ -f "$cand" ] && SCAN_FILES="$SCAN_FILES"$'\n'"$cand"
done < <(grep -hoE '#include[[:space:]]+"[^"]+"' "$SRC_ABS" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
NONASCII="$(printf '%s\n' "$SCAN_FILES" | sort -u | tr '\n' '\0' | xargs -0 grep -nP '[^\x00-\x7F]' 2>/dev/null || true)"
if [ -n "$NONASCII" ]; then
  echo "✗ NON-ASCII characters found (MQL5 Market NON_LATIN risk). Fix these:"
  echo "$NONASCII"
  echo "  -> replace em/en dashes (— –) with '-', smart quotes with ' \", etc."
  exit 1
fi
LOG="${SRC_ABS%.mq5}.compile.log"
EX5="${SRC_ABS%.mq5}.ex5"
rm -f "$EX5"

echo "Compiling: $SRC_ABS"
WINEDEBUG=-all WINEPREFIX="$MT5_PATH" "$WINE" \
    "C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe" \
    "/compile:Z:$SRC_ABS" "/log:Z:$LOG" 2>/dev/null

# MetaEditor logs are UTF-16; re-encode to UTF-8 for display.
if [ -f "$LOG" ]; then
  python3 - "$LOG" <<'PY' 2>/dev/null || true
import sys
p=sys.argv[1]; raw=open(p,'rb').read()
for enc in ('utf-16','utf-16-le','utf-8-sig','utf-8'):
    try: open(p,'w',encoding='utf-8').write(raw.decode(enc)); break
    except Exception: pass
PY
  grep -iE "error|warning|result" "$LOG" || cat "$LOG"
fi

if [ -f "$EX5" ]; then echo "✓ OK: $(basename "$EX5")"; exit 0; else echo "✗ FAILED (no .ex5)"; exit 1; fi
