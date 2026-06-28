# KenKem: A Small, Selective Edge — and Why We're Upfront About It

*A companion to the MasterVP dossier. Same honesty standard — but KenKem is a different, more cautious
story, and we'd rather you hear the caveats from us than discover them yourself.*

---

## The honest one-paragraph version

KenKem is a **selective XAUUSD M1 strategy** that passed the same anti-luck statistical gate MasterVP did —
but **by a much narrower margin, on a much smaller sample.** It is a real, out-of-sample-positive edge, and
it has a genuinely valuable property: it makes money at *different times* than MasterVP, so the two together
are steadier than either alone. But we will not dress it up as a powerhouse. It is a **small, regime-
concentrated edge best used as a diversifier**, not a standalone money-printer. Here's exactly why.

---

## 1. The result (MasterVP's honest little sibling)

Strategy: **KK-KenKem (D5-E4Long), XAUUSD, M1.** Validated on real broker ticks, MT5-confirmed.

| Metric | Value | Honest read |
|---|---|---|
| Profit Factor | **1.43** | Comparable headline PF to MasterVP… |
| Net result | **+$1,427** | …but on far fewer, smaller trades. |
| Trades | **126** | **This is the catch — a small sample.** See §3. |
| Out-of-sample | PF **1.52** (+$497) | It *did* stay positive on data it wasn't tuned on. |

## 2. It passed the anti-luck test — but read the margin

KenKem cleared the **overfitting gate** (the Deflated/Probabilistic Sharpe + Minimum Track Record Length
framework — the same one explained in the MasterVP dossier). That's real and we don't take it lightly:

| Test | Threshold | KenKem | Verdict |
|---|---|---|---|
| Probabilistic Sharpe (PSR) | ≥ 0.95 | **0.953** | ✅ PASS — *by a hair* |
| Sample vs Minimum Track Record Length | sample ≥ MinTRL | **126 ≥ 122** | ✅ PASS — *by 4 trades* |

Compare that to MasterVP, which clears its bar by **7×**. KenKem clears it by a **whisker.** A pass is a
pass — but an honest seller tells you the difference between "seven times clear" and "four trades clear."

## 3. The caveats we insist you know

- **Small sample = lower certainty.** 126 trades is *just* enough to claim an edge statistically; it is not
  enough to be casual about. More live trades will tell us more — in either direction.
- **The edge is concentrated in a strong stretch.** A large share of KenKem's headline came from one
  exceptionally favorable quarter. Measured on its training window alone, the profit factor is closer to
  **~1.15** than 1.43. It is **regime-concentrated**: it shines when its conditions are present and idles
  (or chops) when they're not.
- **One instrument, one timeframe, one entry mix.** XAUUSD M1 only. We tested extending it to M3/M5 and to
  BTCUSD — and **rejected those** because they overfit. We're telling you what *didn't* work, too.

## 4. So why ship it at all? Because of what it does *next to* MasterVP

Here's the genuinely valuable part, and it's a structural fact, not a marketing line:

> KenKem's daily profit-and-loss is **almost uncorrelated** with MasterVP's (daily correlation ≈ **0.08**).

That means they tend to win and lose on *different days*. In our research, combining the two on a risk-
balanced basis produced **higher net profit at a lower drawdown** than running gold alone — a rare "free
lunch" that comes from genuine diversification, not from either strategy being stronger. **KenKem's real
job is to smooth the ride**, not to out-earn MasterVP.

## 5. The same verification offer

- Reproduce it in your own MT5 tester (XAUUSD M1, every-tick, real ticks) — we built it for parity.
- Forward-test on demo first. Given the smaller sample, this matters *even more* for KenKem.
- Ask us for the exact trade count, PSR, and MinTRL figures. They're above, in black and white.

---

## The bottom line

KenKem is **not** the headline act, and we won't pretend otherwise. It is a **small, selective, out-of-
sample-positive edge that barely-but-genuinely passed the anti-luck test**, whose real value is as an
**uncorrelated diversifier** alongside MasterVP. We ship it with its limitations printed on the label —
because a seller who hides the small print on the weaker product is telling you everything about how they
treat the strong one.

*Full methodology and the stronger MasterVP case: see `MASTERVP-EVIDENCE-NOT-LUCK.md`.*
