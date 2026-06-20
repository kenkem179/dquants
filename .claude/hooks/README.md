# .claude/hooks — repo automation

## autopilot-compact-continue.sh  (SessionStart hook)

**Goal:** let an autonomous ("autopilot") run survive context compaction and keep going
without the user.

### What's actually possible (Claude Code v2.1.x)
- ❌ You **cannot** auto-run `/compact` at a custom context % (e.g. 30%). There is no
  context-size hook event, the auto-compact threshold is fixed by the harness, and hooks
  cannot invoke slash commands. (Tracked upstream: anthropics/claude-code#25689.)
- ✅ You **can** rely on the built-in **auto-compact** (`autoCompactEnabled`, default `true`,
  pinned in `.claude/settings.json`). It compacts near the limit and **continues the turn
  automatically** — that already is "compact, then continue without me."
- ✅ You **can** harden the *continuity* across that compaction — which is what this hook does.

### What the hook does
Fires on `SessionStart`. When the session resumed **from a compaction** (`source=compact`) or
an explicit `--resume`, it re-injects the `HANDOFF.md` baton plus a "continue autonomously"
directive as `additionalContext`, so the agent re-orients and keeps working instead of stalling
or re-asking. It re-fires on every subsequent compaction (self-renewing). On a fresh
`startup`/`clear` it stays silent.

### Activation notes
- Defined in the repo's `.claude/settings.json`; Claude Code will ask you to **approve the new
  hook** the first time, and it takes effect on the **next session start** (not the current one).
- Merges additively with any global `~/.claude/settings.json` SessionStart hooks (both run).
- Keep `HANDOFF.md` current — the hook is only as good as the baton it re-injects (the repo's
  CLAUDE.md already mandates this).

### Manual lever
If you want to compact *earlier* than the harness would (the "30%" intent), just run `/compact`
yourself when the status line shows context getting low — this hook handles the continuity either
way (manual or automatic compaction).
