# Claude Code memory (version-controlled copy)

These are the auto-memory facts Claude Code accumulated for this project. The **live**
copy Claude reads/writes lives outside the repo at:

    ~/.claude/projects/<this-repo-path-with-slashes-as-dashes>/memory/

This directory is a git-tracked mirror so the knowledge transfers across machines.

## On a new machine (after `git clone`)

```bash
scripts/sync-claude-memory.sh restore   # copies these files into the live location
```

Then start Claude Code in this repo and the memory is loaded.

## When memory changes during work

Claude writes to the *live* location, not here. Before committing, mirror it back:

```bash
scripts/sync-claude-memory.sh backup
git add .claude/memory && git commit -m "Update Claude memory"
```

`scripts/sync-claude-memory.sh status` shows any drift between the two.

## One-time local setup (not committed)

Claude needs read access to the sibling source-of-truth repo `kenkem`. This is a
machine-local permission, so it is **not** committed. On the new machine, add it to
`.claude/settings.local.json` (adjust the path if the repo lives elsewhere):

```json
{ "permissions": { "additionalDirectories": ["/Users/tokyotechies/Workspace/KEM/kenkem"] } }
```

Also remember to clone the `kenkem` repo itself — `CLAUDE.md` treats its MQL5
sources as the authoritative strategy spec.

> Note: the slug is derived from the repo's absolute path, so the sync script
> computes it dynamically — cloning to a different path still works.
