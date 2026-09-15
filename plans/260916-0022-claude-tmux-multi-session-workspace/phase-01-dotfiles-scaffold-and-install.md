# Phase 01 — Dotfiles scaffold, config, install.sh

## Context Links
- [plan.md](./plan.md), [brainstorm](../reports/brainstorm-260916-claude-tmux-workspace-setup.md)
- Existing dotfiles: `/home/tun/dotfiles` (stow layout; `~/.config/nvim -> ../dotfiles/nvim/.config/nvim`)
- GNU stow manual (`--no-folding`, `--restow`)

## Overview
- Date: 2026-09-16
- Description: Create stow package layout for all deliverables, cw config template, idempotent `install.sh` usable on both machines.
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Dotfiles already use GNU stow (folded dir symlink for nvim). Reuse stow; do not invent a symlinker.
- `~/.local`, `~/.config` shared with other tools → stow with `--no-folding` so stow never turns `~/.local/lib` etc. into a symlink into dotfiles.
- nvim and tmux are already stowed folded (`~/.config/nvim` and `~/.config/tmux` are dir symlinks into dotfiles, as of 2026-09-16). Keep both folded (skip `--no-folding` for them) to avoid unfold churn; `--no-folding` only for new pkgs touching `~/.local`.
- `~/.claude/settings.json` is written by Claude Code itself → never symlink; merge hooks with jq (script built in phase 4, called by install.sh).
- `~/.config/cw/config` is machine-specific (CW_ROOT differs) → copy template once, never symlink/overwrite.

## Requirements
- Functional: `./install.sh [pkg...]` (default `cw tmux bazel`; `nvim` opt-in), backs up conflicting real files to `~/.dotfiles-backup/<ts>/`, re-runnable with no diff, creates cw config from template if missing, runs hook merge, warns if `~/.local/bin` not in PATH, reports missing deps.
- Non-functional: bash, `set -euo pipefail`, <200 lines, shellcheck clean, no secrets, works w/o sudo.

## Architecture
```
/home/tun/dotfiles/
  install.sh                         # entry
  scripts/merge-claude-hooks.sh      # phase 4
  templates/cw-config.example        # copied to ~/.config/cw/config
  templates/claude-hooks.json        # phase 4
  templates/CLAUDE.md.template       # phase 5
  cw/.local/bin/{cw,cw-tmux-state}   # phases 2-4
  cw/.local/lib/cw/*.sh              # phases 2-3
  tmux/.config/tmux/tmux.conf        # phase 4
  bazel/.bazelrc  bazel/.local/bin/bt  # phase 5
  nvim/.config/nvim/...              # existing (+diffview phase 4)
  tests/                             # phase 6
  README.md                          # usage cheatsheet
```
Install flow: check deps → for each pkg: backup conflicts → `stow [--no-folding] --restow -d "$DOTFILES" -t "$HOME" pkg` → config template → merge hooks → PATH check.

Config template (`templates/cw-config.example`), sourced by cw (env vars win, see phase 2):
```bash
CW_ROOT="$HOME/cw"            # sessions: $CW_ROOT/<repo>/<id>
CW_REMOTE=origin
# CW_BASE=main                # else git config cw.base / origin/HEAD / main / master
CW_CLAUDE_CMD=claude
CW_FZF=fzf
CW_SIZE_WARN_GB=100           # cw ls --size warning per repo
# CW_BAZEL_OUTPUT_USER_ROOT="$HOME/.cache/bazel/_bazel_$USER"
```

## Related Code Files
- Create: `/home/tun/dotfiles/install.sh`
- Create: `/home/tun/dotfiles/templates/cw-config.example`
- Create: `/home/tun/dotfiles/README.md` (short: install, cw commands, keybinds, rollout)
- Create dirs: `/home/tun/dotfiles/{cw/.local/bin,cw/.local/lib/cw,tmux/.config/tmux,bazel/.local/bin,scripts,templates,tests}`
- Modify: none. Delete: none.

## Implementation Steps
1. Create dir skeleton above (empty placeholder files not needed; stow ignores empty dirs).
2. `install.sh`:
   - `DOTFILES="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"`.
   - `need git tmux jq stow` → die with install hint; `want fzf lazygit shellcheck bats bazel` → warn only.
   - tmux version check >=3.2 (popup) → warn.
   - `backup_conflicts pkg`: `find "$DOTFILES/$pkg" -type f -o -type l` → rel path → target `$HOME/$rel`; if target exists and `readlink -f target` not under `$DOTFILES` → `mkdir -p` backup dir, `mv`.
   - Stow: `nvim` without `--no-folding`, others with it; always `--restow` (idempotent).
   - `[ -f ~/.config/cw/config ] || install -Dm600 templates/cw-config.example ~/.config/cw/config`.
   - If `scripts/merge-claude-hooks.sh` exists → run it (phase 4).
   - `case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn ...`.
   - Print summary (stowed pkgs, backups made).
3. README: 30–60 lines cheatsheet.
4. Dry run on laptop into temp HOME: `HOME=$(mktemp -d) ./install.sh cw tmux` (phase 6 automates).

## Todo List
- [ ] Skeleton dirs
- [ ] install.sh (deps, backup, stow, config, hooks merge call, PATH check)
- [ ] templates/cw-config.example
- [ ] README.md
- [ ] shellcheck install.sh; run twice in temp HOME, second run no changes

## Success Criteria
- Fresh temp HOME: symlinks created, config copied, exit 0.
- Second run: no new backups, no errors.
- Existing real `~/.config/tmux/tmux.conf` gets backed up, not lost.

## Risk Assessment
- stow folding into shared dirs → `--no-folding` for non-nvim pkgs.
- Restowing nvim alters existing layout → nvim opt-in only.
- Second machine lacks stow → die with hint (`apt/dnf/pacman install stow`).

## Security Considerations
- No secrets in repo; config file created 0600; backups stay in HOME.
- install.sh never uses sudo; never `rm` user files (move to backup).

## Next Steps
- Phase 2 fills `cw` package. Phase 4 adds hook merge script consumed here.
