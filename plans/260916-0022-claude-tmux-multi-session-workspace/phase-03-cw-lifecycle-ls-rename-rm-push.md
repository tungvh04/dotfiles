# Phase 03 — cw `ls` / `rename` / `rm` / `new --from` / `push`

## Context Links
- [plan.md](./plan.md), [phase-02](./phase-02-cw-core-new-go-close.md)
- Gerrit: `git push origin HEAD:refs/for/<branch>`, commit-msg hook `https://<gerrit>/tools/hooks/commit-msg`
- Bazel output layout: output_base = `<output_user_root>/<md5(workspace path)>` (bazel.build/remote/output-directories)
- Existing Gerrit API skill on monorepo box (comment loop, reused — not reimplemented)

## Overview
- Date: 2026-09-16
- Description: Lifecycle commands on top of phase-2 libs; Gerrit push safety; Bazel disk guidance.
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Dir never moves on rename: Bazel output_base keyed by md5(path), Claude history keyed by path. Rename = label + window name (+ optional branch).
- `cw rm` must also drop Bazel output_base, else GBs orphaned: run `bazel clean --expunge` in the worktree before removal (skip with `--keep-cache` or if bazel missing → warn with path).
- "Unpushed" in Gerrit flow can't use `origin/<branch>`. Record last pushed sha in `branch.<b>.cwpushed` on `cw push`; unpushed = `git cherry @{u} HEAD` has `+` lines AND HEAD != cwpushed. Patch-equivalent merged commits (`-`) count as pushed.
- `--from` recycle keeps dir → warm output_base on disk (analysis cache cold if server reaped; action outputs reused).
- Computing output_base size needs no Bazel server: md5 of realpath. Caveat: repo/home rc overriding `--output_user_root`/`--output_base` → `CW_BAZEL_OUTPUT_USER_ROOT`.
- `du` on big output bases is slow → size only behind `--size`.
- Worktrees share `$(git rev-parse --git-common-dir)/hooks` → one commit-msg hook install covers all sessions (unless `core.hooksPath` set).

## Requirements
- `cw ls [--size] [--plain]`: all repos under `$CW_ROOT`. Columns: `REPO/NAME  BRANCH  CHANGE  AGE  STATE  [SIZE]`. CHANGE = first 9 chars of `Change-Id` trailer of HEAD if HEAD ahead of `@{u}`, else `-`. AGE = `git log -1 --format=%cr`. STATE = `@claude_state` emoji if window open, `open` if open w/o state, `closed`. `--size`: worktree `du -sh` + Bazel output_base size (bazel repos); per-repo total; warn if > `CW_SIZE_WARN_GB`, suggest `cw rm`/`cw new --from`. `--plain` = TSV + dir column (fzf input). No `git status` in ls (slow on monorepo).
- `cw rename <name> <new> [--branch]`: validate new; collision check within repo; set label (unset if new == id); `tmux rename-window` if open; `--branch`: `git branch -m old new` (refuse if target exists). Never touch dir. Print hint: run `/rename <new>` inside Claude if it is running (verify command exists).
- `cw rm <name> [--force] [--keep-cache]`: refuse if window open (tell `cw close`) unless `--force` (then kill); refuse if dirty (`git status --porcelain` non-empty, untracked included) or unpushed unless `--force`; bazel repo → `bazel clean --expunge` in dir; `git worktree remove [--force] dir`; `git branch -D b`; `rmdir` empty repo dir.
- `cw new <name> [repo] --from <old>`: old in same repo, window closed, clean + pushed (or `--force`); in old dir: `fetch_base`; `git switch --track -c <name> origin/<base>`; `git branch -D <oldbranch>`; `label_set dir name name` (dir id stays old id → label required); window + fresh claude.
- `cw new` tip (bazel repo only, cheap): if repo has closed sessions → `tip: cw new <name> --from <closed>` reuses warm build.
- `cw push [--chain] [-- extra git push args]`: run in session dir (cwd). Must be on branch w/ upstream; commits ahead N>=1 else die; N>1 and no `--chain` → die (1 session = 1 change); every commit in `@{u}..HEAD` has `Change-Id:` trailer else die with hook install hint; warn if dirty; `git push "$remote" HEAD:refs/for/"$base" "$@"`; on success `git config branch.$b.cwpushed "$(git rev-parse HEAD)"`; print Gerrit URL lines from push output (already in stderr). Comment loop: document "use Gerrit skill", no code.

