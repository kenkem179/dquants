#!/usr/bin/env bash
# sync-presets-on-set.sh — PostToolUse hook.
#
# WHY: MT5's Strategy-Tester "Load" dialog reads the organized SYMLINK VIEW at
#   MQL5/Profiles/Tester/dquants -> dquants/mql5/experts/Presets/<EXPERT>/
# which is rebuilt by scripts/sync_presets.sh. A brand-new .set dropped into an EA folder
# (mql5/experts/<EXPERT>/*.set) is the source of truth but is INVISIBLE in MT5 until that
# view is regenerated. Forgetting the sync = "I can't find the .set" (the recurring trap).
#
# WHAT: whenever a Write/Edit/MultiEdit touches a *.set under mql5/experts/, re-run
# sync_presets.sh (idempotent, symlinks-only — never edits .set files, so it can't loop).
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
input="$(cat 2>/dev/null || true)"

# Extract the edited file path from the PostToolUse payload (system python3 is fine for json).
fp="$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path",""))
except Exception:
    print("")' 2>/dev/null || true)"

case "$fp" in
  *mql5/experts/*.set)
    if [ -x "$ROOT/scripts/sync_presets.sh" ]; then
      if bash "$ROOT/scripts/sync_presets.sh" >/dev/null 2>&1; then
        echo "[hook] MT5 preset view synced — '$(basename "$fp")' is now visible in MT5 Tester -> Inputs -> Load -> dquants/<expert>/"
      else
        echo "[hook] WARNING: scripts/sync_presets.sh failed — run it manually so '$(basename "$fp")' shows in MT5's Load dialog." >&2
      fi
    fi
    ;;
esac
exit 0
