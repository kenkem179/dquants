---
name: kenkem-repo-has-parallel-work
description: NEVER rm -rf or recreate dirs in the sibling kenkem repo — it has active parallel dev (Monster EA already exists)
metadata:
  type: feedback
  originSessionId: 5080b780-c6e1-43c1-b5c8-28268f43d81e
---

The sibling **kenkem** repo (`/Users/tokyotechies/Workspace/KEM/kenkem`) is under **active parallel
development** by the user / other codex sessions, often on feature branches (e.g. `KKMasterVPv1`) that
**diverge from the remote** (local can be behind by several R-series commits). It has MANY branches.

**2026-06-14 incident:** asked to "recreate MQL version of Monster", I assumed
`MQL5/Experts/KK-MasterVP-Monster/` didn't exist and ran `rm -rf` + copied a fresh tree from
KK-MasterVP. It **already existed** — the user's richer Monster EA (NetVolume.mqh, README.md, its own
InputParams/EntryVP, and on the remote 7 R-series hardening commits: StatePersistence, single-instance
guard, tick-staleness guard, embedded news calendar). I clobbered it. Recovered via `git reset --hard`
+ deleted a stray `refs/heads/HEAD` branch my mid-rebase push accidentally created.

**Why:** the EA work is theirs and ahead of what I can see locally; my dquants C++ engine is parity-
validated against KK-MasterVP, NOT necessarily their evolved Monster.

**How to apply:** before ANY write/delete in kenkem — (1) `ls` + `git ls-tree HEAD <path>` to check what
exists, (2) `git fetch` + compare `origin/<branch>` (remote is often ahead), (3) NEVER `rm -rf` a dir
there, (4) add files non-destructively, (5) `git push origin HEAD` not during a rebase. My value-add is
the optimized **param configs** from dquants — deliver those as `.set` files mapped to THEIR schema, don't
rewrite their code. See [[real-target-kenkem-strategies]] and [[workflow-commit-and-plan]].
