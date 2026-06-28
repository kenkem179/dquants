---
name: mql5-market-release
description: Release a KenKem EA/indicator to the MQL5 Market — (1) proactively fix the broker-robustness errors the automated validator flags, AND (2) auto-generate/refresh the product-page description so the user never hand-writes marketing copy. Use whenever (a) cutting/re-cutting a marketplace build, (b) the user pastes an MQL5 Market validation error/log (e.g. "failed modify ... close to market", "not enough money", "invalid stops", "Volume limit reached"), or (c) the user needs/updates a product description, short description, or tags. The validator runs the EA on arbitrary symbols/timeframes/account currencies (notably EURUSD H1) on brokers that report stops_level=0 — every trade op MUST be broker-defensive. Encodes every fix + the description template so we stop firefighting ad-hoc reports and re-writing copy.
---

# MQL5 Market release + validation hardening

The MQL5 Market has an **automated validator** that drag-drops the EA onto charts the author never
tested — typically **EURUSD H1**, but also other symbols, timeframes, and account currencies — on a
broker whose `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_TRADE_FREEZE_LEVEL` are often **0** while the server
*still* enforces a floating min-distance. Any trade op that assumes our XAU/BTC broker's conditions gets
rejected and the EA **fails validation**. This skill (1) proactively audits the EA against the known
failure catalog before release, and (2) maps any pasted validator error to its fix.

**Golden rule:** every `OrderSend` / `PositionModify` / `PositionClose` must be defended against
volume, margin, and stop/freeze-distance constraints — using *live broker values*, never constants.
These are Layer-4 (live MT5) guards with no C++ analog, so they do **not** affect engine parity, and
when they only suppress ops the broker would reject anyway they do **not** change a validated lock's
result.

## Workflow

### A. Triage a pasted validation error
1. Identify the symbol/TF/op from the log (validator usually says `test on EURUSD,H1`).
2. Match the symptom in the **Error catalog** below → apply the named fix at the cited choke-point.
3. Compile headless `bash scripts/compile_mql5.sh <ea>.mq5` → must be **0 errors / 0 warnings**.
4. Re-cut the SAME version (see §C) unless the user asks to bump.

### B. Proactive pre-release audit (run BEFORE every marketplace cut)
Walk the **Audit checklist** — grep each guard exists at every `mvpTrade.*` / `trade.*` call site.
Fix any gap before packaging. Catching it here is the whole point — no more ad-hoc reports.

### C. Cut the release
```bash
# Re-cut same version (default — user tests before a permanent bump):
./scripts/make_release.sh <STRATEGY> --set-version <X.Y> --notes "<what changed>"
# New version only when the user explicitly approves a bump:
make release STRATEGY=<STRATEGY> NOTES="..."
```
- Upload artifact = `mql5/experts/<STRATEGY>/releases/<X.Y>/market/<STRATEGY>-Market-<X.Y>.ex5`
  (the **internals-hidden** market edition, not the dev `.ex5`).
- **Per [[release-ask-version-bump]]: ALWAYS ask "bump version? (Y/N, default N)".** N = orphan/
  overwritable build; bump only AFTER the user has tested.
- `#property link "https://kenkem.biz"` is allowed on the Market; a kenkem.biz URL inside
  `#property description` is **not** for a PUBLIC Market upload — strip it from the description for the
  public build (fine for direct/account-locked distribution).
- `.ex5` is gitignored; `.set` + RELEASE.md + Changelog.md commit normally.

## Error catalog (symptom → cause → fix)

