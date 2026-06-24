# KK-MasterVP — Multi-Timeframe (M5+M3) Confluence — FINDINGS (2026-06-24)

Spec: `MTF_CONFLUENCE_SPEC_2026-06-24.md`. Engine feature default-OFF (base byte-identical, golden parity
+ determinism tests green; MTF-off with the M5 overlay attached = byte-identical, verified empirically).
XAU only (engine = ranking proxy; BTC reversion feed-fictional). 6 disjoint folds (`slice_ticks_by_fold`),
every-tick, 10k/fold. Harness: `mtf_confluence_sweep_2026-06-24.py`.

## VERDICT (part 1): the MTF *confluence gate* is REJECTED. But see the FOLLOW-UP below — the
## broader idea ("act on M3, not M5") WINS via a different mechanism and produced a DSR-PASS candidate.
The user's instinct that "M5 is too late" shows up as a real **net** effect (pure-M3 has higher net), but
the multi-timeframe **confluence gate destroys it**, and the **DD/robustness cost of acting on M3 is not
recovered** by either the M5 gate or the M3 near-price early exit. Nothing in the *gate* family clears the
T1 rule (beat the champion on pooled result AND not degrade worst-fold PF). The gate/exit MTF engine
feature ships as tested default-OFF infra; NOT ported to MQL5.

> ⚠️ **UPDATED 2026-06-24 (follow-up):** the headline "keep M5-only" was reversed by the follow-up study
> below. Acting on M3 — when paired with the champion's *exits* (not a confluence gate) plus a peak-DD
> limiter — beats the M5 champion on every WF axis and PASSES the overfitting gate (DSR 0.995). It is a
> **candidate pending MT5 A/B**, not yet a lock. See `## FOLLOW-UP`.

## Arms (gate mode) — 6-fold pooled, vs the deployed M5 champion
| arm | n | win% | PF | net | maxDD | folds PF>1 | worstPF |
|---|---|---|---|---|---|---|---|
| **A M5 lock (champion)** | 1353 | 58.4 | **1.318** | 21,312 | **7.6%** | **6/6** | **1.094** |
| B M3 base (MTF off) | 1980 | 55.6 | 1.228 | **25,162** | 13.7% | 4/6 | 0.732 |
| C M3 + M5 confluence gate | 1594 | 55.5 | 1.179 | 14,944 | 11.1% | 3/6 | 0.858 |
| D C + M5-ATR SL | 1522 | 54.9 | 1.154 | 12,071 | 12.9% | 3/6 | 0.881 |
| E C+D + early-exit 0.25…0.55 | ~1524 | ~54.8 | 1.14–1.16 | 10.9k–12.3k | 12–14% | 3/6 | ~0.88 |

(Exit sweep was flat across the whole 25–55% band — best E was 0.55 at net 12,340 / PF 1.158, still
−8,972 net and −0.160 PF vs the champion. No threshold rescues it.)

## Why it fails (mechanism)
1. **The M5 value-area gate removes PROFITABLE M3 breakouts.** Requiring the M3 entry to also clear the
   wider M5 master VAH/VAL dropped ~20% of signals (raw 41.6k→32.2k on F4) and cut net from B's 25,162 to
   C's 14,944 (−41%). The filtered-out trades were net-positive: the fast M3 breakouts that have NOT yet
   cleared the slower 36–40h M5 value area are exactly the early entries the idea wanted to keep — gating
   them on M5 confirmation re-introduces the "too late" lag the user was trying to remove.
2. **M5-ATR SL (rule 2) hurts further** (D < C on PF and net): a wider higher-TF stop on an M3-cadence
   trade just sizes risk up without improving exits.
3. **The M3 near-price net early-exit (rule 3) is inert-to-negative** across 0.25–0.55 — cutting on
   opposite near-price flow clips winners more than it saves losers (same survivorship trap as the prior
   conviction-protect / FVG / VMC studies).

## The honest read of the user's instinct
- **Acting earlier (pure M3) genuinely makes more gross profit** (B net 25,162 > champion 21,312, +18%).
  So "M5 is too late" is not wrong on raw edge capture.
