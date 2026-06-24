# KK-MasterVP — Multi-Timeframe (M5+M3) Confluence — HYPOTHESIS / SPEC (2026-06-24)

## 0. User idea (verbatim intent)
> "Waiting for M5 only is too late to decide entry timing. Multi-timeframe confluence will be nicer."

Four concrete rules:
0. **Main chart M5; the breakout/mean-reversion *context* is the M5 master-VP value area.** Breakout is
   "ready to snipe" only when price is beyond the M5 master value area (above mVAH / below mVAL). Do NOT
   wait for the M5 candle to close — use the **M3 candle close** as the trigger (earlier timing).
1. **M3 candle close** supplies: net-volume confirmation, the (M3) master-VP trigger level, and the
   ATR-based entry point.
2. **M5** supplies the structure / ATR-based **SL** (wider, higher-TF stop).
3. **Early exit on M3** when *extreme opposite near-price net volume* appears. Sweep the net-volume
   threshold **25%–55%** (the user doesn't know the right cut).

## 1. Engine realization (why main = M3)
The C++ TickEngine drives bar-close detection off ONE bar series. To get "act on the M3 close, gated by
M5", the faithful realization is:
- **Main series `bars_` = M3** → detection/entry cadence is M3 (earlier than M5). This is rule 0's
  "just use candle close on M3" + rule 1's M3 trigger/net/ATR-entry.
- **M5 overlay** (new `--bars-m5`) → per-M3-bar M5 master VP (mVAH/mVAL/mPOC) + M5 ATR. Supplies the
  rule-0 confluence gate and the rule-2 SL ATR.
- **M3 near-price net** (tick-net fraction in [-1,1]) → rule-3 early exit.

"Main chart M5" is a presentation detail; what matters economically is trigger-cadence = M3 and
context = M5. The benchmark is the deployed **M5-only lock** (`KK-MasterVP-XAUUSD-M5.set`, MT5 +62,732 /
PF 1.402) run the normal way (main = M5).

## 2. New params (ALL default-OFF / inert → base byte-identical; golden parity must stay green)
| key | default | meaning |
|---|---|---|
| `InpEnableMtfConfluence` | false | master switch: M5 value-area confluence gate + (opt) M5-ATR SL |
| `InpMtfHtfSeconds` | 300 | overlay TF seconds (M5) — VP-window + ATR + bar mapping |
| `InpMtfGateBufAtr` | 0.0 | breakout: require M3 entry beyond the M5 edge by buf×M5ATR (0 = just beyond) |
| `InpMtfSlFromHtf` | true | within MTF: SL ATR term uses **M5** ATR instead of M3 ATR (rule 2) |
| `InpMtfRevTouchAtr` | 0.5 | reversion confluence: M3 entry within touch×M5ATR of the M5 edge it fades |
| `InpEnableMtfExit` | false | rule-3 early exit on M3 near-price opposite net volume |
| `InpMtfExitNetMin` | 0.40 | **THE sweep param**: \|M3 near-price net\| against the trade ≥ this → close |
| `InpMtfExitArmR` | 0.0 | only arm the early exit after MFE ≥ this R (0 = always armed) |

`detect_signal` gains a trailing `double atr_sl = -1.0` (−1 ⇒ use M3 atr1 ⇒ byte-identical); when MTF +
`sl_from_htf`, the engine passes the M5 ATR so only the SL distance uses M5 (buffers/diagnostics stay M3).

## 3. Confluence gate (engine-side, after detect_signal, before counting the signal)
For each valid M3 signal at bar i, look up the last fully-closed M5 bar j (close_time ≤ M3 close) and its
M5 master VP over `master_len()` M5 bars:
- **breakout long**: entry_close > m5VAH + buf · **short**: entry_close < m5VAL − buf
- **reversion long**: entry_close ≤ m5VAL + touch · **short**: entry_close ≥ m5VAH − touch

Fail ⇒ the M3 signal is dropped (no trade, not counted as a raw signal). No-lookahead: M5 bar j is fully
closed at decision time.

## 4. Early exit (rule 3)
M3 near-price net = `tf_net_near_at` over the M3 main series (look=`InpTfNetLook`, win=`InpTfNetWinAtr`),
a signed fraction in [-1,1]. On each closed M3 bar while a position is open and MFE ≥ arm_r: if net is
AGAINST the trade with magnitude ≥ `mtf_exit_net_min`, force-close. Sweep `mtf_exit_net_min` ∈ {0.25 … 0.55}.

## 5. Test plan (SOP 6→8)
- **Build/parity**: `make test` (golden parity must stay green = base byte-identical with MTF off).
- **Data**: main = `bars_xauusd_2025_2026_m3.csv`; overlay = `..._m5.csv`; M1 = `..._2024_2026_m1.csv`
  (impulse stays off). 6 disjoint folds (`slice_ticks_by_fold.FOLDS`); slice `ticks_xau_full.csv` once.
- **Sweep** (`mtf_confluence_sweep_2026-06-24.py`): 
  1. Benchmark = M5-only lock (main=M5).
  2. M3-only base (main=M3, MTF off) — isolates "is M3 alone just noisier M5?".
  3. + confluence gate (M5 value-area) ± `MtfSlFromHtf`.
  4. + early exit sweep `MtfExitNetMin` ∈ {0.25,0.30,0.35,0.40,0.45,0.50,0.55} (± armR).
- **Decision rule (T1)**: adopt a variant only if it improves the POOLED result AND does not degrade the
  worst-fold PF vs the M5-only lock. Then run the **overfitting gate** (`research/stats/gate.py`,
  n_trials + sr_trial_std). DSR ≥ 0.95 PASS / 0.90–0.95 WARN / <0.90 FAIL.
- **Honesty caveats**: engine exit-model over-credits trailed runners ([[mastervp-profit-lock-ladder]])
  and BTC reversion is feed-fictional ([[mastervp-t3-reversion-lock]]) → XAU only; engine = RANKING proxy,
  any keeper needs MT5 A/B before a lock. NOT ported to MQL5 unless it wins WF + gate.

## 6. Verdict slot
_(filled at conclusion in MTF_CONFLUENCE_FINDINGS_2026-06-24.md)_
