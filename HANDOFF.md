# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 29 C++ checks PASS.
Latest: entry-count gap ROOT-CAUSED to forming-bar ATR (diagnosis only, no code change)._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — TP PARITY FIXED (commit `1ba5157`); tag-agree 66%→**81%**, |Δpnl| med 114→**4.6**
The matched-pair TP was systematically ~0.3–0.4 too CLOSE, firing TP where MT5 trails out for a smaller
SL-WIN. Traced to the canonical EA's `setMaxTPForTrade` → `finalRR = entry.GetRewardRatio() *
GetDynamicRRMultiplier()`. Two faithful fixes:
1. **Short-RR factor was a misattribution.** `GetRewardRatio()` returns ONE per-entry
   `m_config.rewardRatio` applied identically long/short — there is NO long/short split. The engine's
   `KK_E1/E2/E4_SHORT_FACTOR` (0.875/0.867) made every short's TP ~12–14% too close. Set to **1.0**.
2. **`GetDynamicRRMultiplier` un-ported** (SessionManager.mqh:93): `rrRatio *=` session×ATR-pctile scaler
   (ASIA 0.95 / US 1.15 / EU 1.0; ATR pctile ≥75→1.12, ≤25→0.88; clamp [0.70,1.30]).
   `USE_DYNAMIC_RR_SCALING=true`; `ENABLE_ADAPTIVE_E*` all **false** → `GetRewardRatio()` stays static, so
   this multiplier is the ONLY unmodeled RR term. Added `kk_dynamic_rr_mult` + `kk_session_id` in
   entries.hpp, threaded into `compute_tp`.

### Result (FULL 2yr E1 anchor, `KK_E1_FAITHFUL=1`) — see Repro below
- matched exit-tag agreement **66%→81%**; per-trade |ΔpnlUSD| median **114.23→4.56**.
- over-trail (MT5 SL-WIN→eng TP) **5→2**; **SL-LOSS 11/11 exact**; SL-WIN 10→13/15; TP 9→10/12.
- matched net engine **+639** vs MT5 **+990** (gap now in a few outliers + the 31 missed entries).

## 🟢 DATA BLOCKER — APPARENTLY RESOLVED (verify with user)
`cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` on disk now give
**849,963 bars / 162,761,235 ticks** — i.e. the COMPLETE source (matches the proven-exact 848,532 /
162,657,649, [[tick-source-parity-proven-exact]]), NOT the 577k holes-affected regen the prior handoff
feared. All this session's numbers use the complete data. **Confirm with the user** whether they
restored the full Exness export (or it was never actually deleted) before trusting absolute counts.

## 🔬 THIS SESSION (2026-06-19, no code change — DIAGNOSIS) — entry-count gap ROOT-CAUSED
Decomposed the **62 E1 over-fires** with direct evidence (gate-trace + tester.log block reasons + pctile
oracle). **This OVERTURNS the "84% spurious cross-arming" memory** ([[kenkem-e1-overfire-trendcore]]) — that
came only from `kke1gate.csv`, which is blind to the ATR-limiter layer. True breakdown:
- **~15 = ATR-percentile divergence.** `--pctile-oracle` (feed MT5's exact per-bar pctile from
  `trace.csv.gz` col 33) drops overfire **62→47** (matched 47→44, missed 31→34 — a pctile *timing* residual).
  These are MT5 `[ATR HIGH/LOW/VOL REGIME BLOCK]` → `SKIPPED: High-risk blocked by risk limits` (440 total).
- **14 = `mtf` gate** (engine PASSes where MT5 blocks at `isAllTimeframeEMAsReadyForEntry`). Oracle-invariant.
  Engine mtf composition (entries.hpp:184-197) is structurally faithful → EMA-value boundary rounding flips.
- **~6 = truly spurious arm.** So spurious arming is ~10%, not 84%.

**ROOT CAUSE of the ATR-pctile divergence = forming-bar ATR `s.atrM1` (snapshot.hpp:173) is WRONG.** Engine
`trace_dumper` `atr_pctile` vs MT5 col 33 over 848,532 bars: **exact only 31.6%, median |Δ| 6.25 (=2/32),
block-category differs on 29%.** The pctile method is faithful; the *input* forming ATR is **median 6.5%
relative off, 0% exact**. Closed-bar ATR is fine (SL risk-ratio locked 1.000) — only the forming step is off.
Tested ALL bar-OHLC ATR variants vs MT5 → engine's `|open−prevC|` is closest but 0% exact, mixed-sign error.
**MT5's iATR(0) reflects the forming bar's intra-bar H/L at the cache-read tick → irreducible from bar OHLC.**
Also confirmed `ENABLE_LOSS_COOLDOWNS=true` changes **0 trades** (inert). Full detail: [[kenkem-e1-overfire-is-forming-atr]].

## ▶️ NEXT ACTIONS (in order)
1. **Decide on the forming-ATR fix (biggest single lever, but weigh payoff).** The only faithful fix is
   tick-level: track the forming bar's running H/L in the tick engine and compute `atrM1` at the cache-read
   tick, instead of the bar-frozen `(atr_closed*13+|open−prevC|)/14` in snapshot.hpp:173. ⚠️ Payoff is
   mixed — the oracle (perfect pctile) only nets overfire −15 / matched −3, and `atrM1` feeds sideways +
   trend-scoring too, so regression risk is real. Validate every step with diff_kk + matched_exit_crosstab.
   **Clue:** MT5's implied forming-TR tracks the FULL-bar TR (median Δ≈−0.01), not first-tick `|open−prevC|`
   (Δ≈+0.80) → MT5 iATR(0) uses accumulated range (buffer lag), not bar-frozen first-tick. First verify the
   engine's CLOSED-bar ATR vs MT5 iATR shift-1 (a direct full-TR test was slightly worse, so the base may
   also drift). Detail: [[kenkem-e1-overfire-is-forming-atr]].
2. **`mtf` gate EMA-boundary leak (14 overfire).** Add per-bar m1_ready/m3_ready/m5_dir/extreme + M1 DI±
   to both engine `EGATE` and EA `KKE1GATE,mtf` detail, diff at the 14 leak bars to see which sub-check
   flips. Likely EMA-alignment rounding at `emas_ready_entry` (align−3 shift) or the DI≥16 bypass edge.
3. **2 remaining over-trail SHORTS** (2024-11-11, 2025-02-12); `tpExt` still 0. Lowest priority.
4. After E1 net+counts converge, repeat for E2/E4/E5.

## 🔁 Repro (full 2yr, ~30s)
```
cd cpp_core && make test                        # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
# diagnostics: prefix KK_TRADE_DIAG=1 and/or KK_ENTRY_DIAG=1 (2>/tmp/diag.txt)

