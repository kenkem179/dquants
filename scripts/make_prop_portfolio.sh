#!/bin/bash
# dquants Mixed Prop-Portfolio Bundler
# ----------------------------------------------------------------------------
# Assembles ONE deployable bundle for the FundedNext mixed prop account
# (MasterVP XAU M5 + MasterVP BTC M5 + KenKem XAU M1 on a single account) by
# collecting the LATEST released component EAs + their MIXED-profile .set files
# into:
#       mql5/experts/prop-releases/<portfolio-version>/
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

step "[1/3] Mixed prop-portfolio v$PVER  (MasterVP $MVP_VER + KenKem $KEN_VER)"
rm -rf "$DEST"; mkdir -p "$DEST"

# component files that make up the mixed bundle: relpath under the release dir
COMPONENTS=(
  "$MVP_REL|KK-MasterVP-$MVP_VER.ex5"
  "$MVP_REL|KK-MasterVP-$MVP_VER-xauusd-m5-mixed-fn.set"
  "$MVP_REL|KK-MasterVP-$MVP_VER-btcusd-m5-mixed-fn.set"
  "$KEN_REL|KK-KenKem-$KEN_VER.ex5"
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
# Mixed Prop Portfolio — v$PVER

One FundedNext Stellar-2 \$100K account running three legs together.

| component | version | EA file | symbol · TF | mixed .set | risk/trade |
|-----------|---------|---------|-------------|------------|-----------|
| MasterVP XAU | $MVP_VER | \`KK-MasterVP-$MVP_VER.ex5\` | XAUUSD · M5 | \`KK-MasterVP-$MVP_VER-xauusd-m5-mixed-fn.set\` | 0.43% |
| MasterVP BTC | $MVP_VER | \`KK-MasterVP-$MVP_VER.ex5\` | BTCUSD · M5 | \`KK-MasterVP-$MVP_VER-btcusd-m5-mixed-fn.set\` | 0.15% |
| KenKem XAU   | $KEN_VER | \`KK-KenKem-$KEN_VER.ex5\` | XAUUSD · M1 | \`KK-KenKem-$KEN_VER-xauusd-m1-mixed-fn.set\` | 0.10% |

**Joint DD caps (both EAs, measured on the SHARED equity HWM):** daily 4.2% ·
soft-derisk 7.8% · hard-halt 9.2%.

## Overall-DD anchor (no manual seeding needed)
Both mixed sets bake the contract-baseline anchor (\`InpPropBaselineEquity\` /
\`PROP_BASELINE_EQUITY\` = **100000**). On a fresh attach the overall-DD high-water
mark is seeded at the contract size, so a drawn-down account is read at its TRUE
drawdown (not 0%). Change this to your contract size for a \$50K/\$200K account.
The HWM trails UP from the baseline as new equity peaks print, and persists to
the shared file \`Common/Files/KK_PropState_<login>.txt\` (RESET = delete that file).

## Deploy
1. Copy both \`.ex5\` into \`MQL5/Experts/\` (or the symlinked \`Experts/dquants/\` path).
2. Attach 3 charts on the SAME account: XAUUSD M5, BTCUSD M5, XAUUSD M1.
3. Load the matching mixed \`.set\` on each (Inputs -> Load).
4. KenKem only: clear any stale \`KKG.*\` global variables before attach.
5. Confirm in the log: MasterVP prints \`prop baseline floor applied: peakEquity=100000.00\`.

> Bundle assembled by \`scripts/make_prop_portfolio.sh $PVER\`. Bump the portfolio
> version whenever a component EA is re-released.
EOF
info "PORTFOLIO.md"

echo ""
echo -e "${GREEN}✓ Mixed prop-portfolio v$PVER packaged${NC}  ->  ${BLUE}$DEST${NC}"
echo -e "${YELLOW}note:${NC} *.ex5 is gitignored (build artifact); the .set files + PORTFOLIO.md commit normally."
