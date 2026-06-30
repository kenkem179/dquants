# BUSINESS-PLAN.md — KenKem Trading Software: Go-To-Market Strategy

> Sibling to `BUILD-PLAN.md`. BUILD-PLAN is the engineering phase plan; this is the
> commercial strategy for selling the indicators and EAs. Last updated 2026-06-19.
> **NOT legal advice.** Japan-FSA / FIEA points below are framing to discuss with qualified
> Japanese counsel before acting. Engage a lawyer before scaling revenue or launching anything
> in Phase B.

## Regulatory posture (Japan FSA / FIEA) — the constraint that shapes everything

The business runs in **two phases, gated by licensing.** Hold the "not financial advice" stand point
firmly until the FSA-required qualified person is hired and registration is in place.

- **Phase A — Tool vendor (NOW, no license required):** Sell software the customer *operates and
  controls themselves*. No discretion over customer accounts, no managed money, no profit share, no
  copy trading, no personalized advice. The user sets their own risk and can disable the tool at any
  time. Keep "not financial advice" + past-performance disclaimers on everything. **This is the entire
  near-term business** and it is already working (real Pine users, testimonials, revenue).
- **Phase B — Licensed copy-trading / advisory (LATER, gated):** Copy-trade, signal service, and any
  managed/advisory offering only AFTER hiring the FSA-required person in charge and completing
  registration. Until then these stay off the table — they are the regulated activity, not the goal to
  rush.

### The gray zone to watch in Phase A
Under FIEA, providing **specific, paid buy/sell signals or alerts** for FX / gold-CFD instruments can be
construed as 投資助言業 (investment advisory business), which requires registration. To stay defensibly on
the *tool* side:
- Keep alerts **generic, automated, non-personalized** — "the indicator triggered at X" / "EMA cross on
  M1", NOT "buy now" / personalized recommendations.
- Premium gates the *tool's output* (and forces the user to set their own risk inputs); it does not
  hand out advice.
- The customer always makes and executes their own decision. The software computes; the human decides.
- Never guarantee returns; never take a cut of profits; never touch a customer's account.

## The business you're actually in

You are not selling indicators or EAs. **You are selling trust and proof, packaged as a tool the
customer runs themselves.** The retail market is ~90% scams, so buyers are skeptical. The biggest asset
is the **Kem trading club: a warm, trusting audience that can verify the system works** — and you
already have real Pine traction proving the tool-vendor model converts. Every move should compound that
trust and stay inside Phase A.

### Three hard truths

1. **Backtest ≠ live, and customers chargeback on the gap.** The edge is M1 EMA scalping on XAU — the
   most spread/slippage/latency-sensitive thing you can sell. A great backtest on a bad broker becomes
   an angry refund. This is *why the parity work matters commercially*: if live doesn't match the demo,
   you lose the customer AND the testimonial.
2. **Chargebacks and churn are the silent killers**, not piracy. A beginner who loses money blames you
   regardless of disclaimers. Control expectations (drawdown, losing streaks) and the broker/setup, or
   refunds eat the margin.
3. **"Tool not advice" is the whole moat until Phase B.** It is good positioning AND your regulatory
   posture. Protect it: sell a *tool*, never manage money or advise specifically, never guarantee
   returns, and keep a real entity + ToS + disclaimers behind it.

## Strategic priorities (Phase A, in order)

### 1. Build TWO verified track records — one per audience
Two proofs, because they convince different buyers:
- **FundedNext (prop audience):** the challenge→funded→payout journey proves *"this EA respects
  drawdown rules, passes the challenge, and trades funded capital"* — exactly what the prop-firm buyer
  needs, on small capital. Document it build-in-public as a content funnel. (Already in progress.)
- **Small real-money ECN account (retail audience):** prop-server execution ≠ real-broker execution, so
  a small live ECN account is the stronger proof for the retail "does it actually make money live"
  claim.

