# MasterVP — What To Do (and Not Do), Given the Engine Over-Credits Exits

Last updated: 2026-06-29. Audience: operator + any future agent. This is the standing rule-set for MasterVP
work. It exists because the C++ engine books MasterVP exits **~30% richer than MT5** (see
`EXIT_MODEL_CALIBRATION.md`, R6). Read this before touching anything MasterVP.

---

## 0. First, the thing you actually asked: is the 9X real?

**Yes. Your ~9X-on-1%-risk result is real, not engine fantasy — because it came from MT5, not the engine.**

- The locked config (XAU M5, ProgTrail late-arm ladder) was measured on the **MT5 Strategy Tester, every-tick,
  real ticks**: $10,000 → **$86,034 net, PF 1.4246**, over **2025.06 → 2026.05** (one year), risk ~1%/trade
  compounding. That's **~8.6X**. The engine was *not* the judge here; MT5 was.
- The engine over-credit problem is about **ranking the *next* change**, not about invalidating a result that
  already passed MT5. The lock cleared the overfitting gate too (DSR 1.000, PSR 1.000).

So: **the lock is trustworthy and frozen.** The rest of this doc is about how we add to it *without* fooling
ourselves with the engine.

### Two honesty caveats on the 9X (so live matches backtest)
1. **Drawdown:** that ~8.6X came with a **true full-year peak drawdown ≈ 27.7%**. At 1%/trade you should be
   sized to survive a **30–40% peak**. The growth is real; so is the DD. Don't up-size on the strength of the
   net without respecting the DD.
2. **Deployment trap — verify before you trust a live run.** The ProgTrail params (`InpPmProgTrail`,
   `InpPmProgTriggerR=2.0`, `InpPmProgIncrementR=0.75`, `InpPmProgStepR=0.2`) are **hidden globals** in the
   production `KK-MasterVP.ex5` — a `.set` file **cannot** drive them; only the Debug EA reads them. The 9X was
   produced on **KK-MasterVP-Debug**. For the *production* EA to reproduce it, those four values must be **baked
   as compiled defaults in `Inputs.mqh` and recompiled**. If they aren't baked, the production EA runs a
   *different* (non-ladder) strategy and your live result will diverge from the 9X. **Action: confirm the
   production EA has the ladder baked (one production-EA full-run should reproduce ~86,034 / 1.4246).**

---

## 1. The core constraint, in one sentence

On matched same-entry trades the engine is **+24% to +37% richer** than MT5, concentrated in the
**runner/TP fat tail** (27–32% over-credit), and its exit-*ranking* can **flip sign** (it once ranked trail-3.5
a +24% winner; MT5 said −24%). Therefore:

> **The engine may NOT decide any MasterVP exit question. Exit geometry is MT5-only.**

## 2. Hard rules — DO NOT

- ❌ **Do not lock, or believe, any MasterVP exit change based on a C++ engine number.** Trail width, RR target,
  SL distance, BE buffer, partial/laddered TP, giveback stops — all exit geometry. Engine ranking here is
  documented to invert in sign.
- ❌ **Do not re-run the giveback-stop / flow-exit / reversion-fade / TP1-partial families hoping for a
  different answer.** All four were taken to MT5 and **rejected** (giveback collapsed net ~92% AND raised maxDD;
  TP1-partial optimum is 0%). They are closed unless conditioned on a regime label (see §4).
- ❌ **Do not touch the locked `.set` or the baked defaults** to "try something." The lock stays byte-identical.
- ❌ **Do not size above the drawdown-capped fraction.** Empirical Kelly on the realized R-distribution, not the
  Gaussian shortcut; given the fat tail, never above quarter-Kelly.

## 3. What the engine MAY still do for MasterVP

- ✅ **Entry / signal-side changes** — the engine's signal logic is **exact parity** with MT5 (validated). So
  any *entry* idea (new filter, VP-location condition, session/hour block, entry-flow veto) can be ranked on the
  engine first, then MT5-confirmed. Exits cannot.
- ✅ **Generate leads** for exits — but a lead is not a lock. Any engine exit "win" gets the haircut
  (runner P&L −30%, winner gross −15%, same-entry net edge −30%) and must clear MT5 before it counts. Engine
  exit gains **≤ +0.015 PF (≈10% net) are noise**, full stop.

## 4. The ONE open exit lever — regime-conditioned exit (MT5-gated)

Every MasterVP exit experiment so far tested a stop/giveback against **momentum breakouts**, where a giveback
stop is the wrong tool (you stand in front of the freight train). The untested idea:

- Label each trade's regime with the **OU half-life** (`research/stats/half_life.py`, per-quarter): short
  half-life + significantly-negative β = **mean-reverting** regime; insignificant/positive β = **trending**.
- Apply a **time-stop / mean-target only in the reversion regime**, and let runners run only in the trending
  regime. This is the one reframe that the four rejections did *not* cover.
- **Still MT5-gated.** Build it default-OFF, rank candidates on MT5 (not engine), gate (DSR/PSR/MinTRL),
  per-quarter. If it doesn't beat the lock on MT5, it dies.

This is a *research lead*, not a promise. MasterVP's exit search is largely exhausted; this is the last
untested seam, not a rich vein.

---

## 5. The exactly-one MT5 run I need from you (calibration, not a code change)

This **validates the haircut**, it does not change any EA. It closes R6 and tells us the *full-year* over-credit
(today's 30% is a 2026-OOS-half lower bound).

> **EA:** `KK-MasterVP` (production) — or `KK-MasterVP-Debug` if you want the ladder echoed in the log
> **Symbol:** `XAUUSD`
> **Timeframe:** `M5`
> **Model:** Every tick based on real ticks
> **Date range:** `2025.06.01` → `2026.05.29`
> **Deposit:** `10000`, risk per current lock
> **Preset:** the current lock `.set` (`KK-MasterVP-XAUUSD-M5.set`, ProgTrail baked)
> **Toggle:** `InpExportParity = true`  ← this is the one that matters; it drops `trades_*.csv`

When it's done I auto-collect the `trades_*.csv` from `Tester/Agent-127.0.0.1-3000/`, run the engine on the
matched full-window tick file, and re-run `exit_model_calibration.py` to replace the inferred full-year haircut
with a measured one. **Nothing about your lock changes** — this only sharpens how much we discount *future*
engine exit claims.

## 6. One-line bottom line

Your 9X is real (MT5-proven) and frozen; the engine over-credits exits ~30% so it may never pick a MasterVP
exit change again — exits are MT5-only, the four giveback families stay closed, the single open lever is a
regime-conditioned exit (still MT5-gated), and the one run I want from you is a full-window `InpExportParity`
export that calibrates the haircut without touching a thing.
