# R6 — MasterVP Exit-Model Calibration Audit (2026-06-29)

**Goal (BUILD-PLAN R6, Operating Doctrine #1 "MT5 is the final judge of exits"):** put NUMBERS on where the
C++ tick engine disagrees with MT5 on MasterVP **exits** (runner credit, trail path, BE/prog-trail
sequencing, same-bar hit ambiguity, fill price, tick-delay), and produce a **haircut policy** so engine
exit-side wins can be discounted honestly.

**Verdict: PARTIAL-PASS.** The gap is now *measured* (not just asserted) on two post-TP-fix XAU M5
trade-level parity runs, and a usable haircut policy is derived. It is **partial** because both measured
datasets cover only the **2026.01–2026.06 OOS half** (~470 matched trades each); the full window
(2025.06–2026.05, incl. the Aug-2025 stress month and the big 2025 runners) has **no fresh per-trade MT5
export** — so the headline haircuts are a **lower bound** for the full year. See §4 for the exact export
that would replace each inferred number.

Repro: `conda run -n kenkem python research/mastervp_parity/exit_model_calibration.py`
(reads the two `mt5_runs/RUN_2026-06-20_*` folders that ship BOTH a MT5 trade CSV and a matched-window
engine trade CSV; matches by `(entryTimeUTC, dir)` + entry-price tolerance, decomposes the realized-USD
gap by exit tag and winner/loser).

---

## 1. Every documented engine-vs-MT5 MasterVP comparison (XAU M5 lock family)

| # | Config / run | Engine net (PF) | MT5 net (PF) | Δ net | Sign-agree? | Source |
|---|---|---|---|---|---|---|
| C1 | Lock OOS, **pre** TP-port-bug fix (capped 1.8R) | +10,335 (1.316) | +2,027 (1.071) | **+409%** | yes (both +) but huge mag gap | `RUN_2026-06-20_xau_m5_parity` |
| C2 | Lock OOS, **post** TP fix, 0-spread (logic parity) | +10,335 (1.316) | +10,091 (1.304) | +2.4% (full) / **+24.1% matched** | yes | `RUN_..._parity_v2_tpfix` |
| C3 | Lock OOS, post fix, +0.17 spread (cost-matched) | +9,077 (≈1.28) | +10,091 (1.304) | −10.0% (full) / **+25.4% matched** | yes | `RUN_..._parity_v2_tpfix` |
| C4 | Lock+hour-block OOS, 0-spread | +13,929 (1.370) | +11,789 (1.366) | +18.1% (full) / **+37.0% matched** | yes | `RUN_..._xau_m5_T2_hourblock` |
| C5 | Lock+hour-block OOS, +0.17 spread | +12,867 | +11,789 (1.366) | +9.1% (full) / **+36.6% matched** | yes | `RUN_..._xau_m5_T2_hourblock` |
| C6 | **Trail 2.5 (lock) vs 3.5** A/B, full window | engine WF: 3.5 **wins** +24% (gate-PASS) | 2.5=+62,732 ; **3.5=+47,791 (−24%)** | **SIGN FLIP** | **NO — engine RANKING inverted** | `mt5_runs/2026-06-23_xau_m5_trail35_AB` |
| C7 | RR×BeBuf 105-pass exit sweep, full window | (engine not the judge) | max RR5/BB0.03=81,770 (1.410); lock #2 | n/a | MT5-only optimization | `..._exit_sweep_RRxBB` |
| C8 | RR4.0/T2.75 final lock vs alts | (found on MT5, not engine) | 83,227 flat (1.413) / 87,836 comp | n/a | MT5 fine-opt chose it | `..._RR4_T2.75_confirm` |
| C9 | H9 ProgTrail late-arm ladder (the locked exit win) | engine flat: 86,034 (1.4246) vs lock 83,227 (1.413) = **+3.4% / +0.012 PF** | MT5 comp 1.4246 vs 1.4127 (+0.0118) | yes — **MT5-confirmed** | `H9_results/FINDINGS.md` |
| C10 | H10c session-giveback stop | (engine inert/OFF=lock) | OFF wins every axis; ON collapses net ~92% | yes | `H10c_results/FINDINGS.md` |

**Read of the table.** Whenever entries are held fixed and we compare the *same* trades (matched-pair, rows
C2–C5), the engine is **+24% to +37% richer** than MT5 — the full-sample Δ (+2.4% to +18%) only looks small
because unmatched engine-only trades (which happen to be net-losing here) cancel part of the over-credit.
That cancellation is **luck, not reliability** (parity_v2 nets to +2.4%, T2 to +18% on the same logic). And
row **C6 is the smoking gun**: the engine's 6-fold WF ranked a wider trail (3.5) as a clean +24% gate-PASS
winner; MT5 returned the **exact opposite, −24%**. Engine exit *ranking* can invert in sign, not just
magnitude.

---

## 2. Where the gap comes from (decomposition)

All figures from `exit_model_calibration.py` on the matched pairs. **[E]=evidence (measured), [I]=inference.**

### 2a. Runner / trailed-winner over-credit — the dominant term  **[E]**
Per-matched-trade realized-USD, engine minus MT5, by engine exit tag (0-spread / logic-parity):

| exit tag | parity_v2 Δ/trade (n) | T2_hourblock Δ/trade (n) | reading |
|---|---|---|---|
| **TP (runner backstop)** | **+286.1** (8) | **+397.4** (9) | engine credits the biggest runners **27–32% too much** (TP bucket eng 8,592 vs mt5 6,303; eng 11,267 vs mt5 7,691) |
| SL-WIN (trail/BE in profit) | +3.89 (272) | +15.11 (264) | engine books a richer trailed exit |
| SL-LOSS | −6.75 (190) | −20.11 (188) | engine *over-debits* losers (loses bigger too) |

- **Winner gross over-credit: +9.0% (parity_v2) / +17.5% (T2); 0-spread aggregate = +13.6% of engine
  winner gross (+10,914 USD).**  **[E]**
- **Matched net is engine +31.2% rich** (aggregate 0-spread: eng 24,624 vs mt5 18,773).  **[E]**
- The engine **over-debits losers** (−6.75 to −20/trade), which *masks* part of the winner over-credit at the
  net level — so the true exit-side optimism is larger than full-net Δ suggests.  **[E]**
- Mechanism (from C6 FINDINGS): a chandelier/runner that the engine lets ride captures continuation that
  MT5's real intrabar tick path gives back before the stop triggers. Concentrated in the fat tail — the lock's
  top-20 trades are **74%** of net (C8), exactly the TP/runner bucket where the over-credit is 27–32%.  **[E for magnitudes; I for "intrabar giveback" being the precise cause]**

### 2b. BE / trail / same-bar sequencing → exit-tag flips  **[E for counts, I for cause]**
Exit-tag flips run **6–7%** of matched pairs, and are **asymmetric**:

| flip | parity_v2 | T2 | reading |
|---|---|---|---|
| engine SL-WIN → MT5 SL-LOSS | 24 | 18 | engine thinks the trailed runner exited in profit; MT5 actually stopped at a loss |
| engine SL-LOSS → MT5 SL-WIN | 7 | 7 | reverse |
| engine TP → MT5 SL-WIN | 3 | 3 | engine reached the runner backstop; MT5 trailed out first |

Net flip bias ≈ **+14–17 phantom winners** for the engine. Because **matched `mfeR` is near-identical**
(mean +0.002 to +0.017 R, **median 0.000**), both sides *see the same price path* — the divergence is in
**where the exit fills land on that path** (BE/trail fill price + which of SL/TP resolves first inside the
same bar), **not** in the data feed or the entry.  **[E]** Attributing the SL-WIN→SL-LOSS flips specifically
to BE/trail same-bar sequencing is **[I]** — consistent with mfeR≈equal but unprovable without intrabar exit
timestamps (see §4).

### 2c. Fill price / spread / tick-delay  **[E]**
Adding a flat +0.17 spread (cost-match) shifts **full** net from engine-rich to engine-poor (parity_v2
+2.4%→−10.0%; T2 +18%→+9%) and trims a few marginal SL-WINs — but the **matched winner over-credit
persists** (+6.9% / +15.3%). So spread is a *separate, real* cost lever (≈$2–8/trade) that the over-credit
is **independent of**. The flat +0.17 over-penalizes vs Exness's variable spread (C2/C5), so the true live
cost sits between the 0-spread and +0.17 rows.  **[E]**

### 2d. Ranking unreliability  **[E]**
C6 (trail 2.5 vs 3.5) is direct evidence that engine exit-*geometry* ranking can be **sign-wrong**. By
extension every exit lever the engine "rejected" because it caps the runner (TP1-partial, tighter SL,
giveback) is suspect — which is exactly why those were all re-judged on MT5 (and the *one* exit win that
locked, the ProgTrail late-arm ladder C9, was confirmed on the MT5 optimizer, not adopted on engine alone).

---

## 3. HAIRCUT POLICY (apply to any engine-only MasterVP exit number before believing it)

Derived from §2; XAU M5; **lower bound** (2026 OOS half only). Losers need no upward haircut (engine already
over-debits them, which is conservative for net).

| # | When the engine number is… | Haircut | Derived from |
|---|---|---|---|
| **H-A** | a **runner / trailed-winner / TP-tag** P&L (the fat tail) | **discount 30%** | TP-bucket over-credit 27–32% (C2/C4, n=17) |
| **H-B** | **total winner gross** of an exit config | **discount 15%** | winner over-credit 9.0–17.5%, agg 13.6% |
| **H-C** | a **matched-pair / same-entries exit-only net edge** (e.g. an exit A/B where entries don't move) | **discount 30%** | matched net engine +31% rich (C2–C5) |
| **H-D** | **noise floor** — treat an engine-only exit gain as **noise** below this | **PF gain ≤ +0.015 (≈1% PF) OR same-entry net gain ≤ +10%** | engine runs +0.01–0.012 PF rich at full sample; full-net cancellation band spans +2.4% to +18% |
| **H-E** | an exit-**geometry ranking** (trail width, RR, SL distance) | **no haircut rescues it — MT5 optimizer mandatory** | C6 sign-flip (engine +24% → MT5 −24%) |

**How the floor (H-D) behaves against history (sanity check):** the H9C ProgTrail ladder showed an engine
flat-risk gain of **+3.4% net / +0.012 PF** — i.e. *inside* the H-D noise band — and indeed it was **not**
locked on the engine; it required MT5-optimizer confirmation (which it passed: MT5 +0.0118 PF, gate
DSR 1.000). The policy is therefore consistent with the one exit win we actually shipped: engine-only exit
gains in the single-digit-% / sub-0.015-PF range are leads, not locks.

**Practical default:** for an exit-side engine result with mixed winners/losers, the cleanest single number
is **H-C: knock 30% off the engine's net edge over its same-entry baseline**, then require the residual to
clear MT5. If you only trust the tail, use **H-A (30% off runner P&L)**. Either way, **H-E stands above all:
never lock an exit-geometry choice on engine ranking.**

---

## 4. What fresh MT5 export would replace each inferred haircut with a measured one

The biggest limitation is **window coverage**, then **missing exit-fill columns**.

| Gap today | Exact MT5 export to fix it |
|---|---|
| Haircuts measured on **2026 OOS half only** (~470 matched); full-year over-credit (incl. Aug-2025 chop + big 2025 runners) **inferred** | **Run:** EA `KK-MasterVP`, **XAUUSD**, **M5**, *Every tick based on real ticks*, **2025.06.01→2026.05.29**, deposit 10000, set `KK-MasterVP-XAUUSD-M5.set` (current lock, ProgTrail baked) **+ `InpExportParity=true`** → drop `trades_*.csv`. Then run the engine on the matched full-window tick file and re-run `exit_model_calibration.py`. Replaces H-A/H-B/H-C with full-year numbers. |
| **ProgTrail-ladder** over-credit (the locked exit mechanism C9) not isolated per-trade | Two MT5 full-window trade CSVs on **KK-MasterVP-Debug**: (a) ProgTrail ON (2.0/0.75/0.2), (b) `InpPmProgTrail=false`. Diff each vs the engine ladder-ON / ladder-OFF stream → measures whether the engine's +3.4% ladder credit is real per matured runner. |
| **Same-bar hit ambiguity (2b)** only *inferred* from 24 SL-WIN→SL-LOSS flips | Add to `Parity.mqh` per-trade export: **`exitTimeUTC`, `exitPrice`, and a `slTpSameBar` flag** (was SL and TP both inside the exit bar). Then the flips become directly attributable; quantifies the same-bar term. |
| **Fill-price / slippage** haircut folded into spread | Add **`exitPrice`** to the parity export (we have `realizedUsd` but not the exit px). Lets us split realized gap into level-choice vs fill-slippage. |
| **Cost surface** flat +0.17 over-penalizes vs Exness variable spread | Export MT5 per-trade `spreadPips` at fill (already a column on entry) + an exit-spread field; build the symbol/session spread distribution (ties into R5). |
| **BTC / other TF** — XAU haircut assumed a floor for BTC | BTC M5 KK-MasterVP full-window MT5 trade CSV; memory says BTC engine is *more* optimistic, so confirm the BTC haircut is ≥ XAU's before reusing it. |

---

## 5. One-line bottom line
On matched same-entry trades the C++ engine books MasterVP XAU M5 exits **~30% richer than MT5**, concentrated
in the runner/TP fat tail (**27–32% over-credit**, +13.6% of winner gross), with a **sign-flip risk in exit
ranking** (trail 3.5) — so haircut engine runner P&L 30% / winner gross 15%, treat engine-only exit gains
≤+0.015 PF (≈10% net) as noise, and **never lock exit geometry without an MT5 optimizer pass.**
