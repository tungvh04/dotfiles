# dotfiles — notes for Claude

Personal dotfiles, installed with GNU stow (`./install.sh`). Main project: `cw`, a tmux-based
replacement for Orca (parallel Claude Code sessions on git worktrees). Used on two machines:
an Arch laptop (small repos) and an Ubuntu box with a Bazel + Gerrit monorepo (local or SSH).

## Layout
- `cw/` stow pkg → `~/.local/{bin/cw, lib/cw/*.sh, share/bash-completion/completions/cw}`
- `tmux/` stow pkg → `~/.config/tmux` (folded dir symlink). Prefix `C-a`.
- `nvim/` stow pkg → `~/.config/nvim` (folded). Opt-in in install.sh.
- `templates/cw-config.example` → copied once to `~/.config/cw/config` (machine-specific, untracked)
- `plans/260916-0022-claude-tmux-multi-session-workspace/` — the plan. `plan.md` has phase status
  and "Progress notes"; read it first and update it after changes.

## cw model
One task = worktree `$CW_ROOT/<repo>/<name>` (default `~/cw`) + branch `<name>` + tmux window + Claude
conversation. tmux session = repo. State is derived from git + tmux only (no DB).
- Windows are found by window option `@cw_path`, never by name (renames are safe).
- Sessions are still found by name (`<repo>`); switching to a `@cw_repo` tag is planned (ph3).
- Resume: `cw go` recreates a closed window and runs `claude --continue -n <name>` if
  `~/.claude/projects/<realpath, non-alnum→'-'>/*.jsonl` exists.
- Repos without `origin`: the only remote is used; no remote → branch from local base.

## Working with the user
- Delivered in "stops" (A = ph1+2 done; B = ph4 Claude state in bar + nvim diff review;
  C = rest of ph3: rename, ls, --from, push; D = ph5–7 Bazel, tests, rollout). Each stop ends with
  a short "try this" checklist; the user tries it before the next stop.
- The user is new to tmux (explain concepts briefly), fluent in nvim. Prefers simple over clever
  (vim modes in fzf and a left-sidebar `C-a w` were tried and dropped).
- Repo may go public: no company names, hostnames, Gerrit URLs or internal paths in tracked files.

## Conventions
- bash, `set -euo pipefail`, files < 200 lines, kebab-case names, `cw: ` prefix on errors.
- Libs are sourced by `cw/.local/bin/cw`; add a command as `cw-cmd-<name>.sh` + dispatch case +
  usage line + README + completion.
- New file in a stow pkg → run `./install.sh cw` (or `tmux`) to link it.
- shellcheck is not installed; at least run `bash -n` on every changed script.

## Testing without touching the user's tmux / ~/cw
- Isolate: `HOME=<tmpdir>/home TMUX_TMPDIR=<tmpdir>/tmux CW_CLAUDE_CMD="echo FAKECLAUDE"` plus
  `GIT_AUTHOR_*/GIT_COMMITTER_*` (fake HOME has no git identity). Use a dir under `~/.cache`, delete after.
- Interactive bits (popups, key bindings, choose-tree, fzf, Tab completion): run an inner server
  (`tmux -L inner -f <conf>`) attached inside an outer one (`tmux -L outer`), drive with
  `send-keys` on the outer pane, read with `capture-pane -p` on the outer pane.
- Never `tmux kill-server` without `-L`/`TMUX_TMPDIR` pointing at a test server.

## Gotchas already hit
- `pipefail` + `tmux list-windows` with no server running → silent exit. Wrap: `{ tmux …|| true; } |`.
- `eval "$(declare -p VAR)"` inside a function creates locals; use `printf -v`.
- `git status --porcelain` hides gitignored files (`.env`); `cw rm` checks `--ignored` explicitly.
- `symbolic-ref --short` prints `heads/x` when a tag `x` exists; strip `refs/heads/` manually.
- bash-completion caches "no completion" per shell: already-open shells need `exec bash`.
- `choose-tree` (`C-a w`): per-level colors via `#{?pane_format,…,#{?window_format,…,…}}` work;
  list-on-top/preview-below layout is fixed; filtering out pane lines drops their windows.
- `capture-pane` does not show tree mode; capture the outer pane of a nested client instead.
