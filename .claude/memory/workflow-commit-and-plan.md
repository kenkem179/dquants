---
name: workflow-commit-and-plan
description: Standing workflow — commit+push each completed step and keep the build plan updated
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

The user wants a tight, durable build cadence on the dquants repo (it has an `origin` remote
`github-kenkem:kenkem179/dquants.git`, branch `main`):

**After every completed build step:**
1. `make -C cpp_core test` (or the relevant tests) must be green.
2. `git add -A && git commit` with a clear message (end with the Co-Authored-By line).
3. `git push origin HEAD`.
4. Tick the step `[x]` in **`docs/BUILD-PLAN.md`** (the living plan/tracker) — never lose track of
   progress there.

**Why:** the user views this as low-risk foundation work ("nothing to lose") and wants every increment
safely pushed + progress visible in the plan file. Standing authorization to commit+push each step — no
need to re-ask.

**Context:** the user also asked me to "regularly run /compact." I CANNOT invoke `/compact` myself — it
is a built-in Claude Code CLI command only the user can trigger. Best I can do: keep outputs lean, and
flag good moments to compact (right after a clean commit+push, since BUILD-PLAN.md + git + memory then
hold all state needed to resume losslessly). See [[real-target-kenkem-strategies]].
