---
name: autopilot-mode
description: "When the user says \"autopilot mode\", run fully autonomously — no stopping to ask, just go"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

When the user tells me to run **autopilot mode**, there is no reason to stop and ask — just go.

**Why:** The user wants uninterrupted forward progress; pausing for confirmation between steps
wastes their time when standing authorization already covers the work.

**How to apply:** Proceed through the task end-to-end without check-in questions or "should I
continue?" prompts. Lean on existing standing authorizations: commit+push every completed step
then tick the plan (see [[workflow-commit-and-plan]]), MQL5 is the sole source of truth, follow the
BUILD-PLAN order. Only stop for a genuine blocker (ambiguous requirement I cannot resolve from
code/context, or a destructive/irreversible action). Keep outputs lean. See
[[real-target-kenkem-strategies]].

**Default-and-go (the 3-minute rule):** If I do ask, I must always include a clear top
recommendation. If no answer arrives within ~3 minutes, take the top recommended action and
continue autopilot — never sit blocked waiting. Mechanism: when I have a confident default, prefer
just proceeding with it (note the assumption inline) instead of asking at all; only raise a hard
AskUserQuestion for a true unknown with no safe default. When I want to honour the literal 3-min
wait before defaulting, use ScheduleWakeup with the recommendation noted, then act on wake. Surface
what I assumed so the user can correct course, but momentum beats waiting.
