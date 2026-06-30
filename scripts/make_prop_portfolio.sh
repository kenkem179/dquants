#!/bin/bash
# dquants Prop-Release Bundler
# ----------------------------------------------------------------------------
# Assembles ONE deployable VPS folder holding the LATEST released MasterVP +
# KenKem EAs and ALL THREE deployment profiles of their .set files —
#   PERSONAL (as-swept lock, one strategy alone),
#   PROP     (one strategy per individual prop account, tightened DD caps),
#   MIXED    (all legs on one shared FN-Stella2 account) —
# into:
#       mql5/experts/prop-releases/<portfolio-version>/
# Copy the whole folder to the VPS and deploy any mode case by case.
#
# The portfolio version is INDEPENDENT of the component EA versions: bump it
# whenever any component (MasterVP / KenKem) is re-released. Each copied file
# keeps its own component version in the filename, and PORTFOLIO.md records the
# exact component -> portfolio mapping.
#
# Usage:
#   scripts/make_prop_portfolio.sh <portfolio-version> [--mvp X.Y] [--kenkem X.Y]
#     <portfolio-version>  e.g. 1.0  (the bundle/folder version)
#     --mvp X.Y            pin MasterVP component version (default: latest released)
#     --kenkem X.Y         pin KenKem  component version (default: latest released)
# ----------------------------------------------------------------------------
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${GREEN}  ✓ $*${NC}"; }
step(){ echo -e "${YELLOW}$*${NC}"; }
die(){ echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPERTS="$ROOT/mql5/experts"

PVER=""; MVP_VER=""; KEN_VER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mvp)    MVP_VER="$2"; shift 2;;
    --kenkem) KEN_VER="$2"; shift 2;;
    *)        [ -z "$PVER" ] && PVER="$1" || die "unexpected arg: $1"; shift;;
  esac
done
[ -n "$PVER" ] || die "missing <portfolio-version> (e.g. 1.0)"
echo "$PVER" | grep -qE '^[0-9]+\.[0-9]+$' || die "portfolio-version '$PVER' not <major>.<minor>"

# latest released version = max of releases/<x.y>/ dirs (numeric sort)
latest_ver(){
  local dir="$1"
  ls -1 "$dir/releases" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1
}
[ -n "$MVP_VER" ] || MVP_VER="$(latest_ver "$EXPERTS/KK-MasterVP")"
[ -n "$KEN_VER" ] || KEN_VER="$(latest_ver "$EXPERTS/KK-KenKem")"
[ -n "$MVP_VER" ] || die "no KK-MasterVP release found"
[ -n "$KEN_VER" ] || die "no KK-KenKem release found"

MVP_REL="$EXPERTS/KK-MasterVP/releases/$MVP_VER"
KEN_REL="$EXPERTS/KK-KenKem/releases/$KEN_VER"
DEST="$EXPERTS/prop-releases/$PVER"

step "[1/3] Prop release bundle v$PVER  (MasterVP $MVP_VER + KenKem $KEN_VER · mixed + prop profiles)"
rm -rf "$DEST"; mkdir -p "$DEST"

# Files in the bundle: the shared EA binaries + ALL THREE deployment profiles —
# PERSONAL (as-swept lock, one strategy alone), PROP (one strategy per individual
# prop account, tightened DD caps), and MIXED (all legs on one shared account) —
# so the whole folder copies to the VPS and any mode deploys case by case.
COMPONENTS=(
  # --- EA binaries (shared by all profiles) ---
  "$MVP_REL|KK-MasterVP-$MVP_VER.ex5"
  "$KEN_REL|KK-KenKem-$KEN_VER.ex5"
  # --- Personal profile (as-swept lock, single strategy, no prop DD caps) ---
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5.set"
  "$KEN_REL|KK-KenKem-$KEN_VER-xauusd-m1.set"
  # --- Personal risk-tiered (standalone, tamed drawdown — NO prop baseline) ---
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5-conservative.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5-balanced.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5-conservative.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5-balanced.set"
  "$KEN_REL|KK-KenKem-$KEN_VER-xauusd-m1-conservative.set"
  "$KEN_REL|KK-KenKem-$KEN_VER-xauusd-m1-balanced.set"
  # --- Prop profile (one strategy per individual prop account) ---
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5-prop.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5-prop.set"
  "$KEN_REL|KK-KenKem-$KEN_VER-xauusd-m1-prop.set"
  # --- Mixed profile (all legs on one shared FN-Stella2 account) ---
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5-mixed-fn.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5-mixed-fn.set"
  "$KEN_REL|KK-KenKem-$KEN_VER-xauusd-m1-mixed-fn.set"
)