Publish both as read-only **MyFXBook/FXBlue verified** URLs framed as *"the developer's own results
running this tool — not a recommendation; past performance is not indicative of future results."* This
is marketing of a software product's performance, NOT a signal service.

### 2. Sell the EA as a license the customer runs on their OWN account
This is the Phase-A-safe way to monetize automation: the buyer installs, configures risk, and runs it
on their own MT5 account; they can switch it off anytime; you have zero discretion and take no profit
share. Monthly subscription **locked to MT5 account number** → recurring revenue, kill-switch control,
piracy protection.

**Defaults-OFF design (the posture interlock):** ship the EA with lot size / risk level / etc. = 0/OFF
so it will not trade until the user configures it themselves. This is both a safety interlock (no "it
traded huge and blew my account" complaints) and the core of the "not advice" posture — we never set
anything for them. To avoid the UX/conversion cost of a blank config, ship **example `.set` presets
(conservative / balanced / aggressive) as documentation** that the user must *choose and enable*. That
is software documentation describing how the parameters work — not advice. Keep all marketing about
*what the software does*, never *what returns to expect*.

| Segment | Phase A product (now) | Phase B (when licensed) |
|---|---|---|
| DIY traders | EA license + indicators (they run it) | — |
| **Prop-firm challengers** | EA license w/ "prop-firm mode" (strict daily-DD, news filter, conservative preset) — they run it on their own challenge account | — |
| Hands-off / wealthy ("just give me returns") | Served only as a *tool buyer* for now (done-with-you setup of THEIR own account). **No copy trade until Phase B.** | Copy-trade / signal subscription powered by the EA on a master account |
| Everyone (funnel) | Free/cheap "Basic" indicator → list build | — |

The "hands-off / wealthy" copy-trade play is the most attractive single move — but it is **Phase B**.
Don't shortcut it; it's the exact activity the FSA license is for.

### 3. Recurring revenue with account-locked licensing, everywhere
Monthly subscription keyed to MT5 account number (or TradingView invite-only) beats one-time sales:
predictable income, kill-switch control, forces continued delivery. One-time licenses get cracked.

### 4. Prop-firm is the biggest Phase-A-clean market (FundedNext = the proof vehicle)
A scalper with *strict drawdown control* is exactly what people use to pass challenges — a huge,
money-in-hand audience, and **unambiguously a tool the buyer runs themselves** (no advice, no copy
trade). FundedNext lets you prove the EA on a live-funded account with small capital, then convert that
proof into sales.

**Design the prop preset to respect firm rules** (verify per FundedNext account type before marketing):
- **EA allowance & news-trading limits** — confirm the account type permits EAs and how it treats news.
- **Consistency rule** — many firms cap any single day's share of total profit; a scalper with
  occasional big days can trip it. Build the preset to spread P&L.
- **Hard daily-DD limit + news filter + conservative lot caps** baked into the "prop-firm mode".

**Business risk to flag to customers — same-strategy / copy-trade detection:** if many customers run the
*identical* EA with *identical* settings on the same firm, surveillance can flag correlated trading as
prohibited copy/group trading → customer bans → refund pressure on you. The defaults-OFF design helps
(per-user settings de-correlate trades). State plainly in docs that compliance with each firm's rules is
the customer's responsibility.

## Concrete moves per product line (Phase A)

- **Pine indicators (TradingView):** You already sell here with real testimonials — expand it. Keep
  Basic/Premium split; make Basic *free* (invite-only) as a list-builder. **Reframe Premium alerts as
  generic automated tool triggers, not recommendations** (see gray-zone note). Billing via Whop
  subscription. This line is **discovery + funnel + proof**.
- **MT5 indicators:** Sell on **MT5 Market for discovery/credibility**, then convert buyers to your own
  Whop subscription for margin. Bundle EMA+VP as premium SKU; sell separately as entry points.
- **EAs:** Sequence — KenKemEA → club first → MasterVP/Monster flagship. Gate each release behind:
  (a) your-own verified live track record, (b) 3 risk presets, (c) a setup kit: recommended low-spread
  brokers, VPS guide, minimum account size, expected drawdown/losing-streak disclosure. All sold as a
  license the customer runs themselves.

## 90-day actionable plan (Phase A only)

### Days 1–30 — Foundation & proof
- [ ] FundedNext: run KenKemEA on a funded account; document challenge→funded→payout build-in-public (prop proof)
- [ ] KenKemEA live on a small real-money ECN account → MyFXBook verified link, framed as developer's own results (retail proof)
- [ ] Verify FundedNext rules for the account type: EA allowance, news-trading limits, consistency rule
- [ ] EA ships defaults-OFF; author conservative/balanced/aggressive `.set` presets as documentation
- [ ] Entity + ToS + disclaimers reviewed by Japanese counsel; confirm tool-vendor posture for FX/CFD
- [ ] Reframe Pine Premium alerts to generic non-personalized tool triggers (FIEA gray-zone hygiene)
- [ ] Pick ONE recommended broker; verify backtest matches its live spread/commission (feeds parity work)
- [ ] EA licensing tech: account-locked license-server check + monthly subscription billing

### Days 31–60 — Club beta & testimonials
- [ ] Release KenKemEA *license* to a small paid club cohort (they run it on their own accounts); collect screenshots, testimonials, UX feedback (cap it)
- [ ] Write the "expectations" doc (drawdown, losing streaks, broker requirements) — kills most chargebacks
- [ ] Convert Pine Premium to subscription; ship free Basic as funnel entry

### Days 61–90 — Productize & expand
- [ ] List KenKem MT5 indicator on MT5 Market for discovery
- [ ] Build & market prop-firm preset (Phase-A-clean, money-in-hand audience)
- [ ] Use the verified track record + testimonials as the public sales page for MasterVP/Monster license pre-launch

## Short-term action plan — prove the EA on VPS + sell ASAP (proposed 2026-07-01)

> Slots **inside Days 1–30** of the 90-day plan. Goal: stand up always-on proof accounts, start the
> marketing-automation flywheel, and open Phase-A-clean sales NOW while EA live-proof accrues. Stays
> strictly tool-vendor — no advice, no managed money, no guaranteed returns.

**The 3 documentation presets are READY (shipped 2026-07-01).** They map cleanly to the plan's
"conservative / balanced / aggressive" requirement:
- **Aggressive** = as-swept personal lock — `…-xauusd-m5.set` / `…-btcusd-m5.set` (1% RPT, 10% daily, soft-block off; the ~11X-but-swingy profile)
- **Balanced** = `…-{xauusd,btcusd}-m5-balanced.set` (0.75% RPT / 5% daily / soft-block 6%→0.5x / hard-halt 10%)
- **Conservative** = `…-{xauusd,btcusd}-m5-conservative.set` (0.5% / 4% / soft 5%→0.5x / halt 8%)
- KenKem XAU M1 mirrors with fixed-lot sizing + DD-cap tiers (`…-xauusd-m1-{conservative,balanced}.set`).

### A. Proof infrastructure (Week 1) — always-on accounts on VPS
| Account | Purpose / audience | EA + preset | VPS |
|---|---|---|---|
| **FundedNext** (challenge→funded→payout) | prop-buyer proof | prop-bundle v1.0 `…-prop.set` — **VERIFY FN daily-DD FIRST** | MetaQuotes VPS (broker-co-located, ~$15/mo) |
| **Exness small live ECN** | retail "does it make money LIVE" proof | `…-conservative.set` (real money, lowest risk) | **Exness FREE VPS** (qualify via deposit/volume) |
| **Demo #1 + #2** | A/B the tiers + daily screenshots | balanced vs aggressive, run in parallel | MetaQuotes VPS / free demo VPS |

- Migrate terminal + `.ex5` + `.set` to the VPS; confirm 24/5 uptime; clear stale `KKG.*` globals on each KenKem attach; set `InpPropBaselineEquity` / `PROP_BASELINE_EQUITY` to the real contract size.
- Attach **MyFXBook / FXBlue read-only verified** to every account → those URLs ARE the sales proof (framed "developer's own results, not a recommendation; past performance ≠ future results").
- ✅ **FundedNext Stellar-2 daily-DD = 5%** (confirmed 2026-07-01; the old "3%" in some docs was a stale internal-buffer number, now corrected). The prop `.set` caps the EA's daily loss at **4.4%** — a deliberate ~0.6% safety margin below the 5% firm line. Still verify the account-type **consistency rule** before scaling (a scalper's occasional big day can trip it).

