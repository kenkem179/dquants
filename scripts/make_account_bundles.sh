#!/usr/bin/env bash
# make_account_bundles.sh — assemble one ready-to-send folder per client account.
#
# WHAT THIS DOES
#   For every MT5 account in the deployment lists, builds (or reuses) the
#   account-locked KK-MasterVP EA + KK-MasterVP-Profiler indicator and collects
#   them — together with all deploy .set presets and a README — into:
#
#       mql5/experts/accounts/<ACCOUNT_ID>/
#         KK-MasterVP-<eaver>_<id>.ex5          (account-locked EA, if listed)
#         KK-MasterVP-Profiler-<pver>_<id>.ex5  (account-locked indicator, if listed)
#         KK-MasterVP-XAUUSD-M5.set ... etc      (clean-named deploy presets)
#         KK-MasterVP-Profiler.set
#         README.txt
#       mql5/experts/accounts/<ACCOUNT_ID>.zip   (the same folder, zipped to send)
#
#   Real file COPIES (not symlinks) so the folder zips cleanly and travels.
#   The whole mql5/experts/accounts/ tree is gitignored (rebuildable artifacts +
#   client logins) — never committed.
#
# USAGE
#   scripts/make_account_bundles.sh [--no-build] [--no-zip]
#   make account-bundles
#
#   --no-build  reuse the .ex5 already under releases/<ver>/accounts/ (skip the
#               per-account compile step); fails if a needed .ex5 is missing.
#   --no-zip    create the folders but do not produce the .zip files.
#
# Accounts come from the same gitignored lists make_account_releases.sh uses:
#   scripts/deployment_accounts.KK-MasterVP.txt           (EA)
#   scripts/deployment_accounts.KK-MasterVP-Profiler.txt  (indicator)
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

c0='\033[0m'; cG='\033[0;32m'; cY='\033[1;33m'; cB='\033[0;34m'; cR='\033[0;31m'
step() { printf "${cY}%s${c0}\n" "$*"; }
info() { printf "${cG}  ✓ %s${c0}\n" "$*"; }
warn() { printf "${cY}  ! %s${c0}\n" "$*"; }
die()  { printf "${cR}error: %s${c0}\n" "$*" >&2; exit 1; }

DO_BUILD=1
DO_ZIP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) DO_BUILD=0 ;;
    --no-zip)   DO_ZIP=0 ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

EA_DIR="mql5/experts/KK-MasterVP"
PR_DIR="mql5/indicators/KK-MasterVP-Profiler"
EA_LIST="scripts/deployment_accounts.KK-MasterVP.txt"
PR_LIST="scripts/deployment_accounts.KK-MasterVP-Profiler.txt"
OUT_ROOT="mql5/experts/accounts"

read_ver() { grep -E '^[[:space:]]*#property[[:space:]]+version' "$1" \
             | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+)".*/\1/'; }
EA_VER="$(read_ver "$EA_DIR/KK-MasterVP.mq5")"
PR_VER="$(read_ver "$PR_DIR/KK-MasterVP-Profiler.mq5")"
[ -n "$EA_VER" ] && [ -n "$PR_VER" ] || die "could not read #property version"

# strip ".../foo" comment+blank lines; return 0/1 on whether the line is data.
# On success sets PID / PSERVER / PEXP. Accepts "id, server, expiry" or whitespace.
parse_acct_line() {
  local line; line="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$line" in ''|\#*) return 1 ;; esac
  if printf '%s' "$line" | grep -q ','; then
    PID="$(printf '%s' "$line"     | cut -d, -f1 | tr -d '[:space:]')"
    PSERVER="$(printf '%s' "$line" | cut -d, -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    PEXP="$(printf '%s' "$line"    | cut -d, -f3- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  else
    PID="$(printf '%s' "$line"     | awk '{print $1}')"
    PSERVER="$(printf '%s' "$line" | awk '{print $2}')"
    PEXP="$(printf '%s' "$line"    | awk '{print $3}')"
  fi
  [ -n "$PID" ]
}

# all account ids found in a list file (one per line)
ids_in() {
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if parse_acct_line "$line"; then printf '%s\n' "$PID"; fi
  done < "$1"
}

# print "server|expiry" for <id> in <file>, empty if absent
lookup() {
  local file="$1" want="$2"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if parse_acct_line "$line" && [ "$PID" = "$want" ]; then
      printf '%s|%s' "$PSERVER" "${PEXP:-perpetual}"; return 0
    fi
  done < "$file"
}

# pretty-print an expiry for the README: zero-pad YYYY.M.D -> YYYY.MM.DD (keep any time)
fmt_exp() {
  local e="$1" d rest
  case "$e" in ''|perpetual) printf 'perpetual'; return ;; esac
  d="${e%% *}"; rest=""; [ "$e" != "$d" ] && rest=" ${e#* }"
  printf '%s' "$d" | grep -qE '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$' || { printf '%s' "$e"; return; }
  local yy mm dd; IFS=. read -r yy mm dd <<EOF
$d
EOF
  printf '%s.%02d.%02d%s' "$yy" "$((10#$mm))" "$((10#$dd))" "$rest"
}

# clean a release .set name: drop the "-<ver>-" segment, prettify symbol/TF case
clean_set_name() {
  basename "$1" | sed -E "s/-${EA_VER}-/-/; s/xauusd/XAUUSD/; s/btcusd/BTCUSD/; s/-m5/-M5/; s/-m3/-M3/; s/-m1/-M1/"
}

