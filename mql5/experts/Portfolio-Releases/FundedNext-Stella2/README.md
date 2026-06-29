# FundedNext Stella 2 — 3-Chart Portfolio Deployment

**Account:** $100,000 initial · daily limit **5%** · max/overall limit **10% static from initial balance → hard floor = $90,000**. The Guardian anchor is **pinned to the $100k initial** (`InpGuardInitialBalance`), so current balance no longer affects the math — you can attach at any balance and the floor stays $92,000.

Built 2026-06-29 (Guardian unified across all 3 EAs + anchor-pin recompile). Source locks: MasterVP 1.07 prop, KenKem D5-E4Long. Only **risk/protection** knobs were changed from the locks — every strategy/edge parameter is byte-identical to the MT5-confirmed lock.

---

## The mix (what to load on what)

| # | Chart | EA | .set | Role | Risk/trade | Why this weight |
|---|-------|----|------|------|-----------|-----------------|
| 1 | **XAUUSD M5** | KK-MasterVP | `01-KK-MasterVP-XAUUSD-M5-PRIMARY.set` | **PRIMARY money-maker** | **0.50%** (~$486) | Most-proven edge: MT5 PF **1.4246**, +86k flat-risk / 1,423 tr, gate **DSR 1.000**. Gets the most budget. |
| 2 | **XAUUSD M1** | KK-KenKem | `02-KK-KenKem-XAUUSD-M1-SECONDARY.set` | **SECONDARY money-maker** | **0.40% cap** (~$389; ≤2 concurrent) | MT5 +1,427 / PF **1.428** / 126 tr, gate PASS — thin sample (MinTRL 122<126), so deliberately humbler. Self-protects via prop hard-block (see below). |
| 3 | **BTCUSD M5** | KK-MasterVP | `03-KK-MasterVP-BTCUSD-M5-OPTIONAL.set` | **OPTIONAL diversifier** | **0.20%** (~$195) | Weakest by evidence (full-window **net loser**, MT5 PF 1.058; only a *regime-dependent* edge since mid-2025). Value is **diversification** (uncorrelated to gold), not proven alpha. **Safe to skip.** |

Total baseline heat if all fire once ≈ **1.1%**; realistic worst-case concurrent ≈ **1.5%** of balance.

---

## Account-level protection — now UNIFIED across all 3 EAs (recompiled 2026-06-29)

All three EAs run the **same cross-EA Account Risk Guardian** (KenKem was wired in — `KK-MasterVP.ex5` + `KK-KenKem.ex5` recompiled). It is equity-based, reads live equity every tick, and **shares one persistent record** across every KK EA on the terminal via login-keyed **GlobalVariables on the VPS disk** (day-start, peak, the static anchor, and the breach latch). One EA detects a breach → the shared latch flips → **all three halt and flatten their own positions together.** Identical config in every `.set`:

```
InpGuardEnable        = true
InpGuardDailyLossPct  = 3.5      ; − buffer ⇒ daily halt at 3.0% of day-start
InpGuardOverallDDPct  = 8.5      ; − buffer ⇒ overall halt at 8.0% below the pinned anchor
InpGuardBufferPct     = 0.5
InpGuardDDAnchor      = 1        ; STATIC anchor
InpGuardInitialBalance= 100000   ; ← PINS the anchor to your firm initial ($100k), not the attach balance
InpGuardFlatten       = true     ; on breach, each EA closes its OWN positions (magic/comment-filtered)
```

**The math (why this can't bust the account):**
- The anchor is **pinned to $100,000** (your firm initial), so the overall halt = `100,000 × (1 − 0.08)` = **$92,000** — a fixed **$2,000 (2%) above** the hard $90,000 floor, *regardless of what your balance is when you start.*
- Daily halt ≈ **3.0% of each day's start** — well inside the 5% firm daily line.
- Each EA flattens only its own trades: MasterVP by magic (`InpMVPMagic`), KenKem by comment (`"KenKemST"`) — they never touch each other's positions.

### Why this answers "start it and it just works"
- **Auto-reads balance/equity:** every tick, no hardcoded numbers.
- **Shared persistent VPS memory:** the `KKG.<login>.*` GlobalVariables are flushed to disk and survive restarts; all EAs read/write the same record.
- **Pinned to the firm line:** `InpGuardInitialBalance=100000` is re-asserted on every attach, so the $92k floor never drifts — **no more re-tuning when your balance changes, and no need to clear GlobalVariables anymore.**
- KenKem keeps its *own* prop hard-block (`MADE_FOR_PROP_TRADING=true`, peak-decay off, hard-block 7.5%) as an independent second layer.

### ⚠️ Honest caveats (read before going live)

1. **BTC keeps RunnerRr = 10.0, not your 3.4.** Your 3.4 is applied to **XAU** (where the lock was 4.0) — right there: higher hit-rate, no round-trip to BE, ProgTrail banks before the cap. **But BTC's net is tail-carried (top-10 trades = 219% of net)** — a 3.4R cap removes the fat-tail runners that *are* the edge and flips it negative. Right for gold, wrong for BTC.
2. **Two EAs share XAUUSD — verified safe.** KenKem only manages/closes trades commented `"KenKemST"`; MasterVP filters by magic — neither touches the other's positions. One coupling: KenKem's risk-counting is symbol-only, so when MasterVP holds XAU it counts toward KenKem's aggregate-risk gate and KenKem **self-throttles a bit** (trades slightly less). Safe (conservative), just lowers KenKem's frequency when gold is busy.

---

## Load procedure (do this in order)

1. **Reload the recompiled EAs.** The new logic is in `KK-MasterVP.ex5` and `KK-KenKem.ex5` — make sure MT5 picks them up (re-attach the EA, or restart the terminal so it reloads the `.ex5`).
2. Open **3 charts**: XAUUSD M5, XAUUSD M1, BTCUSD M5.
3. Attach the matching EA to each, **Load** the matching `.set` (Inputs tab → Load). *(No GlobalVariable clearing needed anymore — `InpGuardInitialBalance` pins the anchor for you.)*
4. Confirm **AutoTrading** is on and each EA shows its smiley. The Guardian logs a status line (`eq=… ovrDD=…/8.5% halted=…`) — sanity-check the equity reads right.
5. Optional: enable BTC only if you want the diversifier.

---

## As the account recovers (loosen later, not now)

These numbers are deliberately tight for capital-preservation. Once you're comfortably profitable and want more room, the anchor is pinned to $100k so you can simply:
- Raise `InpGuardOverallDDPct` toward 9–9.5 in all three `.set` (e.g. 9.0 ⇒ floor $91,500), and/or
- Lift MasterVP XAU to 0.6–0.75% and KenKem cap to 0.5–0.6%.
Change it in every `.set` together so the shared line stays consistent.

## Honesty summary (per the trust contract)
- **Proven, deploy with confidence:** MasterVP XAU M5. **Good but thinner:** KenKem XAU M1. **Speculative/optional:** BTC M5.
- XAU RR 3.4 is a deviation from the DSR-passed 4.0 lock: expect **higher win-rate + raw net, slightly lower PF** (the sweep's RR3.2 gave net ~92k @ PF 1.357 vs the lock's PF 1.413). Your informed hit-rate-over-PF preference — applied, eyes open.
- Account-bust protection is now **unified across all three** via one shared, VPS-persistent Guardian pinned to the $100k firm line: any breach → all three halt + flatten their own positions at **$92,000** (2% above the $90k floor). Auto-reads equity, survives restarts, never needs re-tuning. KenKem also keeps its own prop hard-block as a second layer.
