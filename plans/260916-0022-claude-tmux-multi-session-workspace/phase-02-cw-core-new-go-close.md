# Phase 02 — cw core + `new` / `go` / `close`

## Context Links
- [plan.md](./plan.md), [phase-01](./phase-01-dotfiles-scaffold-and-install.md), [phase-03](./phase-03-cw-lifecycle-ls-rename-rm-push.md)
- git-worktree(1) (`add --track -b`, `list --porcelain`), tmux(1) user options `@name`, `new-window -P -F`
- `claude --help`: `-n/--name`, `-c/--continue` (verified on 2.1.272)

## Overview
- Date: 2026-09-16
- Description: Entry `cw` + shared libs (config, repo/base detection, session discovery, tmux helpers) and commands `new <name> [repo]`, `go [name]`, `close <name>`.
- Priority: P2 (core of the plan)
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Session identity = worktree dir `$CW_ROOT/<repo>/<id>`; id = name at creation, immutable. Display name = `git config branch.<b>.cwname` if set, else id. Label rides with the branch section (`git branch -m` moves it, `-D` deletes it) → zero extra state, no `extensions.worktreeConfig` side effects on the repo.
- Find windows by `@cw_path` window option (stable across renames), never by window name. tmux targets use window ids (`@12`) → names may contain anything valid.
- Start window with a shell, then `send-keys` claude → window survives Claude exit; user sees exit output.
- `git worktree add --track -b <name> <dir> origin/<base>` sets upstream → base for push later = `@{u}`, no stored base.
- Resume: `claude --continue` only if a conversation exists for the dir (`~/.claude/projects/<encoded-path>`; encoding observed `/`→`-`, assume non-alnum→`-`, verify). Otherwise plain `claude -n`.
- Not in tmux → create detached then `attach`; in tmux → `switch-client`. `-d` flag skips both (tests/scripts).
- Gerrit remotes often lack `origin/HEAD` → base fallback chain needed.

## Requirements
- `cw new <name> [repo-path] [-d]`: validate name `^[A-Za-z0-9][A-Za-z0-9_-]{0,48}$`; repo = arg or cwd (if cwd is a worktree, use main repo via common dir); refuse if branch `refs/heads/<name>` or dir exists or name already used as label in repo; fetch base (warn-only on failure, offline/SSH); create worktree; tmux session `<repo>` (sanitized) ensured; window named `<name>`, options `@cw_path`, run `$CW_CLAUDE_CMD -n <name>`; switch/attach.
- `cw go [name|repo/name] [-d]`: no arg + fzf + TTY → picker (preview: `git log --oneline -10`, `git status -s`); else print session list, exit 1. Window exists → select + switch. Missing → recreate window + resume claude.
- `cw close <name>`: kill window if present (worktree kept); idempotent message if already closed.
- Name resolution across all repos: match label/id; ambiguous → error listing `repo/name` forms.
- Non-functional: every file <200 lines, `set -euo pipefail`, errors to stderr with `cw: ` prefix, exit codes 0 ok / 1 user error / 2 usage.

## Architecture
```
cw/.local/bin/cw                       dispatch + usage (~70 lines)
cw/.local/lib/cw/cw-common.sh          die/warn, load_config, validate_name, repo_main_dir,
                                       repo_name, detect_base, is_bazel_repo (~120)
cw/.local/lib/cw/cw-session.sh         list_session_dirs, session_field (branch/name/repo),
                                       resolve_session, label get/set, is_dirty, is_unpushed (~150)
cw/.local/lib/cw/cw-tmux.sh            tmux_session_ensure, window_for_path, window_create,
                                       claude_start_cmd, focus_window, window_state (~120)
cw/.local/lib/cw/cw-cmd-new.sh         cmd_new (+ --from in phase 3) (~130)
cw/.local/lib/cw/cw-cmd-go-close.sh    cmd_go, pick_session, cmd_close (~100)
phase 3: cw-cmd-ls.sh, cw-cmd-rename-rm.sh, cw-cmd-push.sh
```
Entry resolves libs through stow symlink:
```bash
CW_LIB="$(dirname "$(readlink -f "$0")")/../lib/cw"
for f in "$CW_LIB"/cw-*.sh; do . "$f"; done
case "${1:-}" in new|go|close|ls|rename|rm|push) cmd="$1"; shift; "cmd_$cmd" "$@";; *) usage; exit 2;; esac
```
Config load (env wins over file):
```bash
load_config() {
  local saved; saved="$(declare -p CW_ROOT CW_BASE CW_REMOTE CW_CLAUDE_CMD CW_FZF CW_SIZE_WARN_GB CW_BAZEL_OUTPUT_USER_ROOT 2>/dev/null || true)"
  [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/cw/config" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/cw/config"
  eval "$saved"
  : "${CW_ROOT:=$HOME/cw}" "${CW_REMOTE:=origin}" "${CW_CLAUDE_CMD:=claude}" "${CW_FZF:=fzf}" "${CW_SIZE_WARN_GB:=100}"
}
```
Base detection (per repo): `git config cw.base` > `$CW_BASE` > `git symbolic-ref --short refs/remotes/$CW_REMOTE/HEAD` (strip remote) > first existing of `main`, `master` on remote > die with hint `git config cw.base <branch>`.

Repo main dir: `common=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir)`; main = `dirname "$common"` (non-bare). repo name = `basename main`. Guard: if `$CW_ROOT/<repo>` has worktrees with different common dir → die (basename collision).

