#!/bin/bash
# dquants EA Release Packager
# ----------------------------------------------------------------------------
# Packages a compiled MQL5 EA + its parameter sets into a versioned release
# folder, leaving the DEV copy untouched.
#
#   mql5/experts/<STRATEGY>/<STRATEGY>.mq5        <- DEV source (untouched)
#   mql5/experts/<STRATEGY>/<STRATEGY>.ex5        <- DEV build  (untouched)
#   mql5/experts/<STRATEGY>/*.set                 <- DEV presets (untouched)
#   mql5/experts/<STRATEGY>/release.conf          <- variant manifest (optional)
#                       │
#                       ▼  make_release.sh
#   mql5/experts/<STRATEGY>/releases/<VER>/<STRATEGY>-<VER>.ex5
#   mql5/experts/<STRATEGY>/releases/<VER>/<STRATEGY>-<VER>-<variant>.set
#   mql5/experts/<STRATEGY>/releases/<VER>/RELEASE.md
#
# Versioning is AUTOMATIC:
#   - Scans releases/<x.y>/ for the latest already-released version.
#   - If none exists, releases at the dev `#property version`.
#   - If one exists, bumps to the next free version (minor by default, or
#     --major) and writes that back into the .mq5 `#property version`, so the
#     dev source always matches the newest release.
#   - --set-version X.Y forces an exact version (no auto-bump).
#
# Multiple .set variants per EA (e.g. one for XAU, one for BTC, a prop build
# with tighter risk) are declared in release.conf. Each line:
#
#     <variant>   <source.set>   [KEY=VAL ...]
#
#   variant     -> tag appended to the release .set name
#   source.set  -> dev preset (relative to the strategy dir) used as the base
#   KEY=VAL ...  -> optional overrides applied to that variant only
#                   (this is how a prop build diverges from a personal one)
#
# If release.conf is absent, every *.set in the strategy dir is bundled as-is.
#
# Every release also appends a dated entry (newest on top) to the rolling
# changelog that lives ALONGSIDE the version folders:
#
#   mql5/experts/<STRATEGY>/releases/Changelog.md
#
# Pass a human description with --notes "..."; re-running the same version
# replaces that version's block (idempotent).
#
# Usage:
#   scripts/make_release.sh <STRATEGY> [--no-compile] [--major|--minor] [--set-version X.Y] [--notes "text"]
#   STRATEGY       e.g. KK-MasterVP  (folder name under mql5/experts/)
#   --no-compile   reuse the existing dev .ex5 instead of recompiling
#   --major|--minor  which digit to auto-bump when a release exists (default minor)
#   --set-version  force an exact <major>.<minor> (skips auto-bump)
#   --notes "..."  one-line description recorded in Changelog.md for this version
# ----------------------------------------------------------------------------
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}  ✓ $*${NC}"; }
step() { echo -e "${YELLOW}$*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPERTS_DIR="$PROJECT_ROOT/mql5/experts"

STRATEGY="${1:-}"
[ -n "$STRATEGY" ] || die "usage: make_release.sh <STRATEGY> [--no-compile] [--major|--minor] [--set-version X.Y]"
shift || true
DO_COMPILE=1
BUMP_KIND="minor"       # default: bump the minor digit when a release already exists
EXPLICIT_VER=""         # --set-version X.Y forces an exact version (no auto-bump)
REL_NOTES=""            # --notes "..." -> one-line changelog description for this version
while [ $# -gt 0 ]; do
  case "$1" in
    --no-compile)  DO_COMPILE=0 ;;
    --major)       BUMP_KIND="major" ;;
    --minor)       BUMP_KIND="minor" ;;
    --set-version) shift; EXPLICIT_VER="${1:-}"; [ -n "$EXPLICIT_VER" ] || die "--set-version needs X.Y" ;;
    --notes)       shift; REL_NOTES="${1:-}"; [ -n "$REL_NOTES" ] || die "--notes needs a description" ;;
    *)             die "unknown arg: $1" ;;
  esac
  shift || true
done

