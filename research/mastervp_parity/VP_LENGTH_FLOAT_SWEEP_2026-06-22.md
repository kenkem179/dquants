# Float master-VP-multiple — 0.5-step sweep (2026-06-22)

`InpMasterMult` is now a **float**: `master_len = round(InpVpLookback × InpMasterMult)`. Wired through
C++ (`Params::master_mult` double, `master_len()` rounds), the EA (`Inputs.mqh`/`Engine.mqh`), and the
Profiler indicator. Integer multiples are byte-identical to before (`make test` 37/37 + golden parity
green); the float only adds *intermediate* lengths the old integer step skipped.

**Why it matters:** with `VpLookback=120`, an integer step moved the master VP by a full 120 bars
(360→480→600). 0.5 steps give half-`VpLookback` resolution (420/480/540), so we can see whether each
lock is on a true plateau interior or a lucky integer landing.

Sweep: `research/mastervp_parity/vp_length_float_sweep_2026-06-22.py` (train+OOS, plateau-pick).

## Results

### XAU-M3 — lock 4.0 (480b) CONFIRMED optimal, no float gain
| mult | master | TRAIN | OOS |
|---|---|---|---|
| 3.0 | 360 | PF 1.239 / +17729 / dd 18.1% | PF 1.202 / +4075 / dd 20.2% |
| 3.5 | 420 | PF 1.216 / +16879 / dd 26.0% | PF 1.175 / +3426 / dd 16.6% |
| **4.0** | **480** | **PF 1.264 / +21769 / dd 29.5%** | **PF 1.351 / +6263 / dd 11.7%  ⟵ LOCK** |
| 4.5 | 540 | PF 1.170 / +11955 / dd 40.0% | PF 1.215 / +3778 / dd 12.1% |
| 5.0 | 600 | PF 1.099 / +5423  / dd 24.2% | PF 1.211 / +4018 / dd 18.0% |

Lock 4.0 has the **best OOS PF AND the lowest OOS dd**; both neighboring half-steps (3.5, 4.5) are
worse on PF. The integer lock was not a lucky landing — it sits on a genuine local optimum. **No change.**

### XAU-M5 — lock 4.0 (432b) is the TRAIN optimum, but float reveals SHORTER generalizes better OOS
| mult | master | TRAIN | OOS |
|---|---|---|---|
| 3.0 | 324 | PF 1.181 / +11263 / dd 33.8% | PF 1.419 / +5062 / **dd 8.1%** |
| 3.5 | 378 | PF 1.164 / +8554  / dd 22.4% | **PF 1.506 / +6069 / dd 8.0%** |
| **4.0** | **432** | **PF 1.355 / +23155 / dd 15.1%** | PF 1.322 / +3470 / dd 12.3%  ⟵ LOCK |
| 4.5 | 486 | PF 1.300 / +18047 / dd 11.3% | PF 1.256 / +2916 / dd 13.3% |
| 5.5 | 594 | PF 1.280 / +14981 / dd 11.4% | **PF 1.565 / +6252 / dd 8.4%** |

⚠️ **Finding worth following up, NOT an immediate re-lock.** The 432b lock owns the TRAIN by a wide
margin (PF 1.355) and was chosen via the earlier WF+MC pass. But at finer granularity the **shorter
masters 3.0–3.5 (324–378b) generalize markedly better on the OOS window** (PF 1.42–1.51, dd ~8% vs the
lock's 12.3%) — exactly the train/OOS tension integer steps hid (you'd only have seen 3.0/4.0/5.0).
This is a single-OOS-window result, so per the repo's discipline it is a **walk-forward candidate**,
not a lock: the lock was MC-hardened at 432b and the shorter window could be regime-luck. → queue a
per-fold WF run of mult ∈ {3.0, 3.5, 4.0} for XAU-M5 before touching the lock.

### BTC-M5 — lock 30.0 (720b) fine; nearby steps within feed noise
`vplb=24` so each 1.0 step = 24 bars (already fine resolution). OOS is noisy across the range. Lock 30.0
(OOS PF 1.250 / dd 14.8%) is reasonable; 31.0 (744b) is marginally better OOS (PF 1.313 / +6563) but
worse dd and the BTC/Exness feed is historically MT5-over-optimistic — not a robust improvement. **No change.**

### BTC-M3 — structurally dead at EVERY float length
All multiples 2.0–8.0 are PF 0.73–0.92 with 65–90% drawdown on both windows. Confirms the prior verdict:
the BTC-M3 breakout has no edge at any master length. **No lock, as before.**

## Verdict
- Float `InpMasterMult` is shipped and validated (byte-identical at integers; finer probes elsewhere).
- XAU-M3, BTC-M5, BTC-M3: float granularity **confirms** the existing locks/verdicts; nothing to change.
- **XAU-M5: one real follow-up** — shorter master (mult 3.0–3.5) beats the lock OOS with lower dd; send
  it to per-fold walk-forward before any re-lock (single-window OOS spike, not yet trustworthy).
