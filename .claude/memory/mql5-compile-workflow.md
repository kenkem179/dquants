---
name: mql5-compile-workflow
description: "How to compile MQL5 headlessly on this Mac (wine64 + MetaEditor) — do it freely, no need to ask"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

The user CANNOT compile on mobile but authorized me to compile MQL5 myself, freely, without asking
(2026-06-14). Use `dquants/scripts/compile_mql5.sh <path-to.mq5>` — it wraps the bundled wine64 +
MetaEditor64.exe (borrowed from `../kenkem/scripts/launch_mt5.sh`), re-encodes the UTF-16 log, and exits
0 only if a `.ex5` is produced. Prints `Result: N errors, M warnings`.

Toolchain facts:
- Native app `/Applications/MetaTrader 5.app`; bundled wine at
  `.../Contents/SharedSupport/wine/bin/wine64`; WINEPREFIX = `~/Library/Application Support/net.metaquotes.wine.metatrader5`.
- MetaEditor = `$WINEPREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe`. Z: drive maps to unix `/`.
- **EAs must live under the wine MT5 `MQL5/Experts/`** — the repo folders are SYMLINKED in (KenKem,
  KK-MasterVP, KK-MasterVP-Monster, KK-Common, …). For a new EA folder, symlink it:
  `ln -sfn <repo>/MQL5/Experts/<Dir> "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/MQL5/Experts/<Dir>"`.
- The kenkem repo also has `make compile EA=<dir>/<file>.mq5` (and `make status`, `make launch`).

Build artifacts (`*.ex5`, `*.compile.log`) are throwaway — don't commit them.
Relates to [[milestone-production-promotion]].
