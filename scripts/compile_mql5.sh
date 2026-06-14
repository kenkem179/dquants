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
