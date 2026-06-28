#!/usr/bin/env bash
# SessionStart hook — AUTOPILOT COMPACTION CONTINUITY.
#
# WHAT IT DOES: fires on every session start; only acts when the session was resumed FROM A
# COMPACTION (source == "compact") or a --resume (source == "resume"). It re-injects the
# HANDOFF.md baton + an "continue autonomously" directive so an in-flight autonomous run
# survives auto-compact without losing the thread or stopping to re-ask.
#
# WHY THIS SHAPE (and not "auto /compact at 30%"): Claude Code has NO supported way to trigger
# /compact at a custom context %, no context-size hook event, and hooks cannot invoke slash
# commands. BUT the built-in auto-compact (autoCompactEnabled, default true) already compacts
# near the limit and CONTINUES the turn automatically. This hook makes that automatic compaction
# SAFE for autopilot by restoring the working context every time it happens (self-renewing: it
# re-fires on each subsequent compaction too).
#
# Output: SessionStart `additionalContext` JSON. Stays silent (exit 0, no output) on a fresh
# startup/clear so it never nags an interactive session.

set -uo pipefail

payload="$(cat)"
proj="${CLAUDE_PROJECT_DIR:-$(pwd)}"
handoff="$proj/HANDOFF.md"

# Pull the trigger source out of the hook payload (python3 is always present on macOS).
source_val="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source",""))
except Exception: print("")' 2>/dev/null || echo "")"

# Only re-inject after a compaction or an explicit resume.
case "$source_val" in
  compact|resume) ;;
  *) exit 0 ;;
esac

directive="🔁 CONTEXT WAS JUST COMPACTED/RESUMED (source=${source_val}). You are CONTINUING an in-flight session, not starting fresh.
- Re-orient from the HANDOFF baton below + your auto-memory, then CONTINUE the current task autonomously.
- Do NOT stop to ask the user to re-confirm the next step, and do NOT re-derive facts already established.
- ONLY pause if you hit a genuine external blocker (e.g. you are waiting on the user to run an MT5 test).
- Per CLAUDE.md: keep HANDOFF.md updated as you go. The current baton:"

if [[ -f "$handoff" ]]; then
  body="$(head -c 12000 "$handoff")"
else
  body="(HANDOFF.md not found at $handoff — reconstruct state from recent git log + the in-progress diff.)"
fi

# Emit the SessionStart additionalContext as JSON.
CTX="${directive}

${body}" python3 -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":os.environ["CTX"]}}))'
