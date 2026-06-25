#!/bin/bash
# dquants per-account EA builder (account-locked releases)
# ----------------------------------------------------------------------------
# Builds ONE compiled EA per MT5 account, each hard-locked to that account so
# it refuses to run anywhere else.
#
# IMPORTANT: per-account builds are the MQL5-MARKET EDITION, never a fully-
# exposed dev EA. Before baking the account, the same internals-hiding transform
# used by make_release.sh is applied (shared lib scripts/lib/market_edition.sh):
#   - KK-MasterVP: single-source — Inputs.mqh is hand-curated, so the dev source
#     already IS the market edition (no transform).
#   - KK-KenKem:   whitelist-strip — release.market.whitelist hides non-visible
#     inputs + bakes the locked defaults.
# So every account-locked .ex5 shows ONLY the user-facing knobs, exactly like the
# marketplace build, plus the account lock. Order: hide -> bake account -> compile.
#
# The lock is enforced by the shared guard
# mql5/experts/KK-Common/AccountLock.mqh: every KK EA carries two HIDDEN
# compiled-in strings (not dialog inputs), empty by default:
#
#     string ALLOWED_ACCOUNT_ID     = "";   // MT5 login number
#     string ALLOWED_ACCOUNT_SERVER = "";   // MT5 trade-server name
#
# A login number is only unique WITHIN a server (the same number can exist on
# different brokers), so each build pins BOTH. This script bakes one (id,server)
# pair into those globals, compiles, and saves the .ex5 with the account in its
# name — leaving the dev source byte-identical afterwards (trap-restored).
#
# At runtime KK_AccountAuthorized() compares the baked pair against the live
# account; on mismatch it raises Alert("Invalid Account ID") and OnInit returns
# INIT_FAILED, so MT5 never ticks the EA (no detection, no execution).
#
# ACCOUNTS FILE  (one account per line):
#     <AccountID>  <ServerName>
#   - whitespace- OR comma-separated; ServerName may contain spaces
#   - blank lines and lines starting with '#' are ignored
#   - ServerName is OPTIONAL: id-only lines lock the login on any server
#   Example:
#     12345678   FundedNext-Server
#     87654321   Exness-MT5Real8
#     11112222                       # locks the login on any server
#
# Default accounts file (gitignored — holds real account numbers):
#     scripts/deployment_accounts.txt          (shared default)
#   or per strategy, auto-detected if present:
#     scripts/deployment_accounts.<STRATEGY>.txt
#
# OUTPUT (gitignored .ex5 build artifacts):
#     mql5/experts/<STRATEGY>/releases/<VERSION>/accounts/
#       <STRATEGY>-<VERSION>_<AccountID>.ex5
#       ACCOUNTS.md                              (id -> server -> file manifest)
#
# Usage:
#   scripts/make_account_releases.sh <STRATEGY> [--accounts FILE] [--out DIR]
#   STRATEGY      KK-KenKem | KK-MasterVP   (folder under mql5/experts/)
#   --accounts F  account list (default: per-strategy file, else shared default)
#   --out DIR     output dir (default: releases/<VERSION>/accounts/)
# ----------------------------------------------------------------------------
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}  ✓ $*${NC}"; }
step() { echo -e "${YELLOW}$*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPERTS_DIR="$PROJECT_ROOT/mql5/experts"
# shellcheck source=lib/market_edition.sh
. "$SCRIPT_DIR/lib/market_edition.sh"

STRATEGY="${1:-}"
[ -n "$STRATEGY" ] || die "usage: make_account_releases.sh <STRATEGY> [--accounts FILE] [--out DIR]"
shift || true

ACCOUNTS_FILE=""
OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --accounts) shift; ACCOUNTS_FILE="${1:-}"; [ -n "$ACCOUNTS_FILE" ] || die "--accounts needs a path" ;;
    --out)      shift; OUT_DIR="${1:-}";       [ -n "$OUT_DIR" ]       || die "--out needs a path" ;;
    *)          die "unknown arg: $1" ;;
  esac
  shift || true
done

EA_DIR="$EXPERTS_DIR/$STRATEGY"
MQ5_FILE="$EA_DIR/$STRATEGY.mq5"
EX5_FILE="$EA_DIR/$STRATEGY.ex5"
[ -d "$EA_DIR" ]   || die "strategy folder not found: $EA_DIR"
[ -f "$MQ5_FILE" ] || die "EA source not found: $MQ5_FILE"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  dquants per-account builds — $STRATEGY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 1) Resolve the accounts file -----------------------------------------------
step "[1/5] Resolving accounts file..."
if [ -z "$ACCOUNTS_FILE" ]; then
  if   [ -f "$SCRIPT_DIR/deployment_accounts.$STRATEGY.txt" ]; then
    ACCOUNTS_FILE="$SCRIPT_DIR/deployment_accounts.$STRATEGY.txt"
  elif [ -f "$SCRIPT_DIR/deployment_accounts.txt" ]; then
    ACCOUNTS_FILE="$SCRIPT_DIR/deployment_accounts.txt"
  else
    die "no accounts file. Create scripts/deployment_accounts.txt (or pass --accounts FILE).
       Format per line: <AccountID> <ServerName>   (see deployment_accounts.txt.example)"
  fi
