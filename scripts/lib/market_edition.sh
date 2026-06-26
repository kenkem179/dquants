# shellcheck shell=bash
# ----------------------------------------------------------------------------
# Shared MQL5-Market edition helpers — sourced by make_release.sh AND
# make_account_releases.sh so both produce the SAME marketplace binary.
#
# The MARKETPLACE edition hides strategy internals: only user-facing knobs show
# in the MT5 Inputs dialog; everything else is fixed inside the .ex5. There are
# two mechanisms, auto-detected per EA:
#
#   A. SINGLE-SOURCE  (KK-MasterVP) — the dev Inputs.mqh is curated BY HAND: the
#      `input` keyword in the live source IS the visibility control (no `input`
#      => fixed compiled-in global => hidden). Nothing to transform; the dev
#      build already IS the market build. Visible keys = the `input Inp*` lines.
#      STANDING RULE: never expose an input param OR a comment a user can't
#      understand — keep visible knobs + descriptions plain and user-friendly.
#
#   B. WHITELIST-STRIP (KK-KenKem) — release.market.whitelist lists the
#      dialog-visible KEYs; every other `input` is stripped to a fixed global
#      (hidden) and the validated lock's .set values are baked in as the new
#      compiled-in defaults. Visible keys = the whitelist.
#
# An EA opts into a market edition by providing release.market.conf and/or
# release.market.whitelist. Approach-B mutates dev source in place; every file
# touched is backed up to <file>.devbak and its path is appended to the bash
# array named by the caller (bash 3.2: no namerefs, so we append via eval) — the
# caller restores them in its EXIT/INT/TERM trap so a build NEVER leaves the
# working tree mutated.
#
# NOTE ON THE C++ ENGINE: the `input` keyword is PURELY MT5-dialog presentation.
# The dquants C++ engine has its own param system and sweeps EVERY param
# regardless of whether the mirrored MQL `input` keyword is present. Hiding a
# param for the marketplace does NOT remove it from sweeps.
# ----------------------------------------------------------------------------

# mkt_has_edition <EA_DIR> -> 0 if the EA ships a marketplace edition
mkt_has_edition() {
  [ -f "$1/release.market.conf" ] || [ -f "$1/release.market.whitelist" ]
}

# mkt_uses_whitelist <EA_DIR> -> 0 if approach B (whitelist present), else 1
mkt_uses_whitelist() { [ -f "$1/release.market.whitelist" ]; }

# mkt_has_forcehide <EA_DIR> -> 0 if the EA ships a release.market.forcehide list
#   (single-source targeted "hide-and-hard-code" of specific keys for the market
#   edition ONLY — e.g. force InpNotifyMode=2 so marketplace users can't resell
#   full SL/TP signals, while the dev/personal build keeps the key configurable).
mkt_has_forcehide() { [ -f "$1/release.market.forcehide" ]; }

# mkt_needs_transform <EA_DIR> -> 0 if the market build must mutate+recompile dev
#   source (whitelist strip OR force-hide), vs a pure single-source copy.
mkt_needs_transform() { mkt_uses_whitelist "$1" || mkt_has_forcehide "$1"; }

# _mkt_forcehide_keys <EA_DIR> -> print the force-hidden keys, one per line.
_mkt_forcehide_keys() {
  local fh="$1/release.market.forcehide"
  [ -f "$fh" ] || return 0
  sed -E 's/#.*//' "$fh" | grep -E '=' | sed -E 's/=.*//; s/[[:space:]]//g' | grep -v '^$' || true
}

# mkt_visible_keys <EA_DIR> -> print the dialog-visible Inp* keys, one per line
#   approach B: the whitelist entries; approach A: whatever still carries `input`
#   in the live dev source (the user's hand-curated visibility), MINUS any keys
#   force-hidden for the marketplace (so they are also dropped from the .set).
mkt_visible_keys() {
  local ea="$1" wl="$1/release.market.whitelist"
  local keys
  if [ -f "$wl" ]; then
    keys="$(grep -vE '^[[:space:]]*(#|$)' "$wl" | sed -E 's/[[:space:]]//g' || true)"
  else
    keys="$(grep -rhoE '^[[:space:]]*input[[:space:]]+[A-Za-z_]+[[:space:]]+Inp[A-Za-z0-9_]+' \
      "$ea"/*.mqh "$ea"/*.mq5 2>/dev/null | awk '{print $NF}' || true)"
  fi
  # Force-hidden keys are never dialog-visible (and must be dropped from the .set)
  # even when listed in the whitelist (where they appear only so the force-hide
  # pass can find + bake them). Subtract them in BOTH branches.
  if mkt_has_forcehide "$ea"; then
    local hidef; hidef="$(mktemp)"
    _mkt_forcehide_keys "$ea" > "$hidef"
    printf '%s\n' "$keys" | grep -vxF -f "$hidef" || true   # empty hidef -> keeps all
    rm -f "$hidef"
  else
    printf '%s\n' "$keys"
  fi
}