- **But it is much rougher**: maxDD 13.7% vs 7.6%, only 4/6 folds positive (F3 −$4,002, F6 −$530),
  worst-fold PF 0.732 vs 1.094. The M5 champion trades the extra net for a far smoother, every-fold-positive
  equity curve — which is what a prop/funded book needs.
- **MTF confluence was the proposed way to keep M3's net while adding M5's smoothness. It does the
  opposite**: it keeps the roughness (worstPF still 0.86–0.88, 3/6 losing folds) while throwing away the
  net. The two timeframes' value areas are not a clean confluence filter here.

## Exit-only isolation (rule 3 on the pure M3 base, no gate) — `--mode exitonly`
The M3 near-price net early-exit is **inert** on the pure M3 base across the entire 25–55% band:
net stays ~25,000–25,450 (B = 25,162), maxDD ~13.7–14.3% (B = 13.7%), and **worstPF = 0.732 is
unchanged at every threshold** — the killer fold F3 (−$4,002) is untouched (extreme opposite near-price
net ≥0.25–0.55 simply doesn't coincide with that fold's losing trades). Best = exit0.50: net 25,450,
+$4,137 vs champion but still PF 1.230 / dd 13.7% / worstPF 0.732 / 4-of-6 folds → **fails T1**
(worstPF 0.732 ≪ champion 1.094). So rule 3 neither adds net nor tames the drawdown.

| arm (exit-only) | PF | net | maxDD | folds PF>1 | worstPF | vs champ |
|---|---|---|---|---|---|---|
| B M3 base | 1.228 | 25,162 | 13.7% | 4/6 | 0.732 | net +3,850, worstPF FAIL |
| X exit 0.25 | 1.219 | 23,889 | 14.3% | 4/6 | 0.732 | FAIL |
| X exit 0.50 (best net) | 1.230 | 25,450 | 13.7% | 4/6 | 0.732 | net +4,137, worstPF FAIL |
| X exit 0.55 | 1.230 | 25,358 | 13.7% | 4/6 | 0.732 | FAIL |

## Overfitting gate
Not run as a lock test: **no variant cleared T1** (every MTF/exit arm degrades worst-fold PF vs the
champion), so there is no lock candidate to deflate. The gate (`research/stats/gate.py`) is reserved for
a config that first survives WF — none did here.

## Caveats / scope
- Engine over-credits trailed runners and the M3 base inherits the M3-lock exit (trail 2.0 / tp1 20),
  not the champion's (trail 2.5 / tp1 0). A fairer "M3-with-champion-exits" arm could shift B's absolute
  numbers, but the **gate's monotonic profit destruction** (C,D,E all below B) is the load-bearing result
  and is exit-config-independent.
- Not MT5-validated; not needed — nothing beat the champion, so there is no candidate to A/B.

## Decision
Keep `KK-MasterVP-XAUUSD-M5.set` (MT5 +62,732 / PF 1.402) unchanged. MTF-confluence engine params stay
default-OFF infra. Not ported to MQL5.

---

## FOLLOW-UP (2026-06-24) — "M3 with the champion's EXITS + a DD limiter" — the idea WINS
The gate study showed pure-M3 has more *net* but is rougher. The user approved testing whether M3 with the
**champion's exit config + a DD limiter** recovers the robustness *without* the gate. It does — decisively.

**Key realisation:** the MTF study's "B M3 base" used the OLD Pine-faithful M3 lock, which never received
the champion's later WF-locked improvements. The M5 champion's edge is not just "slower TF" — it carries
four post-baseline locks the M3 lock is missing: `InpTp1ClosePct 20→0` (T3 exit), `InpTrailAtrMult 2.0→2.5`,
`InpEnableReversion true` (T3), `InpBlockedHoursStr 2,3,14` (T2). Comparing M3-old-exits vs M5-new-exits was
never apples-to-apples.