step "[2/3] Collecting components..."
for c in "${COMPONENTS[@]}"; do
  reldir="${c%%|*}"; fname="${c##*|}"
  if [ -f "$reldir/$fname" ]; then
    cp "$reldir/$fname" "$DEST/$fname"; info "$fname"
  else
    echo -e "${YELLOW}  ! missing (skipped): $fname${NC}"
  fi
done

step "[3/3] Writing PORTFOLIO.md..."
cat > "$DEST/PORTFOLIO.md" <<EOF
# Prop Release Bundle — v$PVER

Self-contained folder for the VPS: two EA binaries + ALL THREE deployment
profiles. Copy the whole folder over, then deploy **case by case** —

- **Mode A — Personal:** one strategy alone on a personal account (as-swept lock).
- **Mode B — Individual prop accounts:** one strategy per its own prop account.
- **Mode C — Mixed portfolio:** all three legs on ONE shared FN-Stella2 account.

Same \`.ex5\` for every mode; only the \`.set\` differs.

Components: MasterVP \`$MVP_VER\` · KenKem \`$KEN_VER\` · portfolio \`$PVER\`.

## Mode A — Personal (one strategy alone, as-swept lock)
| strategy | symbol · TF | .set |
|----------|-------------|------|
| MasterVP XAU | XAUUSD · M5 | \`KK-MasterVP-$MVP_VER-xauusd-m5.set\` |
| MasterVP BTC | BTCUSD · M5 | \`KK-MasterVP-$MVP_VER-btcusd-m5.set\` |
| KenKem XAU   | XAUUSD · M1 | \`KK-KenKem-$KEN_VER-xauusd-m1.set\` |

No prop DD caps and no contract-baseline anchor (runs the locked params as swept).
Use these for personal/non-funded accounts where firm drawdown rules don't apply.

## Mode A-Tiered — Personal, risk-tiered (tamed drawdown, standalone)
Same locked edge as Mode A, but with lower per-trade risk + tighter daily DD + an
ACTIVE soft-block (de-risk to half-lots before any hard cap) — for personal accounts
that find the as-swept 1% RPT / 10% daily / soft-block-off profile too aggressive.
Still standalone: **no** contract-baseline anchor, **no** shared HWM.

| strategy | symbol · TF | Conservative .set | Balanced .set |
|----------|-------------|-------------------|---------------|
| MasterVP XAU | XAUUSD · M5 | \`KK-MasterVP-$MVP_VER-xauusd-m5-conservative.set\` | \`KK-MasterVP-$MVP_VER-xauusd-m5-balanced.set\` |
| MasterVP BTC | BTCUSD · M5 | \`KK-MasterVP-$MVP_VER-btcusd-m5-conservative.set\` | \`KK-MasterVP-$MVP_VER-btcusd-m5-balanced.set\` |
| KenKem XAU   | XAUUSD · M1 | \`KK-KenKem-$KEN_VER-xauusd-m1-conservative.set\`   | \`KK-KenKem-$KEN_VER-xauusd-m1-balanced.set\`   |

DD tiers (MasterVP is true %-risk; KenKem keeps its fixed base lot and tiers DD caps only):

| tier | MasterVP RPT | daily DD | soft-block → lot | hard halt | KenKem daily / slowdown / soft-block |
|------|-------------|----------|------------------|-----------|--------------------------------------|
| Conservative | 0.5%  | 4% | 5% → 0.5x | 8%  | 4% / 5% / 8% → 0.5x (no hard halt; soft-block de-risks) |
| Balanced     | 0.75% | 5% | 6% → 0.5x | 10% | 5% / 6% / 10% → 0.5x (no hard halt; soft-block de-risks) |

Compounding trade-off vs the ~11X as-swept XAU run (geometric, edge fixed): Conservative
≈ ~3.3X, Balanced ≈ ~6X — roughly half / three-quarters the drawdown. Test before trusting.

## Mode B — Individual prop accounts (one strategy each)
| strategy | symbol · TF | .set | DD caps (daily / soft / hard) |
|----------|-------------|------|-------------------------------|
| MasterVP XAU | XAUUSD · M5 | \`KK-MasterVP-$MVP_VER-xauusd-m5-prop.set\` | 4.4% / 8.0%→0.5x / 9.5% |
| MasterVP BTC | BTCUSD · M5 | \`KK-MasterVP-$MVP_VER-btcusd-m5-prop.set\` | 4.4% / 8.0%→0.5x / 9.5% |
| KenKem XAU   | XAUUSD · M1 | \`KK-KenKem-$KEN_VER-xauusd-m1-prop.set\`   | 4.4% / slowdown 7% / soft-block 9% |

Run each on its OWN account (don't share the equity HWM across unrelated accounts).
Note: KenKem prop keeps \`MADE_FOR_PROP_TRADING=false\` (soft-block = micro-lots, no
hard halt) — its 9% soft-block is the de-risk floor, not a kill switch.

## Mode C — Mixed (all legs on one shared account)
| leg | symbol · TF | .set | risk/trade |
|-----|-------------|------|-----------|
| MasterVP XAU | XAUUSD · M5 | \`KK-MasterVP-$MVP_VER-xauusd-m5-mixed-fn.set\` | 0.43% |
| MasterVP BTC | BTCUSD · M5 | \`KK-MasterVP-$MVP_VER-btcusd-m5-mixed-fn.set\` | 0.15% |
| KenKem XAU   | XAUUSD · M1 | \`KK-KenKem-$KEN_VER-xauusd-m1-mixed-fn.set\` | 0.10% |

**Joint DD caps (all legs share ONE equity HWM):** daily 4.2% · soft-derisk 7.8% ·
hard-halt 9.2%. Attach all three on the SAME account so the shared-file HWM is joint.

## Overall-DD anchor (no manual seeding needed — prop + mixed)
Every prop + mixed set bakes the contract-baseline anchor (\`InpPropBaselineEquity\` /
\`PROP_BASELINE_EQUITY\` = **100000**). On a fresh attach the overall-DD high-water
mark is seeded at the contract size, so a drawn-down account reads its TRUE drawdown
(not 0%). **Change this to your contract size for a \$50K/\$200K account.** The HWM
trails UP from the baseline as new equity peaks print, and persists to the shared
file \`Common/Files/KK_PropState_<login>.txt\` (RESET = delete that file).

## Deploy
1. Copy both \`.ex5\` into \`MQL5/Experts/\` (or the symlinked \`Experts/dquants/\` path).
2. Pick a mode and attach the chart(s); load the matching \`.set\` (Inputs -> Load).
3. KenKem only: clear any stale \`KKG.*\` global variables before attach.
4. Set the baseline input to your account's contract size if not \$100K.
5. Confirm in the log: MasterVP prints \`prop baseline floor applied: peakEquity=...\`.

> Bundle assembled by \`scripts/make_prop_portfolio.sh $PVER\`. Bump the portfolio
> version whenever a component EA is re-released.
EOF
info "PORTFOLIO.md"

echo ""
echo -e "${GREEN}✓ Prop release bundle v$PVER packaged${NC}  ->  ${BLUE}$DEST${NC}"
echo -e "${YELLOW}note:${NC} *.ex5 is gitignored (build artifact); the .set files + PORTFOLIO.md commit normally."