# _mkt_push_backup <array_name> <path> : back up <path> to <path>.devbak and
#   append the backup path to the named array (bash-3.2-safe).
_mkt_push_backup() {
  local arr="$1" path="$2"
  cp -f "$path" "$path.devbak"
  eval "$arr+=(\"$path.devbak\")"
}

# mkt_apply_hiding <EA_DIR> <backup_array_name>
#   Mutates dev source in place for the marketplace build; backups pushed to the
#   named array (caller restores via its trap). Two composable transforms:
#     - whitelist (approach B): strip non-whitelisted `input`s + bake the lock.
#     - force-hide (approach A or B): strip `input` from listed keys + hard-code
#       their value (release.market.forcehide). Applied last so it always wins.
#   A pure single-source EA with neither file is a no-op.
mkt_apply_hiding() {
  local ea="$1" arr="$2"
  if mkt_uses_whitelist "$ea"; then
    _mkt_apply_whitelist "$ea" "$arr" || return 1
  fi
  _mkt_apply_forcehide "$ea" "$arr" || return 1
  return 0
}

# _mkt_apply_forcehide <EA_DIR> <backup_array_name>
#   For every "KEY=VAL" in release.market.forcehide: find the file declaring
#   `input <type> KEY = ...;`, back it up, then rewrite that line WITHOUT `input`
#   (=> hidden compiled-in global) and with VAL as the baked value. The key stays
#   `input` (visible + configurable) in the unmodified dev/personal build.
_mkt_apply_forcehide() {
  local ea="$1" arr="$2"
  local fh="$ea/release.market.forcehide"
  [ -f "$fh" ] || return 0

  local map; map="$(mktemp)"
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                                  # strip inline comment
    line="$(printf '%s' "$line" | tr -d '[:space:][:cntrl:]')"
    [ -z "$line" ] && continue
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    [ -n "$key" ] && [ -n "$val" ] && printf '%s\t%s\n' "$key" "$val" >> "$map"
  done < "$fh"
  [ -s "$map" ] || { rm -f "$map"; return 0; }

  local keyre; keyre="$(cut -f1 "$map" | paste -sd'|' -)"
  local files f tgt
  files="$(cd "$ea" && grep -rlE "^[[:space:]]*input[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+($keyre)[[:space:]]*=" \
            --include=*.mqh --include=*.mq5 --exclude-dir=releases . 2>/dev/null | sed 's|^\./||' | sort -u || true)"
  for f in $files; do
    tgt="$ea/$f"
    _mkt_push_backup "$arr" "$tgt"
    awk -v MAP="$map" '
      BEGIN {
        while ((getline m < MAP) > 0) {
          ti=index(m,"\t"); if (ti==0) continue
          k=substr(m,1,ti-1); v=substr(m,ti+1)
          gsub(/[ \t\r]/,"",k); sub(/[\r]+$/,"",v)
          if (k!="") force[k]=v
        }
      }
      {
        if (match($0, /^[ \t]*input[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) {
          lead=$0; sub(/[^ \t].*$/,"",lead)
          rest=substr($0,length(lead)+1)
          sub(/^input[ \t]+/,"",rest)
          split(rest,tk,/[ \t]+/); name=tk[2]; sub(/=.*/,"",name)   # handle "name= val" (no space)
          if (name in force) {
            eq=index(rest,"="); semi=index(rest,";")
            if (semi>0) {
              pre=substr(rest,1,eq); tail=substr(rest,semi)
              print lead pre " " force[name] tail          # no "input " => hidden, value baked
              next
            }
          }
        }
        print $0
      }
    ' "$tgt" > "$tgt.bk" && mv -f "$tgt.bk" "$tgt"
  done
  rm -f "$map"
}

# _mkt_apply_whitelist <EA_DIR> <backup_array_name> : approach B (strip non-
#   whitelisted `input`s to fixed globals + bake the locked .set defaults).
_mkt_apply_whitelist() {
  local ea="$1" arr="$2"
  local wl="$ea/release.market.whitelist"

  # optional "# bake_defaults_from: <set>" directive -> freeze hidden params at
  # the validated lock instead of dev defaults
  local bake_set
  bake_set="$(grep -E '^[[:space:]]*#[[:space:]]*bake_defaults_from:' "$wl" \
              | head -1 | sed -E 's/.*bake_defaults_from:[[:space:]]*//' | tr -d '[:space:]' || true)"

  local wlkeys; wlkeys="$(mktemp)"
  grep -vE '^[[:space:]]*(#|$)' "$wl" | sed -E 's/[[:space:]]//g' > "$wlkeys"

  # every input-declaring source under the EA dir (relative paths, no spaces)
  local files
  files="$(cd "$ea" && grep -rlE '^[[:space:]]*input[[:space:]]' \
            --include=*.mqh --include=*.mq5 --exclude-dir=releases . | sed 's|^\./||' | sort)"
  local f
  for f in $files; do _mkt_push_backup "$arr" "$ea/$f"; done

  # locked defaults to bake, as KEY<TAB>VAL (only primitive numeric/bool decls
  # are rewritten by the awk below — enums/strings keep their dev defaults).
  local bk; bk="$(mktemp)"
  if [ -n "$bake_set" ]; then
    [ -f "$ea/$bake_set" ] || { rm -f "$wlkeys" "$bk"; echo "bake_defaults_from set not found: $ea/$bake_set" >&2; return 1; }
    local key val
    while IFS='=' read -r key val || [ -n "$key" ]; do
      case "$key" in ''|\#*|\;*) continue ;; esac
      key="$(printf '%s' "$key" | tr -d '[:space:][:cntrl:]')"
      val="$(printf '%s' "$val" | tr -d '[:cntrl:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
      [ -n "$key" ] && [ -n "$val" ] || continue
      printf '%s\t%s\n' "$key" "$val" >> "$bk"
    done < "$ea/$bake_set"
  fi

  local tgt
  for f in $files; do
    tgt="$ea/$f"
    awk -v WL="$wlkeys" -v BK="$bk" '
      BEGIN {
        while ((getline k < WL) > 0) { gsub(/[ \t\r]/,"",k); if (k!="") wl[k]=1 }
        while ((getline b < BK) > 0) {
          ti=index(b,"\t"); if (ti==0) continue
          bkk=substr(b,1,ti-1); bkv=substr(b,ti+1)
          gsub(/[ \t\r]/,"",bkk); sub(/[\r]+$/,"",bkv)
          if (bkk!="") bake[bkk]=bkv
        }
        np=split("double float int uint long ulong short ushort char uchar bool",pp," ")
        for (i=1;i<=np;i++) prim[pp[i]]=1
      }
      /^[ \t]*input[ \t]+group[ \t]/ { pg=$0; hg=1; next }
      {
        if (match($0, /^[ \t]*(input[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) {
          lead=$0; sub(/[^ \t].*$/,"",lead)
          rest=substr($0,length(lead)+1)
          if (rest ~ /^input[ \t]+/) sub(/^input[ \t]+/,"",rest)
          split(rest,tk,/[ \t]+/); type=tk[1]; name=tk[2]; sub(/=.*/,"",name)   # handle "name= val" (no space)
          eq=index(rest,"="); semi=index(rest,";")
          if (semi==0) { print $0; next }
          pre=substr(rest,1,eq); tail=substr(rest,semi)
          curval=substr(rest,eq+1,semi-eq-1); newval=curval
          if ((type in prim) && (name in bake)) newval=" " bake[name]
          vis=(name in wl)
          if (vis && hg) { print pg; hg=0 }
          print lead (vis ? "input " : "") pre newval tail
          next
        }
        print $0
      }
    ' "$tgt" > "$tgt.bk" && mv -f "$tgt.bk" "$tgt"
  done
  rm -f "$wlkeys" "$bk"
}
