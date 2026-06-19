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
