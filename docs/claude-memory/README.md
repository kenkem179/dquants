# Claude Code memory snapshot

This folder is a **version-controlled snapshot** of Claude Code's project memory for dquants, so it can
travel between machines via git. The live memory that Claude actually reads lives *outside* the repo at a
machine-specific path:

- macOS: `~/.claude/projects/-Users-<user>-Workspace-KEM-dquants/memory/`
- Windows: `%USERPROFILE%\.claude\projects\<slug>\memory\`

The `<slug>` is the repo's **absolute path with separators replaced by dashes**, so it differs per machine
(e.g. `C-Users-<user>-...-dquants`). Claude only auto-loads memory from the slug that matches the current
checkout path — copying these files in is what makes them active on a new PC.

## Restore on the other PC (one-time)

1. Start Claude Code once in this repo so it creates the project dir, OR locate
   `~/.claude/projects/<slug-for-this-repo>/`.
2. Copy every `*.md` from this folder into that project's `memory/` subdir:
   ```bash
   # macOS/Linux
   mkdir -p ~/.claude/projects/<slug>/memory
   cp docs/claude-memory/*.md ~/.claude/projects/<slug>/memory/
   ```
   ```powershell
   # Windows PowerShell
   $dest = "$env:USERPROFILE\.claude\projects\<slug>\memory"
   New-Item -ItemType Directory -Force $dest
   Copy-Item docs\claude-memory\*.md $dest
   ```
3. `MEMORY.md` is the index Claude loads each session; the other files are the individual facts it links to.

## Keeping it in sync

This snapshot is updated manually (it is a copy, not a symlink). Re-run the copy from the live `memory/`
dir into `docs/claude-memory/` before pushing whenever memory changes, and copy back after pulling on a
new machine. The live dir is the source of truth on whichever machine you're actively working on.

## Not in git (regenerate on the new PC)

Large derived data is gitignored and will NOT transfer: `data/processed/*.parquet`,
`cpp_core/tools/*.csv` (tick/bar/trace CSVs), and the raw `data/{btcusd,xauusd}/*.csv`. Rebuild the tick
and bar CSVs from the raw feed with `cpp_core/tools/common/export_ticks.py` / `export_bars.py` once the
raw `data/` is present on the new machine. C++ binaries rebuild with `make -C cpp_core`.
