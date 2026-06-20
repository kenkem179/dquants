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
# VER comes from `#property version "<major>.<minor>"` in the .mq5 (MQL5 rule).
# Bump major for a real strategy change, minor for a fine-tune, then re-run.
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
# Usage:
#   scripts/make_release.sh <STRATEGY> [--no-compile]
#   STRATEGY  e.g. KK-MasterVP  (folder name under mql5/experts/)
#   --no-compile  reuse the existing dev .ex5 instead of recompiling
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
[ -n "$STRATEGY" ] || die "usage: make_release.sh <STRATEGY> [--no-compile]"
DO_COMPILE=1
[ "${2:-}" = "--no-compile" ] && DO_COMPILE=0

EA_DIR="$EXPERTS_DIR/$STRATEGY"
MQ5_FILE="$EA_DIR/$STRATEGY.mq5"
EX5_FILE="$EA_DIR/$STRATEGY.ex5"
[ -d "$EA_DIR" ]  || die "strategy folder not found: $EA_DIR"
[ -f "$MQ5_FILE" ] || die "EA source not found: $MQ5_FILE"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  dquants release — $STRATEGY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 1) Version from #property version (MQL5 <major>.<minor>) --------------------
step "[1/5] Reading version..."
VERSION="$(grep -E '^#property[[:space:]]+version' "$MQ5_FILE" \
            | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
[ -n "$VERSION" ] || die "no '#property version \"x.y\"' found in $MQ5_FILE"
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+$' \
  || die "version '$VERSION' is not <major>.<minor> (MQL5 rule)"
info "version $VERSION"

# 2) Compile (or reuse) the DEV EA -------------------------------------------
if [ "$DO_COMPILE" -eq 1 ]; then
  step "[2/5] Compiling dev EA..."
  "$SCRIPT_DIR/compile_mql5.sh" "$MQ5_FILE" || die "compile failed — fix errors first"
else
  step "[2/5] Skipping compile (--no-compile)"
fi
[ -f "$EX5_FILE" ] || die "no .ex5 — compile the dev EA first (drop --no-compile)"
info "dev build: $STRATEGY.ex5"

# 3) Create the versioned release folder -------------------------------------
step "[3/5] Creating releases/$VERSION/ ..."
REL_DIR="$EA_DIR/releases/$VERSION"
mkdir -p "$REL_DIR"
REL_EX5="$REL_DIR/$STRATEGY-$VERSION.ex5"
cp -f "$EX5_FILE" "$REL_EX5"
info "$STRATEGY-$VERSION.ex5"

# 4) Package the .set variants ------------------------------------------------
step "[4/5] Packaging parameter sets..."
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
step "[5/5] Writing RELEASE.md..."
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

echo
echo -e "${GREEN}✓ Release $VERSION packaged${NC}  ->  ${BLUE}$REL_DIR${NC}"
echo -e "${YELLOW}note:${NC} *.ex5 is gitignored (build artifact); the .set files + RELEASE.md commit normally."
