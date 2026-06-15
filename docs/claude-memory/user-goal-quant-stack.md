---
name: user-goal-quant-stack
description: What the user wants from the dquants quant stack and how they want to work
metadata: 
  node_type: memory
  type: user
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

The user wants a complete quant trading stack to: (1) analyze/visualize tick data for research, (2) run
backtests **super fast without relying on the MT5 Strategy Tester**, and (3) seamlessly convert
validated strategies into a final MT5 Expert Advisor.

Hard constraint they stated: research/strategy logic lives in Python + C++; **MQL5 is only the final
execution language**, and the MT5 Strategy Tester is a final sanity check only — never the research
environment. They believe C++ → MQL5 conversion is ~1:1 (true for pure signal/SL/TP functions, not for
MT5 API calls). They use Claude=Research Manager, Codex=Implementation, Gemini=Reviewer.

Machine: MacBook Pro M5 (Apple Silicon, arm64) — native arm64 tooling matters. See
[[project-kenkem-quant-os]].