printf "${cB}━━━ dquants per-account delivery bundles ━━━${c0}\n"
info "EA KK-MasterVP $EA_VER · Profiler $PR_VER"

# 1) (re)build the account-locked .ex5 ---------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
  step "[1/3] Building account-locked .ex5 (KK-MasterVP, KK-MasterVP-Profiler)..."
  ./scripts/make_account_releases.sh KK-MasterVP           >/dev/null || die "EA account build failed"
  ./scripts/make_account_releases.sh KK-MasterVP-Profiler  >/dev/null || die "Profiler account build failed"
  info "account-locked builds refreshed"
else
  step "[1/3] Reusing existing account-locked .ex5 (--no-build)"
fi

EA_ACC="$EA_DIR/releases/$EA_VER/accounts"
PR_ACC="$PR_DIR/releases/$PR_VER/accounts"

# 2) assemble per-account folders --------------------------------------------
step "[2/3] Assembling $OUT_ROOT/<id>/ ..."
ALL_IDS="$( { ids_in "$EA_LIST"; ids_in "$PR_LIST"; } | sort -u )"
[ -n "$ALL_IDS" ] || die "no accounts found in $EA_LIST or $PR_LIST"

COUNT=0
for id in $ALL_IDS; do
  dest="$OUT_ROOT/$id"
  rm -rf "$dest"; mkdir -p "$dest"

  ea_meta="$(lookup "$EA_LIST" "$id")"
  pr_meta="$(lookup "$PR_LIST" "$id")"
  ea_srv="${ea_meta%%|*}"; ea_exp="${ea_meta#*|}"
  pr_srv="${pr_meta%%|*}"; pr_exp="${pr_meta#*|}"
  srv="${ea_srv:-$pr_srv}"

  have_ea=0; have_pr=0
  if [ -n "$ea_meta" ]; then
    f="$EA_ACC/KK-MasterVP-${EA_VER}_${id}.ex5"
    [ -f "$f" ] || die "missing EA build $f (run without --no-build)"
    cp "$f" "$dest/"
    for s in "$EA_DIR/releases/$EA_VER"/*.set; do
      [ -f "$s" ] && cp "$s" "$dest/$(clean_set_name "$s")"
    done
    have_ea=1
  fi
  if [ -n "$pr_meta" ]; then
    f="$PR_ACC/KK-MasterVP-Profiler-${PR_VER}_${id}.ex5"
    [ -f "$f" ] || die "missing Profiler build $f (run without --no-build)"
    cp "$f" "$dest/"
    [ -f "$PR_DIR/KK-MasterVP-Profiler.set" ] && cp "$PR_DIR/KK-MasterVP-Profiler.set" "$dest/"
    have_pr=1
  fi

  # README ---------------------------------------------------------------
  {
    echo "KenKem — account-licensed package"
    echo "================================="
    echo
    echo "Account : $id"
    echo "Server  : ${srv:-(any)}"
    echo
    echo "These builds are locked to the account + server above and will not run"
    echo "on any other account (they show \"Invalid Account ID\" and stop)."
    echo
    echo "Included:"
    if [ "$have_ea" -eq 1 ]; then
      echo "  - KK-MasterVP EA  v$EA_VER   (expires: $(fmt_exp "$ea_exp"))"
      echo "      install: copy KK-MasterVP-${EA_VER}_${id}.ex5 into  MQL5/Experts/"
    fi
    if [ "$have_pr" -eq 1 ]; then
      echo "  - KK-MasterVP Profiler  v$PR_VER   (expires: $(fmt_exp "$pr_exp"))"
      echo "      install: copy KK-MasterVP-Profiler-${PR_VER}_${id}.ex5 into  MQL5/Indicators/"
    fi
    echo "  - .set presets: load via the EA/indicator settings dialog -> Load."
    echo
    echo "Access expires on the date shown (broker server time). After that the EA"
    echo "stops opening NEW trades but keeps managing any open position; the"
    echo "Profiler stops drawing. Both show \"Expired Access\"."
    echo
    echo "Automated trading software / analysis tool — not financial advice and no"
    echo "profit guarantee. Trading carries risk of loss; use at your own risk."
    echo
    echo "For more details, visit https://kenkem.biz"
  } > "$dest/README.txt"

  # 3) zip ---------------------------------------------------------------
  if [ "$DO_ZIP" -eq 1 ]; then
    ( cd "$OUT_ROOT" && rm -f "$id.zip" && zip -qr "$id.zip" "$id" )
    printf "${cG}  ✓ %s${c0}  (EA:%s Profiler:%s) -> %s/%s.zip\n" "$id" "$have_ea" "$have_pr" "$OUT_ROOT" "$id"
  else
    printf "${cG}  ✓ %s${c0}  (EA:%s Profiler:%s)\n" "$id" "$have_ea" "$have_pr"
  fi
  COUNT=$((COUNT+1))
done

step "[3/3] Done."
info "$COUNT account bundle(s) -> $OUT_ROOT/"
[ "$DO_ZIP" -eq 1 ] && info "zips ready to send: $OUT_ROOT/<id>.zip"
echo "note: mql5/experts/accounts/ is gitignored (rebuildable; holds client logins)."