| Validator message | Cause | Fix |
|---|---|---|
| `failed modify ... [Modification ... close to market]` / `invalid stops` on a **modify** | New OR existing SL/TP within broker stop/freeze level; on EURUSD both levels report 0 so a naive `minDist=0` lets a near-market SL through | Guard the modify choke-point with `effMin = max(stops_level, freeze_level, spread)`, floor `10*_Point`; skip (no-op, retry next tick) if either current or new SL/TP is within `effMin` of market. **KK-MasterVP:** `MvpSafeModify` in `Engine.mqh`. **KK-KenKem:** `SafeModifyPosition` in `Utils/BrokerHelpers.mqh`. |
| Repeated identical modify every tick (log spam) | Re-sending a modify equal to current SL/TP | No-op suppression: skip when `\|new-cur\| <= _Point` for both SL & TP (already in `MvpSafeModify`). |
| `not enough money` / `No money` on entry | Order margin exceeds free margin (tiny deposit / high-margin symbol / big lot) | Before `Buy/Sell`: `OrderCalcMargin(otype,sym,lot,price,req)` then skip if `req > AccountInfoDouble(ACCOUNT_MARGIN_FREE)`. (KK-MasterVP `Engine.mqh` entry path.) |
| `Volume limit reached` / `invalid volume` | Lot ignores min/max/step or per-symbol/dir `SYMBOL_VOLUME_LIMIT` | Normalize: clamp to `[VOLUME_MIN, min(VOLUME_MAX, VOLUME_LIMIT)]`, floor ceiling to a step, round to `VOLUME_STEP`. (`KKPositionSize`/`Sizing.mqh`; KenKem `NormalizeLotSize`.) |
| `invalid stops` on **entry** | Entry SL/TP within stop/freeze level | `minDist = KKMinStopDist(sym) + spread + 2*_Point`; `KKClampStops()` pushes SL/TP outward. (KK-MasterVP entry path.) |
| `invalid price` / off-tick SL/TP | Price not a multiple of `SYMBOL_TRADE_TICK_SIZE` | `NormalizeDouble(px,_Digits)` + round to tick size (KenKem `NormalizePriceToTickSize`). |
| `PositionClose` rejected on a winning/near-TP trade | Position **frozen** (SL/TP within freeze level) — close is rejected like modify | Check `IsPositionFrozen()` before close; if frozen, skip and let it close naturally at its level (KenKem `SafePositionClose`). |
| Validator can't open ANY trade / "no trades" | Hardcoded pip/point math wrong for 5-digit FX, or symbol-specific constants | Derive pip/point/digits from `SymbolInfo*` at runtime; never hardcode for XAU/BTC. |
| Rejected for `DLL/WebRequest` use | External calls in tester | Tester-guard them (`if(MQLInfoInteger(MQL_TESTER)) return;`) — D3 Notifier already does. |

## Audit checklist (verify each holds at EVERY trade-op call site)

- [ ] **Modify guard** — every SL/TP modify routes through the freeze/stop-aware helper
      (`MvpSafeModify` / `SafeModifyPosition`), using `max(stops,freeze,spread)` floored at `10*_Point`,
      checking BOTH current and new SL/TP, and skipping (not erroring) when too close.
      `grep -n "PositionModify" mql5/experts/<EA>/*.mqh` → none should call `trade.PositionModify`
      directly, bypassing the helper.
- [ ] **Entry stop distance** — entry SL/TP clamped to `≥ stops/freeze + spread + buffer` from price.
- [ ] **Volume** — lot normalized to min/max/step AND capped by `SYMBOL_VOLUME_LIMIT`.
- [ ] **Margin** — `OrderCalcMargin` vs `ACCOUNT_MARGIN_FREE` before send; skip if unaffordable.
- [ ] **Close** — close routed through a frozen-position check.
- [ ] **No hardcoded symbol constants** — pip/point/digits/tick from `SymbolInfo*` at runtime.
- [ ] **External I/O tester-guarded** — Notifier/WebRequest/CSV off in tester.
- [ ] **Compiles 0 errors / 0 warnings** headless.
- [ ] **Market edition** — uploading the `releases/<ver>/market/` build, not the dev `.ex5`.
- [ ] **`#property description`** has no kenkem.biz URL for a PUBLIC Market upload (link property OK).

## Why these don't break a validated lock
All guards only *suppress* an op the broker would reject under our XAU/BTC conditions the validated
trails/entries already clear (SL/TP sit far beyond the level). So the locked MT5 result is byte-identical
on our broker; the guards only change behaviour on the edge-case symbols the validator probes. Still, if a
guard's floor could plausibly bind on the locked symbol, re-confirm that lock in MT5 before trusting it.