EA_DIR="$EXPERTS_DIR/$STRATEGY"
MQ5_FILE="$EA_DIR/$STRATEGY.mq5"
EX5_FILE="$EA_DIR/$STRATEGY.ex5"
[ -d "$EA_DIR" ]  || die "strategy folder not found: $EA_DIR"
[ -f "$MQ5_FILE" ] || die "EA source not found: $MQ5_FILE"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  dquants release — $STRATEGY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 1) Resolve version: check existing releases, auto-bump, sync the .mq5 --------
step "[1/6] Resolving version..."
RELEASES_DIR="$EA_DIR/releases"

# bump_ver <x.y> <major|minor>  -> next version string
bump_ver() {
  local v="$1" kind="$2" maj min
  maj="${v%%.*}"; min="${v#*.}"
  if [ "$kind" = "major" ]; then maj=$((maj + 1)); min=0; else min=$((min + 1)); fi
  printf '%d.%02d' "$maj" "$min"   # MQL5 minor is 2-digit (1.00, 1.10, 1.11)
}
# ver_ge <a> <b>  -> true if a >= b (numeric major.minor compare)
ver_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n | tail -1)" = "$1" ]; }

DEV_VER="$(grep -E '^#property[[:space:]]+version' "$MQ5_FILE" \
            | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
[ -n "$DEV_VER" ] || die "no '#property version \"x.y\"' found in $MQ5_FILE"
echo "$DEV_VER" | grep -qE '^[0-9]+\.[0-9]+$' \
  || die "version '$DEV_VER' is not <major>.<minor> (MQL5 rule)"

# latest already-released version (max of releases/<x.y>/ dirs)
LATEST_REL=""
if [ -d "$RELEASES_DIR" ]; then
  # `|| true`: under `set -euo pipefail`, grep exits 1 when no numeric-version
  # folder exists yet (e.g. releases/ holds only a non-standard tag like
  # 1.8.154-legacy) — that's a valid "no prior release", not an error.
  LATEST_REL="$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
                 | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
fi

if [ -n "$EXPLICIT_VER" ]; then
  echo "$EXPLICIT_VER" | grep -qE '^[0-9]+\.[0-9]+$' || die "--set-version '$EXPLICIT_VER' not <major>.<minor>"
  VERSION="$EXPLICIT_VER"
  info "explicit version $VERSION (--set-version; no auto-bump)"
elif [ -z "$LATEST_REL" ]; then
  VERSION="$DEV_VER"
  info "no prior release found — first release at dev version $VERSION"
else
  # candidate = max(dev, latest released); bump while that folder already exists
  VERSION="$DEV_VER"
  ver_ge "$LATEST_REL" "$VERSION" && VERSION="$LATEST_REL"
  while [ -d "$RELEASES_DIR/$VERSION" ]; do VERSION="$(bump_ver "$VERSION" "$BUMP_KIND")"; done
  info "latest release $LATEST_REL (dev $DEV_VER) -> next ($BUMP_KIND) = $VERSION"
fi

# Sync the resolved version back into the dev .mq5 so source == released build.
if [ "$VERSION" != "$DEV_VER" ]; then
  sed -E "s|(^#property[[:space:]]+version[[:space:]]+\")[^\"]+(\")|\1$VERSION\2|" \
      "$MQ5_FILE" > "$MQ5_FILE.tmp" && mv "$MQ5_FILE.tmp" "$MQ5_FILE"
  info "bumped #property version in $STRATEGY.mq5: $DEV_VER -> $VERSION"
fi

# Marketplace-edition plumbing (used in the optional [market] step at the end).
# If a release-only inputs file (Inputs.release.mqh) exists, the script also
# emits a second, MQL5-Market-ready build where the technical strategy params
# are hidden (fixed). That build is produced by transiently swapping this file
# in for the compile; the DEV Inputs.mqh is backed up and restored via a trap,
# so `make release` NEVER mutates the committed source. The NORMAL release below
# (full EA + personal/prop sets) is unaffected and exposes every input.
PUBLIC_INPUTS="$EA_DIR/Inputs.release.mqh"
DEV_INPUTS="$EA_DIR/Inputs.mqh"
INPUTS_BACKUP=""
restore_inputs() {
  if [ -n "$INPUTS_BACKUP" ] && [ -f "$INPUTS_BACKUP" ]; then
    mv -f "$INPUTS_BACKUP" "$DEV_INPUTS"; INPUTS_BACKUP=""
  fi
}
trap restore_inputs EXIT INT TERM