fi
[ -f "$ACCOUNTS_FILE" ] || die "accounts file not found: $ACCOUNTS_FILE"
info "accounts: $ACCOUNTS_FILE"

# Parse: each kept line -> "id<TAB>server" (server may be empty / contain spaces)
declare -a ACCT_IDS=() ACCT_SRVS=()
while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  # split on first comma if present, else on first run of whitespace
  if printf '%s' "$line" | grep -q ','; then
    id="$(printf '%s' "$line"  | cut -d',' -f1 | sed 's/[[:space:]]*$//')"
    srv="$(printf '%s' "$line" | cut -d',' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  else
    id="$(printf '%s'  "$line" | awk '{print $1}')"
    srv="$(printf '%s' "$line" | sed -E 's/^[^[:space:]]+[[:space:]]*//')"
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "${RED}  ! skipping invalid account id: '$line'${NC}"; continue; }
  case "$srv" in *'"'*|*'|'*) die "server name for $id contains an unsupported char (\" or |): '$srv'" ;; esac
  ACCT_IDS+=("$id"); ACCT_SRVS+=("$srv")
done < "$ACCOUNTS_FILE"
[ ${#ACCT_IDS[@]} -gt 0 ] || die "no valid account IDs in $ACCOUNTS_FILE"
info "${#ACCT_IDS[@]} account(s) to build"

# 2) Resolve version + locate the file that declares ALLOWED_ACCOUNT_ID -------
step "[2/5] Resolving version + lock source..."
VERSION="$(grep -E '^[[:space:]]*#property[[:space:]]+version' "$MQ5_FILE" \
            | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
[ -n "$VERSION" ] || die "no '#property version \"x.y\"' in $MQ5_FILE"
info "version $VERSION"

# the dev-compiled file holding the hidden globals (exclude the swapped-in
# market inputs file and the releases/ tree)
LOCK_FILE="$(cd "$EA_DIR" && grep -rlE '^[[:space:]]*string[[:space:]]+ALLOWED_ACCOUNT_ID[[:space:]]*=' \
              --include='*.mqh' --include='*.mq5' \
              --exclude='*.release.mqh' --exclude-dir=releases . 2>/dev/null \
              | sed 's|^\./||' | head -1 || true)"
[ -n "$LOCK_FILE" ] || die "no file declares 'string ALLOWED_ACCOUNT_ID =' under $EA_DIR"
LOCK_FILE="$EA_DIR/$LOCK_FILE"
grep -qE '^[[:space:]]*string[[:space:]]+ALLOWED_ACCOUNT_SERVER[[:space:]]*=' "$LOCK_FILE" \
  || die "$LOCK_FILE declares ALLOWED_ACCOUNT_ID but not ALLOWED_ACCOUNT_SERVER"
info "lock source: ${LOCK_FILE#$PROJECT_ROOT/}"

# 3) Prepare output + apply market-hiding + set up restore trap --------------
step "[3/5] Preparing output + marketplace hiding..."
[ -n "$OUT_DIR" ] || OUT_DIR="$EA_DIR/releases/$VERSION/accounts"
mkdir -p "$OUT_DIR"
info "out: ${OUT_DIR#$PROJECT_ROOT/}"

# Files mutated here (input sources for whitelist EAs + the account-lock file)
# are backed up to <file>.devbak; the trap restores them ALL so the working tree
# is left byte-identical. acctbase = the hidden, account-EMPTY baseline that each
# per-account bake starts from (removed on exit).
MKT_BACKUPS=()
restore_all() {
  local b f
  for b in "${MKT_BACKUPS[@]:-}"; do
    [ -n "$b" ] && [ -f "$b" ] || continue
    f="${b%.devbak}"; mv -f "$b" "$f"
  done
  MKT_BACKUPS=()
  rm -f "$LOCK_FILE.acctbase"
}
trap restore_all EXIT INT TERM

# 3a) Hide internals -> the working source becomes the marketplace edition
#     (single-source EAs like KK-MasterVP curate via Inputs.mqh; KK-KenKem strips
#     via whitelist; release.market.forcehide hides+hard-codes specific keys).
if mkt_has_edition "$EA_DIR"; then
  if mkt_uses_whitelist "$EA_DIR"; then
    info "hiding internals via release.market.whitelist"
  elif mkt_has_forcehide "$EA_DIR"; then
    info "single-source + force-hiding keys via release.market.forcehide"
  else
    info "single-source: Inputs.mqh already curated (no transform)"
  fi
  mkt_apply_hiding "$EA_DIR" MKT_BACKUPS || die "market hiding failed"
else
  echo -e "${YELLOW}  ! no marketplace edition for $STRATEGY — building from full dev source${NC}"
fi

# 3b) Ensure the lock file has a pristine backup for the final restore. If the
#     hiding step already backed it up (KenKem: it's an input source) its .devbak
#     is pristine — don't clobber it.
[ -f "$LOCK_FILE.devbak" ] || _mkt_push_backup MKT_BACKUPS "$LOCK_FILE"

# 3c) Snapshot the hidden, account-empty lock file as the per-account bake base.
cp -f "$LOCK_FILE" "$LOCK_FILE.acctbase"

# bake one (id, server) pair into the hidden globals (idempotent: always reads
# from the hidden baseline, so re-runs never stack)
bake_account() {
  local id="$1" srv="$2"
  cp -f "$LOCK_FILE.acctbase" "$LOCK_FILE"
  # -E (ERE) for portable BSD/GNU sed; \+ is unsupported in BSD BRE
  sed -E \
      -e "s|^([[:space:]]*string[[:space:]]+ALLOWED_ACCOUNT_ID[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"$id\"|" \
      -e "s|^([[:space:]]*string[[:space:]]+ALLOWED_ACCOUNT_SERVER[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"$srv\"|" \
      "$LOCK_FILE" > "$LOCK_FILE.tmp" && mv -f "$LOCK_FILE.tmp" "$LOCK_FILE"
}

# 4) Build one EA per account ------------------------------------------------
step "[4/5] Compiling per-account locked EAs..."
declare -a MANIFEST=()
BUILT=0
for i in "${!ACCT_IDS[@]}"; do
  id="${ACCT_IDS[$i]}"; srv="${ACCT_SRVS[$i]}"
  echo -e "${BLUE}  -> $id${srv:+  @ $srv}${NC}"
  bake_account "$id" "$srv"
  # verify the bake actually took (guards against a renamed/edited declaration)
  grep -qE "ALLOWED_ACCOUNT_ID[[:space:]]*=[[:space:]]*\"$id\"" "$LOCK_FILE" \
    || die "bake failed for $id — check the ALLOWED_ACCOUNT_ID declaration in $LOCK_FILE"
  if "$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" >/dev/null 2>&1 && [ -f "$EX5_FILE" ]; then
    out="$OUT_DIR/$STRATEGY-${VERSION}_${id}.ex5"
    cp -f "$EX5_FILE" "$out"
    info "$(basename "$out")"
    MANIFEST+=("$id|${srv:-(any server)}|$(basename "$out")")
    BUILT=$((BUILT + 1))
  else
    echo -e "${RED}  ✗ compile failed for account $id${NC}"
  fi
done

restore_all; trap - EXIT INT TERM
# rebuild the dev .ex5 from the restored (unlocked, full-dev) source so the
# working tree is left exactly as before
"$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" >/dev/null 2>&1 || true
[ "$BUILT" -gt 0 ] || die "no per-account EAs built"

# 5) Write ACCOUNTS.md manifest ----------------------------------------------
step "[5/5] Writing ACCOUNTS.md..."
GIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_BRANCH="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'n/a')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "# $STRATEGY $VERSION — account-locked builds"
  echo
  echo "- Built: \`$BUILD_DATE\` (UTC) · commit \`$GIT_HASH\` on \`$GIT_BRANCH\`"
  echo "- Each EA refuses to run on any account but the one baked in"
  echo "  (Alert \"Invalid Account ID\" + INIT_FAILED via KK-Common/AccountLock.mqh)."
  echo "- \`.ex5\` files are gitignored build artifacts; deploy them per account."
  echo
  echo "| account id | server | file |"
  echo "|------------|--------|------|"
  for row in "${MANIFEST[@]}"; do
    IFS='|' read -r id srv f <<<"$row"
    echo "| $id | $srv | \`$f\` |"
  done
} > "$OUT_DIR/ACCOUNTS.md"
info "ACCOUNTS.md"

echo
echo -e "${GREEN}✓ Built $BUILT account-locked EA(s)${NC}  ->  ${BLUE}$OUT_DIR${NC}"
echo -e "${YELLOW}note:${NC} dev source + dev .ex5 restored (working tree unchanged). *.ex5 is gitignored."
