# C1 — Dead-default-feature audit (read-only, 2026-06-26 autopilot)

Audit only — **no code was deleted.** Deletion is a supervised, one-feature-per-commit job with the
golden-parity + `make -C cpp_core test` safety net (a byte-diff after removing a feature = it wasn't dead).
This note records which default-OFF features are OFF/inert across the deployed MasterVP locks so the next
session can kill the clean ones fast.

## Toggle state across the deployed locks

| Feature toggle | XAU-M5 (lock) | BTC-M5 | XAU-M3 BASE | XAU (default) | Verdict |
|---|---|---|---|---|---|
| `InpEnableReversion` | **true** | false | false | false | **ACTIVE in XAU-M5 lock — do NOT remove** |
| `InpEnableImpulse` | absent(=false) | absent | absent | absent | DEAD everywhere → kill candidate (retired Monster delta) |
| `InpEnableExtremeReversion` | false | absent | false | absent | DEAD → kill candidate (XRev) |
| `InpNodeGateEnabled` | false | false | false | false | DEAD → kill candidate (node-engine gate) |
| `InpBrkRequireFlow` | false | false | false | false | DEAD → kill candidate (node gate) |
| `InpUsePriorBarVP` | false | false | false | false | DEAD → kill candidate |
| `InpUseMtfAgree` | false | false | false | false | DEAD → kill candidate (MTF gate) |
| `InpUseMomVeto` | false | false | false | false | DEAD → kill candidate (RSI momentum veto) |
| `InpRevTpMpoc` / `InpXRevTpMpoc` | false | absent | false | absent | DEAD → fold into reversion/XRev removal |
| `InpTrailBrk/Rev/Imp/XRev` | -1 | absent | -1 | absent | INERT (-1=inherit) everywhere → kill candidate |
| `InpMinAtrPct` / `InpMaxAtrPct` | 0.0 | 0.0 | 0.0 | 0.0 | OFF — but **KEEP** (CLAUDE.md: ATR-regime filter is a profitability lever, sweep don't delete) |
| `InpBreakMaxAtr` | 1e6 (no cap) | 1e6 | 1e6 | 1e6 | anti-chase OFF everywhere; single param, low-value to remove |

## Clean kill candidates (OFF in EVERY deployed lock; remove one-per-commit, golden-parity must stay byte-identical)
1. **Impulse-thrust path** — `InpEnableImpulse` + all `InpImpulse*` / `InpTfNet*` + `NetVolume.mqh`
   (MasterVP) and `kk/mastervp` impulse + `kk::detect_impulse` (C++). The retired Monster delta.
2. **Extreme Reversion (XRev)** — `InpEnableExtremeReversion` + `InpXRev*` + `ExtremeReversion.mqh` + engine mirror.
3. **Node-engine gate** — `InpNodeGateEnabled` / `InpBrkRequireFlow` / `InpSfpFlowMin` / `InpUsePriorBarVP`
   (+ node decay/neutral/saturation if only the gate consumed them — verify).
4. **Quality gates** — `InpUseMtfAgree` / `InpMtfHardVeto` / `InpUseMomVeto` / `InpRsiMidline` (MTF + RSI veto).
5. **Per-entry trail overrides** — `InpTrailBrk/Rev/Imp/XRev` (always -1 = inherit).
6. **FVG-SL** — `cpp_core/include/kk/mastervp/fvg_sl.hpp` (engine-only, WF-rejected, never ported to MQL).

## Do NOT remove
- **Reversion** (`InpEnableReversion` + `InpRev*` / `InpRetestAtr` / `InpBodyPctMin`) — ON in the XAU-M5 lock.
- **ATR band** (`InpMinAtrPct` / `InpMaxAtrPct`) — doctrine: profitability lever, keep & sweep.
- Note: removing the impulse path (#1) also removes the only consumer of the high-vol band that impulse
  fires *above* — verify the ATR band itself stays intact for breakout/reversion when impulse is cut.

## ⚠️ Process reminder for the deletion session
- One feature per commit. After each: `make -C cpp_core test` green AND the locked `.set` golden-parity run
  byte-identical. Mirror the C++ removal in the EA, recompile 0/0.
- The new `KK_IN` macro means several of these are now `KK_IN`-prefixed in `Inputs.mqh` — delete the whole
  declaration, not just the prefix.
- Keep the research write-ups in `research/` + memory (the lesson), drop only the code.