## Product description (auto-generate it — the user should NOT hand-write copy)

Each product has a description doc in `docs/guides/`:
`<STRATEGY>-EA-MQL5-Marketplace-Description.md` (EA) / `<NAME>-Profiler-MQL5-Marketplace-Description.md`
(indicator). **These are the canonical, MQL5-policy-compliant templates — clone their structure and tone;
never start from a blank page.** On every release, OFFER to refresh the description and produce the
copy-paste blocks (short + full + tags) so the user just pastes. Generate it; don't make them write it.

### How to generate / refresh (do this automatically)
1. **Read the source of truth, not memory:** the EA's VISIBLE inputs (`grep -nE "^\s*(input|sinput)" ` the
   market-edition source — these are the only knobs a buyer sees; hidden globals must NOT appear in copy),
   the shipped presets in `release.conf`, the flagship symbol/TF, and the prior description doc.
2. **Map each visible input → one plain-English bullet** grouped exactly as the existing doc (Risk /
   Account protection / Profit taking / Trading hours / News / Execution / Guardian / Notifications /
   Trade log / Misc). If an input was added/removed/renamed this release, add/remove/rename its bullet —
   that sync step is the whole reason this is in the skill. Keep one example value per knob (e.g. `0.5`
   calmer, `1.0` default).
3. **Reuse the fixed blocks verbatim** from the template: "Honest word on performance", "Disclaimer",
   "Requirements", "Quick start". They are already policy-vetted — only edit if a fact changed.
4. **Produce three paste-ready outputs:** (a) **Short description** (< ~1500 chars, indicator template has
   a labelled one); (b) **Full description** (the main field, ≤ 32000 chars); (c) **Tags** (the trailing
   `*Tags: ...*` line — comma list, lower-case, symbol + style keywords).
5. Write the result back into the `docs/guides/` doc so it's the new canonical, and hand the user the
   paste blocks.

### Structure to follow (EA)
Title (product name) → one-line hook → 1-paragraph "what it does, plainly" → **Why traders will like it**
(bullets) → **What it trades** (table: flagship / also-runs / best TF / style / account type) → **Quick
start** (numbered, demo-first note) → **The settings you control** (grouped bullets, one per visible
input, with the "internals are pre-configured and not exposed" closer) → **Included presets** (personal +
prop) → **Requirements** → **An honest word on performance** → **Disclaimer** → **Tags**.
Indicator variant: drop trade/risk groups; lead with "Display-only … places no orders, not a signal
service"; sections = What it draws / What it reads / Trend context / Study-only markers / Setup / What it
is **not** / Honest note / Tags. (See the Profiler doc.)

### MQL5 Market policy rules the copy MUST obey (why hand-writing wastes time)
- **No profit/outcome guarantees.** Never "guaranteed", "risk-free", "X% per month", "no losses". Use
  "historically tested", "designed to", "in our testing". Keep the Disclaimer block.
- **No contact info / off-market selling in the PUBLIC product text** — no email, phone, Telegram/Discord
  handles, or external sales URLs in the description field. (A `#property link` on the binary is allowed;
  a kenkem.biz URL in `#property description` must be stripped for the PUBLIC build — see §C.) Mentioning
  that the EA *can send alerts to* Discord/Telegram/Email is fine; pasting your own handle is not.
- **English required**; be specific and detailed (thin descriptions get rejected).
- **Honest screenshots only** — tester results must be realistic; no doctored equity curves.
- **Describe only what's exposed** — don't document hidden/locked internals or imply tunability that the
  market build doesn't offer.
- Keep within field limits: full ≤ 32000 chars, short field is small (~1500) — the indicator doc shows both.

### Don'ts that cost rework
- Don't invent inputs or claims not backed by the actual `input` set / presets.
- Don't drift the flagship symbol/TF from `release.conf` (currently XAUUSD M5).
- Don't leave stale bullets for inputs that were hidden or removed in the market edition.

## Related memory
[[release-ask-version-bump]] · [[ea-marketplace-and-account-builds]] · [[ea-release-versioning-convention]]
· [[compile-mql5-headless]] · [[mt5-run-instructions-must-be-exact]]