# 2) Compile (or reuse) the DEV EA -------------------------------------------
if [ "$DO_COMPILE" -eq 1 ]; then
  step "[2/6] Compiling dev EA..."
  "$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" || die "compile failed — fix errors first"
else
  step "[2/6] Skipping compile (--no-compile)"
fi
[ -f "$EX5_FILE" ] || die "no .ex5 — compile the dev EA first (drop --no-compile)"
info "dev build: $STRATEGY.ex5"

# 3) Create the versioned release folder -------------------------------------
step "[3/6] Creating releases/$VERSION/ ..."
REL_DIR="$EA_DIR/releases/$VERSION"
mkdir -p "$REL_DIR"
REL_EX5="$REL_DIR/$STRATEGY-$VERSION.ex5"
cp -f "$EX5_FILE" "$REL_EX5"
info "$STRATEGY-$VERSION.ex5"

# 4) Package the .set variants ------------------------------------------------
step "[4/6] Packaging parameter sets..."
CONF="$EA_DIR/release.conf"
declare -a SET_LINES=()   # "variant|relpath|overrides" for the RELEASE.md table

# apply_overrides <set-file> "KEY=VAL KEY=VAL ..."  (UTF-8 key=value presets)
apply_overrides() {
  local f="$1"; shift
  local kv
  for kv in "$@"; do
    local key="${kv%%=*}" val="${kv#*=}"
    if grep -qE "^${key}=" "$f"; then
      # portable in-place edit (BSD/GNU sed) via temp file
      sed "s|^${key}=.*|${key}=${val}|" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
      printf '%s=%s\n' "$key" "$val" >> "$f"
    fi
  done
}

# Allowlist of dialog-visible input keys (lines beginning `input <type> Inp...`)
# taken from the market inputs file (Inputs.release.mqh). Used ONLY by the
# marketplace edition below to strip hidden-internal keys from its .set files so
# they are never leaked in the shipped preset text. The NORMAL .set files above
# are NOT filtered. Empty (no filtering) if Inputs.release.mqh is absent.
VISIBLE_KEYS=""
if [ -f "$PUBLIC_INPUTS" ]; then
  VISIBLE_KEYS="$(grep -oE '^[[:space:]]*input[[:space:]]+[A-Za-z_]+[[:space:]]+Inp[A-Za-z0-9_]+' "$PUBLIC_INPUTS" \
                  | awk '{print $NF}' || true)"
fi

# filter_set_to_visible <set-file> : drop every line whose key is not a visible
# input (and all comment/blank lines); prepend a clean header.
filter_set_to_visible() {
  local f="$1"
  [ -n "$VISIBLE_KEYS" ] || return 0
  local tmp="$f.flt" line key
  {
    echo "; $STRATEGY $VERSION preset. Strategy internals are fixed inside the EA;"
    echo "; only the user-adjustable inputs below are present."
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in \;*|'') continue ;; esac
      key="$(printf '%s' "${line%%=*}" | tr -d '[:space:]')"
      # `if` (no else) returns 0 even when the key is hidden, so the while loop
      # always ends 0 and the redirected group below never trips `set -e`.
      if printf '%s\n' "$VISIBLE_KEYS" | grep -qx "$key"; then
        printf '%s\n' "$line"
      fi
    done < "$f"
  } > "$tmp"
  mv -f "$tmp" "$f"
}

if [ -f "$CONF" ]; then
  info "using manifest: release.conf"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                              # strip comments
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    read -r variant source rest <<<"$line"
    [ -n "$variant" ] && [ -n "$source" ] || die "bad release.conf line: $line"
    local_src="$EA_DIR/$source"
    [ -f "$local_src" ] || die "source set not found: $local_src"
    out="$REL_DIR/$STRATEGY-$VERSION-$variant.set"
    cp -f "$local_src" "$out"
    if [ -n "${rest:-}" ]; then
      # shellcheck disable=SC2086
      apply_overrides "$out" $rest
    fi
    info "$STRATEGY-$VERSION-$variant.set  ($source${rest:+  [$rest]})"
    SET_LINES+=("$variant|$source|${rest:-—}")
  done < "$CONF"