### B. Marketing-automation flywheel (Week 1; runs daily thereafter)
Both engines already exist — wire them to the proof:
- **`../kenkem-pine` daily-bias** (`.claude/skills/daily-bias` + `daily-bias-scheduled.sh`): auto-generates a daily XAU/BTC market-bias AI insight. Use it as (a) free funnel content and (b) the recurring *tool output* that justifies a Pine-Premium / Whop subscription. **Keep it GENERIC and non-personalized** ("regime = trend, ATR percentile 62, London bias up") — never "buy now" — to stay on the tool side of the FIEA line.
- **`../dquants-sns`** (220–300 prepared posts + `generate_sns_images.py` AI images + publisher → FB/IG/X/Threads/Whop, driven by `STATE.json`): schedule the prepared series + AI images for hands-off multi-channel posting. Inject two LIVE feeds: (1) daily-bias output → the daily post slot; (2) a weekly **build-in-public** post = equity screenshot from the verified links above. Every published number must trace to `../dquants` (the repo's standing rule) — no invented stats.

### C. Sell ASAP — Phase-A-clean, sequenced by what's already proven (Days 1–30)
Sell what is proven NOW; pre-sell the EA behind the accruing track record.
1. **Now:** Pine indicators + **daily-bias subscription** (Whop, invite/account-locked) — already a live, converting line; the daily insight is the recurring deliverable.
2. **Now:** open EA-license **waitlist / pre-orders** (account-locked monthly, defaults-OFF, 3 presets shipped as docs) on the sales page — list price + limited spots, fulfilled when the EA clears its go-live gate (D).
3. **Funnel:** free Basic indicator + daily-bias teasers → list build → dquants-sns nurtures to the waitlist.

### D. EA "cleared to sell" gate (do NOT fulfil EA licenses before ALL hold)
Honest-proof gate, mirrors the engineering deploy gate:
- ≥ **30 days continuous live** on Exness ECN (conservative) with **live-vs-backtest delta within tolerance**,
- FundedNext challenge **passed** on the prop preset (or a documented honest fail + fix — publish either),
- **expectations doc** shipped (drawdown, losing streaks, broker/VPS/min-account requirements — kills chargebacks),
- recommended low-spread broker + VPS setup kit finalized.

### Metrics from day one
MRR (Pine + daily-bias subs) · EA waitlist size + pre-order conversion · refund/chargeback rate ·
**live-vs-backtest delta per broker** · daily-bias post → click → trial conversion.

## Phase B backlog (do NOT start until licensed hire + FSA registration)
- [ ] Hire FSA-required person in charge; complete registration
- [ ] Copy-trade / signal subscription for the hands-off / wealthy segment (master account → copiers)
- [ ] Any managed or discretionary / advisory offering

## Metrics to track from day one
- Monthly recurring revenue (MRR)
- **Churn rate** (real health metric for subscriptions)
- **Refund/chargeback rate** (trust thermometer)
- Free→paid conversion
- Live-vs-backtest performance delta per broker (product-quality early warning)

## One-sentence version
Stay strictly a *tool vendor* — sell indicators and an account-locked EA the customer runs themselves,
prove it with your own verified live track record, lean on the club's trust and your existing Pine
revenue, attack the prop-firm market (Phase-A-clean), and park copy-trading behind the FSA-licensed
hire — so you grow now without ever stepping over the "not financial advice" line.
