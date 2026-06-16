# Config-drift audit — KenKem & Monster (2026-06-16)

**Why:** MasterVP parity broke because `baseline.set` failed to pin keys that are BOTH C++-engine-read
AND genuine EA `input`s (`InpUseMtfAgree`: C++ true / MT5 false; `InpMaxPeakDDPct`: C++ 22 / MT5 30) →
engine default ≠ MT5 tester default → silent behavioral divergence. This audit re-runs that lesson on
KenKem and Monster. (Distinct from the already-fixed "Class-A EA-locked key" issue.)

A **drift-risk key** satisfies all of: (1) read by the C++ engine `apply_kv`, (2) a genuine EA `input`
(not hardcoded), (3) NOT pinned in the parity reference MT5 uses, (4) C++ default ≠ EA/MT5 value.

---

## Monster — ✅ CLEAN (no MasterVP-style bug)

Every genuine EA-input key the C++ engine reads has a C++ struct default that **exactly equals** the EA
`input` default → unpinned keys agree by construction. **0 confirmed drift keys.** Notably the two
MasterVP culprits are non-issues: `InpUseMtfAgree` does not exist in Monster; `InpMaxPeakDDPct` is C++
`0.0` == EA `0` (vs MasterVP's C++ 22).

- Evidence: `cpp_core/include/kk/monster/monster_config.hpp` (struct L19–199, `apply_kv` L235–411,
  `monster_non_input_keys()` lock L417–424); EA inputs
  `kenkem/MQL5/Experts/KK-MasterVP-Monster/Config/InputParams.mqh` L24–238; MT5 echo
  `kenkem/MQL5/Profiles/Tester/KK-Monster.set` (2026-06-16) + dated `KK-Monster.*.ini` (pin same 66 keys).
- ~41 unpinned genuine inputs are latent-only (match today; would drift if either default is edited).

### Monster — one real correctness gap (Class-A, not drift)
Two EA-**hardcoded** plain vars (not `input`s) are read by `apply_kv` but are **missing** from
`monster_non_input_keys()`, so a `.set` value would be honored by C++ yet ignored by MT5:
- `InpBrkRrLookbackBars` — plain `int=25` (InputParams L119; read apply_kv L304). Safe now (25/25).
- `InpMaxTradesPerSession` — plain `int=50` (InputParams L230; read apply_kv L404). Safe now (50/50).

**Action:** add both to `monster_non_input_keys()`. Low urgency (nothing pins them today) but it closes the
same class of hole the node params (`InpNodeDecay`…) already plugged.

---

## KenKem — ⚠️ CONFIRMED divergence + a target-EA mismatch (bigger than drift)

The MasterVP one-EA/one-namespace model does not hold for KenKem. **Two different EAs run in MT5:**

| MT5 run | Expert= | era | ADX/RSI len |
|---|---|---|---|
| original | `KenKem\KenKemExpert.ex5` | older .ini | hardcoded **14** (not inputs) |
| **distilled (current)** | `dquants\KK-KenKem\KK-KenKem.ex5` | **most recent, 2026-06-16** | **genuine inputs**, ran **ADX=15 / RSI=11** |

- The dquants C++ `kenkem_config.hpp` models the **original** `KenKemExpert`: it **locks** `ADX_LEN`/`RSI_LEN`
  to 14 via `is_ea_locked_key()` (hpp L322–335) and the parity sets strip them with the comment
  "EA hardcodes them to 14" (`parity_kenkem_xau.set:37`). **True for KenKemExpert, FALSE for KK-KenKem.**
- In `KK-KenKem` they are genuine inputs: `kenkem/MQL5/Experts/KK-Common/KenKem/Inputs.mqh:54`
  `input int InpAdxLen=14, InpRsiLen=14, InpAtrLen=14;` — and the latest tester `.set` loaded **15 / 11**
  (`kenkem/MQL5/Profiles/Tester/KK-KenKem.set`; `KK-KenKem.XAUUSD…M1.20250301_20251210.400.ini`).

**⟹ CONFIRMED divergence:** C++ runs ADX(14)/RSI(14); the current MT5 EA ran ADX(15)/RSI(11). Worse than
MasterVP — because the engine *refuses* these keys, **pinning them in the .set will NOT fix it**; the lock
itself must be revisited for the KK-KenKem target.

| logical param | C++ effective | MT5 (KK-KenKem) ran | genuine MT5 input? | verdict |
|---|---|---|---|---|
| ADX length | 14 (locked, refused) | **15** | yes (Inputs.mqh:54) | **CONFIRMED divergence** |
| RSI length | 14 (locked, refused) | **11** | yes (Inputs.mqh:54) | **CONFIRMED divergence** (feeds Sideways score) |
| ATR length (`ATR_PERIOD_FOR_SL`) | 14 (unpinned) | 14 (`InpAtrLen`) | yes | latent (equal now) |

### KenKem — separate issue flagged by the audit (verify, don't assume)
The agent reported the most recent **XAU** `KK-KenKem.set` carries **BTC-tuned** values (EMA 12/23/53/94/210,
MIN_MOMENTUM 13.97, E5_RR 1.2241) rather than the dquants XAU side. If real, the latest XAU MT5 run loaded
the wrong parameter file → every EMA/ADX/RR would differ for a config-selection reason, not drift. **Re-confirm
which values the XAU run actually used before drawing any parity conclusion.**

---

## ✅ DECISION (user, 2026-06-16, CORRECTED): two EAs, two ROLES — tune `KK-KenKem`, beat `KenKemExpert`
The first decision ("target = KenKemExpert, lock correct") was made on a misframing and is **superseded**.
Clarified user goal: *produce a BETTER KenKem via the dquants pipeline and ship it.* The two EAs are not
either/or — they are baseline vs deploy vehicle:
- **`KenKem\KenKemExpert.ex5`** = the **baseline to beat** (PF 1.62; ADX/RSI/EMA hardcoded). Stays the bar.
- **`dquants\KK-KenKem\KK-KenKem.ex5`** = the **Layer-4 promotion vehicle** — same E1/E2/E4/E5 logic
  (`KK-Common/KenKem/Engine.mqh`, toggles `InpE1On…InpE5On`) but ADX/RSI/EMA/RR exposed as **genuine
  inputs** (~96 inputs across `Inputs.mqh` + `CommonInputs.mqh`). This is what we **tune and deploy**.
- **Implication for the lock:** `is_ea_locked_key()` refusing ADX_LEN/RSI_LEN is correct ONLY for the
  hardcoded original. Against `KK-KenKem` those are real inputs → tuning them is legitimate & reproducible.
  The engine must be re-pointed at `KK-KenKem`: **un-lock** ADX/RSI/EMA, pin them in the parity `.set`,
  and validate parity against a **`KK-KenKem`** run (NOT KenKemExpert). KK-KenKem *expands* the tunable
  surface — it dissolves the old "contamination" problem rather than causing it.
- The "XAU set carries BTC values" flag is now a real to-check (it's the deploy vehicle's `.set`).

---

## Net result
- **Monster:** clean for drift; one minor lock-set gap to close (2 keys).
- **KenKem:** confirmed ADX/RSI divergence rooted in a **target-EA mismatch** (engine = KenKemExpert,
  current MT5 = KK-KenKem). Needs a user decision before any fix or sweep.