else
  info "no release.conf — bundling all dev *.set as-is"
  shopt -s nullglob
  for s in "$EA_DIR"/*.set; do
    base="$(basename "$s" .set)"
    variant="${base#$STRATEGY-}"                    # strip leading strategy name
    [ "$variant" = "$base" ] && variant="default"   # fallback when no prefix
    out="$REL_DIR/$STRATEGY-$VERSION-$variant.set"
    cp -f "$s" "$out"
    info "$STRATEGY-$VERSION-$variant.set  ($(basename "$s"))"
    SET_LINES+=("$variant|$(basename "$s")|—")
  done
  shopt -u nullglob
fi
[ ${#SET_LINES[@]} -gt 0 ] || die "no .set files packaged (none found / none in release.conf)"

# 5) Write RELEASE.md provenance ---------------------------------------------
step "[5/6] Writing RELEASE.md..."
GIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_BRANCH="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'n/a')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REL_MD="$REL_DIR/RELEASE.md"
{
  echo "# $STRATEGY — release $VERSION"
  echo
  echo "- Built: \`$BUILD_DATE\` (UTC)"
  echo "- Source commit: \`$GIT_HASH\` on \`$GIT_BRANCH\`"
  echo "- EA: \`$STRATEGY-$VERSION.ex5\` (locked build of \`$STRATEGY.mq5\`)"
  echo
  echo "## Parameter sets"
  echo
  echo "| variant | .set file | base preset | overrides |"
  echo "|---------|-----------|-------------|-----------|"
  for row in "${SET_LINES[@]}"; do
    IFS='|' read -r v src ov <<<"$row"
    echo "| $v | \`$STRATEGY-$VERSION-$v.set\` | \`$src\` | $ov |"
  done
} > "$REL_MD"
info "RELEASE.md"

# 6) Append (newest on top) to the rolling Changelog.md ----------------------
# Lives alongside the version folders: releases/Changelog.md. Idempotent —
# re-releasing the same version replaces that version's block.
step "[6/6] Updating Changelog.md..."
CHANGELOG="$RELEASES_DIR/Changelog.md"
CL_TITLE="# $STRATEGY — Changelog"
NOTES="${REL_NOTES:-Release packaged via make_release.sh (no --notes given).}"

ENTRY="$(mktemp)"
{
  echo "## $VERSION — ${BUILD_DATE%%T*}"
  echo
  echo "- Built \`$BUILD_DATE\` · commit \`$GIT_HASH\` on \`$GIT_BRANCH\`"
  echo "- EA: \`$STRATEGY-$VERSION.ex5\` (locked build of \`$STRATEGY.mq5\`)"
  echo "- $NOTES"
  printf -- '- Variants:'
  for row in "${SET_LINES[@]}"; do
    IFS='|' read -r v _src _ov <<<"$row"
    printf ' `%s`' "$v"
  done
  echo
  echo
} > "$ENTRY"

if [ -f "$CHANGELOG" ]; then
  TMP="$(mktemp)"
  # drop any existing block for this EXACT version (header "## <VERSION> ..."),
  # the trailing space in the match guards 1.1 vs 1.10
  awk -v ver="## $VERSION " '
    /^## /{ skip = (index($0, ver) == 1) }
    !skip
  ' "$CHANGELOG" > "$TMP"
  {
    echo "$CL_TITLE"; echo
    cat "$ENTRY"
    awk '/^## /{p=1} p' "$TMP"   # all surviving older entries, from first "## " on
  } > "$CHANGELOG"
  rm -f "$TMP"
else
  { echo "$CL_TITLE"; echo; cat "$ENTRY"; } > "$CHANGELOG"
fi
rm -f "$ENTRY"
info "Changelog.md (${VERSION} entry on top)"

# --- Marketplace edition (internals hidden) ---------------------------------
# A SECOND build off the same source for the MQL5 Market: technical strategy
# params are hidden (fixed) by swapping in Inputs.release.mqh for the compile,
# and its .set files are filtered to the user-facing keys only. The dev source
# is restored immediately after (trap-guarded). Variants come from
# release.market.conf (falls back to release.conf). Skipped if there is no
# Inputs.release.mqh or when --no-compile is given (needs a fresh hidden build).
if [ -f "$PUBLIC_INPUTS" ] && [ "$DO_COMPILE" -eq 1 ]; then
  step "[market] Building MQL5-Market edition (internals hidden)..."
  MKT_DIR="$REL_DIR/market"
  mkdir -p "$MKT_DIR"

  # compile with the internals hidden, capture the .ex5, then restore dev source
  INPUTS_BACKUP="$DEV_INPUTS.devbak"
  cp -f "$DEV_INPUTS" "$INPUTS_BACKUP"
  cp -f "$PUBLIC_INPUTS" "$DEV_INPUTS"
  "$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" || die "market compile failed — fix errors first"
  MKT_EX5="$MKT_DIR/$STRATEGY-Market-$VERSION.ex5"
  cp -f "$EX5_FILE" "$MKT_EX5"
  info "$STRATEGY-Market-$VERSION.ex5  (internals hidden)"
  restore_inputs                                   # dev Inputs.mqh back in place
  "$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" >/dev/null 2>&1 || true   # dev .ex5 back
  info "dev source restored + dev .ex5 rebuilt (working tree unchanged)"

  # filtered .set variants for the market edition
  MKT_CONF="$EA_DIR/release.market.conf"; [ -f "$MKT_CONF" ] || MKT_CONF="$CONF"
  declare -a MKT_SET_LINES=()
  if [ -f "$MKT_CONF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      read -r variant source rest <<<"$line"
      [ -n "$variant" ] && [ -n "$source" ] || die "bad release.market.conf line: $line"
      local_src="$EA_DIR/$source"
      [ -f "$local_src" ] || die "market source set not found: $local_src"
      out="$MKT_DIR/$STRATEGY-Market-$VERSION-$variant.set"
      cp -f "$local_src" "$out"
      if [ -n "${rest:-}" ]; then
        # shellcheck disable=SC2086
        apply_overrides "$out" $rest
      fi
      filter_set_to_visible "$out"
      info "$STRATEGY-Market-$VERSION-$variant.set  ($source${rest:+  [$rest]})"
      MKT_SET_LINES+=("$variant|$source|${rest:-—}")
    done < "$MKT_CONF"
  fi

  # market RELEASE.md
  {
    echo "# $STRATEGY (MQL5-Market edition) — release $VERSION"
    echo
    echo "- Built: \`$BUILD_DATE\` (UTC)"
    echo "- Source commit: \`$GIT_HASH\` on \`$GIT_BRANCH\`"
    echo "- EA: \`$STRATEGY-Market-$VERSION.ex5\` — strategy internals are HIDDEN (fixed);"
    echo "  only the user-facing inputs (risk, profit-taking, trading hours, news, basic"
    echo "  execution safety) appear in the dialog."
    echo "- Compiled by swapping \`Inputs.release.mqh\` in for the build; dev source untouched."
    echo "- \`.set\` files are stripped to the user-facing keys only (no internal params leaked)."
    echo
    echo "## User-facing parameter sets"
    echo
    echo "| variant | .set file | base preset | overrides |"
    echo "|---------|-----------|-------------|-----------|"
    for row in "${MKT_SET_LINES[@]}"; do
      IFS='|' read -r v src ov <<<"$row"
      echo "| $v | \`$STRATEGY-Market-$VERSION-$v.set\` | \`$src\` | $ov |"
    done
  } > "$MKT_DIR/RELEASE.md"
  info "market/RELEASE.md"
fi

echo
echo -e "${GREEN}✓ Release $VERSION packaged${NC}  ->  ${BLUE}$REL_DIR${NC}"
[ -d "${MKT_DIR:-/nonexistent}" ] && echo -e "${GREEN}✓ MQL5-Market edition${NC}  ->  ${BLUE}$MKT_DIR${NC} (internals hidden)"
echo -e "${YELLOW}note:${NC} *.ex5 is gitignored (build artifact); the .set files + RELEASE.md + Changelog.md commit normally."