# --- ATR-pctile root-cause diagnostics (this session) ---
# 1) oracle A/B: feed MT5's exact per-bar pctile, expect overfire 62->47
D=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace
gzcat $D/trace.csv.gz | awk -F, 'NR>1{print $1","$33}' > /tmp/pctile_oracle.csv
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 \
  --set research/kenkem_parity/anchor_E1_only_trace.set --pctile-oracle /tmp/pctile_oracle.csv --out /tmp/e_oracle.csv
# 2) per-bar pctile divergence: engine trace_dumper col atr_pctile vs MT5 col 33
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --set research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/eng_trace.csv
# (then compare /tmp/eng_trace.csv[atr_pctile] vs $D/trace.csv.gz col33 -> 31.6% exact, 29% wrong category)
```
Current (complete data): matched 47 / missed 31 / overfire 62; |Δrisk| 0.081; |ΔpnlUSD| median **4.56**;
matched tag-agree **81%**; matched net engine **+639** vs mt5 **+990**.

## 📦 Data / instruments
- Full 2yr XAU: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` —
  REGENERATED this session from `data/xauusd/` symlinked raws; **incomplete** (577,738 bars). gitignored.
- **MT5 ref run (committed)** at `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`:
  `trades.csv` (78, the diff target) · `kke1gate.csv` · `tester.log.gz` (input echo + mechanism counts +
  `TRAILING SL` lines) · `trace.csv.gz` (gunzip before use). EA=canonical KenKemExpert, XAU 2024.01→2026.06.
  **Input echo confirms MY_STANDARD_LOT_SIZE=100, COMMON_MAX_RISK_PER_TRADE=0.01, leverage 1:500.**
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `TradeManagement/TradeManager.mqh`,
  `Config/InputParams.mqh`). dquants `mql5/experts/KenKem/` is the THIN KK-rewrite — NOT this EA.

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity
is ground truth. See [[goal-pip-to-atr-relative]].