### Stage 1 — port the champion's locks onto M3 (cumulative). Harness `m3_champ_exits_2026-06-24.py`
| arm | PF | net | maxDD | folds+ | worstPF | note |
|---|---|---|---|---|---|---|
| A M5 champion (ref) | 1.318 | 21,312 | 7.6% | 6/6 | 1.094 | bar to beat |
| B M3 lock as-is | 1.228 | 25,162 | 13.7% | 4/6 | 0.732 | old exits |
| C1 +tp1=0 | 1.285 | 33,225 | 13.8% | 4/6 | 0.748 | net +57% vs B (runner edge) |
| C2 +trail2.5 only | 1.207 | 22,168 | 16.4% | 4/6 | 0.722 | worse alone |
| C3 +champ exit (tp1=0 & trail2.5) | 1.257 | 28,854 | 14.0% | 5/6 | 0.738 | F6 flips + |
| C4 +reversion | 1.296 | 32,642 | 15.9% | 5/6 | 0.620 | net up, F3 deeper |
| **C5 +blocked-hours 2,3,14** | 1.283 | 30,602 | 11.2% | 5/6 | **0.955** | **T2 nearly fixes F3 (−4,002→−834)** |

The T2 hour-block (block lunch-lull + late-London chop) is what tames the killer fold F3 — exactly the
"act on M3 but skip the chop windows" idea, and it costs little net.

### Stage 2/3 — DD limiter on C5. Harnesses `m3_champ_c5dd_2026-06-24.py` (+ Stage-2 in `_exits_`)
A peak-to-trough **peak-DD limiter** (the one risk rule M3's rougher curve needs and the smooth M5 champion
doesn't) closes the last gap. Plateau: 15 & 18 both clear T1; 12 over-truncates (worstPF 0.552), 20 just
misses (1.074).
| arm | PF | net | maxDD | folds+ | worstPF | vs champ |
|---|---|---|---|---|---|---|
| C5 (no limiter) | 1.283 | 30,602 | 11.2% | 5/6 | 0.955 | net +9,290, worstPF FAIL |
| **C5 + peakDD=18** | **1.398** | **30,252** | **7.5%** | **6/6** | **1.106** | **KEEPER — beats on every axis** |
| C5 + peakDD=15 | 1.451 | 27,774 | 7.1% | 6/6 | 1.177 | KEEPER (max robustness) |
| C5 + peakDD=20 | 1.375 | 29,058 | 8.2% | 6/6 | 1.074 | near (worstPF just under) |
| C5 + peak15+daily5 | 1.421 | 26,999 | 7.2% | 6/6 | 1.166 | KEEPER |
| C5 + daily/lossStreak only | ~1.28 | ~30k | ~10% | 5/6 | 0.92–0.99 | not enough alone |

**Winner = C5 + peakDD=18:** PF **1.398** (vs 1.318), net **30,252 (+42%)**, maxDD **7.5% (= champion)**,
**6/6 folds**, worst-fold PF **1.106 (> champion 1.094)**. Beats the M5 champion on every WF axis.

### Overfitting gate — `m3_champ_gate_2026-06-24.py` + `research/stats/gate.py`
n_trials=22 (full M3-champ-exits search), sr_trial_std=0.01532 (std of per-trade Sharpe across the 11
Stage-3 arms). Pooled 6-fold winner stream (1332 trades):
- **DSR = 0.995 → PASS** (≥0.95), PSR-vs-0 = 1.000, MinTRL 241 vs 1332 trades → sample-sufficient.
The candidate survives multiple-testing deflation.

### Status & remaining gate
- **Candidate, NOT a lock.** Written to `cpp_core/tools/mastervp/kkmastervp_xau_m3_CHAMPEXITS_CANDIDATE.set`.
- The engine is a RANKING proxy that over-credits trailed runners; this config leans hard on runners
  (tp1=0 / trail2.5) and fires ~40% more trades than the M5 champion, so the +42% net is exactly where
  proxy inflation lives. **The MT5 A/B (vs the deployed M5 champion, recent OOS) is the one remaining gate
  before this can replace the lock.** Only a DSR-PASS *and* MT5-confirmed config gets promoted to
  `kkmastervp_xau_m3_LOCKED` / a kenkem Preset.

### Revised decision
The M5-only champion is no longer obviously #1 for XAU. The MTF *confluence gate* stays rejected, but the
user's core thesis ("M5 is too late") is vindicated: trade the M3 cadence, keep the champion's runner-exits,
block the chop hours, and cap peak drawdown. Pending MT5 confirmation, **C5+peakDD18 is the new lead XAU
candidate.**
