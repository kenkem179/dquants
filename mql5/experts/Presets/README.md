# Presets — organized MT5 `.set` tree (by expert)

This folder is the **one tidy place to load strategy presets from inside MT5**. It is
organized into one subfolder per Expert Advisor:

```
Presets/
  KK-MasterVP/          # XAU/BTC M3+M5 deploy + A/B (BASE / RevMpoc / XRev / 9h)
  KK-MasterVP-Monster/  # BTC M3 deploy + A/B
  KK-KenKem/            # E5 deploy presets + XAU M1 D3/D4 lock candidates
```

## These are symlinks, not copies (so nothing ever drifts)

Each `*.set` here is a **relative symlink** to the canonical source preset. The source
of truth stays where the docs, `release.conf`, and run READMEs already point:

| Expert subfolder       | source of truth                                  |
|------------------------|--------------------------------------------------|
| `KK-MasterVP/*`        | `mql5/experts/KK-MasterVP/*.set`                 |
| `KK-MasterVP-Monster/*`| `mql5/experts/KK-MasterVP-Monster/*.set`         |
| `KK-KenKem/E5-*`       | `mql5/experts/KK-KenKem/*.set`                    |
| `KK-KenKem/...M1-D3/D4*`| `research/kenkem_parity/*.set` (lock candidates) |

Edit the **source** `.set`; the view here updates for free. Never edit a file via this
folder expecting a "separate" copy — there isn't one.

## Loading in MetaTrader 5

`Presets/` is symlinked into the MT5 Strategy-Tester preset directory:

```
MQL5/Profiles/Tester/dquants  ->  dquants/mql5/experts/Presets
```

In the Strategy Tester → **Inputs** tab → **Load**, open `dquants/<expert>/` and pick the
`.set`. (`Profiles/Tester` is itself a symlink into the `kenkem` repo — that's expected;
the `dquants` link lands inside it.)

## Regenerating

After a fresh clone, after adding a new deploy `.set` to an EA folder, or if the MT5 link
goes missing, run:

```bash
./scripts/sync_presets.sh   # idempotent — rebuilds this tree + the MT5 Tester symlink
```

## Conventions for the next agent

- **New deploy/A-B preset** → drop the real `.set` in the **EA folder** (or
  `research/kenkem_parity/` for KenKem lock candidates), then run `sync_presets.sh`.
- Keep the EA folders as source of truth (release tooling reads `.set` from there).
- Pure sweep/parity intermediates (`research/optimization/`, `cpp_core/tools/`,
  `**/mt5_runs/`) are **not** surfaced here — only user-facing deploy presets are.