## Architecture
```
cw/.local/lib/cw/cw-cmd-ls.sh          cw_ls_rows (TSV), cmd_ls (format/column), size helpers (~140)
cw/.local/lib/cw/cw-cmd-rename-rm.sh   cmd_rename, cmd_rm, bazel_expunge (~130)
cw/.local/lib/cw/cw-cmd-push.sh        cmd_push, check_change_ids (~80)
cw/.local/lib/cw/cw-cmd-new.sh         + recycle_from (keep file <200; else split cw-cmd-new-from.sh)
cw/.local/lib/cw/cw-session.sh         is_dirty, is_unpushed (from phase 2 file)
```
Snippets:
```bash
change_id() { git -C "$1" log -1 --format='%(trailers:key=Change-Id,valueonly)' | head -c 9; }
bazel_output_base() { local root="${CW_BAZEL_OUTPUT_USER_ROOT:-$HOME/.cache/bazel/_bazel_$USER}"
  printf '%s/%s' "$root" "$(printf '%s' "$(realpath "$1")" | md5sum | cut -d' ' -f1)"; }
is_unpushed() { local d=$1 b; b=$(session_branch "$d")
  git -C "$d" cherry '@{u}' HEAD 2>/dev/null | grep -q '^+' || return 1
  [ "$(git -C "$d" rev-parse HEAD)" != "$(git -C "$d" config "branch.$b.cwpushed" || true)" ]; }
missing_change_ids() { git log --format='%H%x00%(trailers:key=Change-Id,valueonly)' '@{u}..HEAD' | awk -F'\0' '$2==""{print $1}'; }
```
Hook hint text:
```
commit(s) lack Change-Id. Install hook once per repo (shared by all worktrees):
  f="$(git rev-parse --git-common-dir)/hooks/commit-msg"; curl -fsSLo "$f" https://<gerrit>/tools/hooks/commit-msg && chmod +x "$f"
then: git commit --amend --no-edit
```
Relation-chain rule (doc in README + CLAUDE.md template): one session = one branch = one change; iterate by `git commit --amend` (keep Change-Id); new independent work = new session.

## Related Code Files
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-ls.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-rename-rm.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-push.sh`
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-new.sh` (`--from`, bazel tip)
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-session.sh` (`is_dirty`, `is_unpushed`)
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-go-close.sh` (use full `cw_ls_rows`)
- Modify: `/home/tun/dotfiles/cw/.local/bin/cw` (unstub commands)
- Modify: `/home/tun/dotfiles/README.md` (commands, Gerrit rule, Bazel disk guidance)

## Implementation Steps
1. `cw_ls_rows`: iterate sessions, build TSV; state via one `tmux list-windows -a -F '#{@cw_path}\t#{@claude_state}'` call cached in assoc array (not per-row tmux calls).
2. `cmd_ls`: `--plain` → raw TSV; else `column -t -s $'\t'` with header; `--size` adds columns and per-repo total + warning (`du -sb`, human via `numfmt --to=iec`).
3. `cmd_rename`: resolve, validate, collision (`resolve_session` for new name in same repo must fail; `--branch` → `show-ref` check), label, window rename, optional `branch -m` (label config moves with section; re-set label after to be safe).
4. `cmd_rm`: guards in order window → dirty → unpushed (after quiet `fetch_base`, warn on failure) → expunge → worktree remove → branch delete → cleanup empty dir. Each refusal names the override flag.
5. `recycle_from` in cmd_new: guards (same as rm minus window kill) → switch/track new branch → delete old branch → label → window.
6. `cmd_push`: guards, Change-Id check, push, record cwpushed.
7. Manual test on laptop against a local bare "gerrit-like" remote; on monorepo box against real Gerrit with a throwaway change (WIP: `%wip` push option) in phase 7.

## Todo List
- [ ] cw_ls_rows + cmd_ls (+ --plain, --size, warning)
- [ ] cmd_rename (label, window, --branch; dir untouched)
- [ ] cmd_rm (guards, bazel expunge, worktree+branch removal)
- [ ] cmd_new --from recycle + bazel tip
- [ ] cmd_push (chain guard, Change-Id check, cwpushed)
- [ ] README updates; shellcheck; each lib <200 lines

## Success Criteria
- `cw ls` lists sessions from 2+ repos in <1s for ~20 sessions (no --size).
- rename: dir path + inode unchanged; window name + label updated; `--branch` renames branch, upstream kept.
- rm refuses dirty/unpushed/open without `--force`; with `--force` dir, branch, output_base gone.
- `--from`: same dir, new branch at `origin/<base>`, old branch deleted.
- push: refs/for/<base> updated; missing Change-Id / chain → nonzero with hint.

## Risk Assessment
- `cw rm --force` data loss → explicit flag, message lists what is lost (dirty files, unpushed commits count) before acting.
- output_base md5 mismatch (symlinked CW_ROOT, custom output_user_root) → size shows `?`; expunge via `bazel clean` is path-agnostic, so rm still correct.
- `bazel clean --expunge` slow/starts JVM → acceptable on rm; `--keep-cache` escape.
- `git cherry` false "unpushed" after Gerrit rebase-with-conflict merge → user uses `--force`; message explains.

## Security Considerations
- `--force` paths never `rm -rf` outside `$CW_ROOT/<repo>/<id>`; assert dir prefix before removal.
- Push only to configured remote; extra args passed as array (no eval).
- Gerrit credentials untouched (git/ssh config handles auth).

## Next Steps
- Phase 4 provides `@claude_state` used by ls STATE column. Phase 6 tests all guards.