Session discovery: `for d in "$CW_ROOT"/*/*/; do [ -f "$d/.git" ] && ...` (a worktree has `.git` file). Fields via `git -C "$d"`: branch `symbolic-ref --short -q HEAD`, name `config branch.$b.cwname || basename`.

Window create + claude:
```bash
wid=$(tmux new-window -d -P -F '#{window_id}' -t "$sess:" -n "$name" -c "$dir")
tmux set-option -w -t "$wid" @cw_path "$dir"
tmux send-keys -t "$wid" "$(claude_start_cmd "$dir" "$name" "$resume")" Enter
# claude_start_cmd: printf '%q ' $CW_CLAUDE_CMD [--continue] -n "$name"
```
Focus: `[ -n "${TMUX:-}" ] && tmux switch-client -t "$wid" || tmux attach -t "$wid"` (skip if `-d`). `tmux_session_ensure`: `has-session -t "=$sess"` else `new-session -d -s "$sess" -c "$CW_ROOT/$repo"` (first window is a plain shell in repo root; acceptable, doubles as scratch).

Picker:
```bash
if [ -z "$name" ]; then
  if command -v "$CW_FZF" >/dev/null && [ -t 0 ] && [ -t 1 ]; then
    line=$(cw_ls_plain | "$CW_FZF" --delimiter=$'\t' --with-nth=1,2,5 \
      --preview 'git -C {6} log --oneline -10; git -C {6} status -s') || exit 1
  else cw_ls_plain | cut -f1,2,5 | column -t; echo "usage: cw go <name>" >&2; exit 1; fi
fi
```
(`cw_ls_plain` defined in phase 3 ls module; implement minimal version here, extend in phase 3.)

## Related Code Files
- Create: `/home/tun/dotfiles/cw/.local/bin/cw`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-common.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-session.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-tmux.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-new.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-go-close.sh`
- Modify/Delete: none

## Implementation Steps
1. `cw` entry: strict mode, lib loading, `load_config`, dispatch, `usage` (all 7 subcommands listed; phase-3 ones stubbed until implemented), `-h`.
2. `cw-common.sh`: `die()`, `warn()`, `load_config`, `validate_name`, `repo_main_dir`, `repo_name` (sanitize `.`/`:` → `_` for tmux session), `detect_base`, `is_bazel_repo` (`MODULE.bazel|WORKSPACE|WORKSPACE.bazel` in dir), `fetch_base` (`git fetch -q "$CW_REMOTE" "$base"` || warn).
3. `cw-session.sh`: `list_session_dirs`, `session_branch/name/repo`, `resolve_session <name|repo/name>` → prints dir or dies (0 or >1 matches), `label_set dir branch name` (unset when name == id), `claude_project_exists dir` (`[ -d "$HOME/.claude/projects/${dir//[^A-Za-z0-9]/-}" ]`).
4. `cw-tmux.sh`: functions per Architecture; `window_for_path dir` → `tmux list-windows -a -F '#{window_id} #{@cw_path}' 2>/dev/null | awk -v p="$dir" '$2==p{print $1; exit}'` (no server → empty).
5. `cw-cmd-new.sh`: parse args (`-d`, positional name, optional repo); checks; `mkdir -p "$CW_ROOT/$repo"`; `git -C main worktree add --track -b "$name" "$dir" "$CW_REMOTE/$base"`; window create (fresh claude); focus. On failure after worktree add but before window → leave worktree, print `cw go <name>` hint (no rollback magic).
6. `cw-cmd-go-close.sh`: `cmd_go` (picker/fallback, resolve, find/create window with resume flag from `claude_project_exists`), `cmd_close` (kill-window if found).
7. Manual verification in real tmux on laptop with a small repo; check `claude -n` name appears, `--continue` resumes after `cw close` + `cw go`.
8. Verify: Claude projects-dir encoding for paths with `.`/`_`; whether `--continue -n` keeps name.

## Todo List
- [ ] cw entry + usage
- [ ] cw-common.sh (config, validate, repo, base, bazel detect)
- [ ] cw-session.sh (discover, resolve, label, project-exists)
- [ ] cw-tmux.sh (ensure session, find/create window, focus)
- [ ] cmd_new (no --from yet)
- [ ] cmd_go (picker, fallback list, resume) + cmd_close
- [ ] shellcheck all; manual smoke in tmux; verify encoding + `-n` w/ `--continue`

## Success Criteria
- `cw new foo` → worktree `$CW_ROOT/<repo>/foo` on branch `foo` tracking `origin/<base>`, window `foo` running Claude, <10s (excluding fetch).
- `cw close foo; cw go foo` → window recreated, previous conversation resumed.
- `cw go` without fzf/TTY prints list, exits 1.
- Collisions (branch/dir/label) fail with clear message, nothing created.

## Risk Assessment
- Projects-dir encoding wrong → resume falls back to fresh Claude (not destructive); verify step 8.
- `send-keys` race before shell ready → tmux buffers keys to pane input; fine. If user shell rc slow, still ok.
- Repo basename collision → explicit die; user can set distinct `CW_ROOT` or rename clone.
- Detection of main repo from inside a session dir → always via `--git-common-dir`.

## Security Considerations
- Quote all vars; build claude command with `printf %q`; names validated regex (no shell/tmux metachars).
- Config file sourced = user-trusted like `.bashrc`; created 0600 in phase 1.
- No network besides `git fetch` to configured remote.

## Next Steps
- Phase 3: ls (full), rename, rm, `new --from`, push. Phase 6: tests for these paths.
