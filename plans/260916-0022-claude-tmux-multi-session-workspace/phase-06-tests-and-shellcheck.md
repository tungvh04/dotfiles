# Phase 06 — Tests (bats) + shellcheck

## Context Links
- [plan.md](./plan.md), phases [02](./phase-02-cw-core-new-go-close.md), [03](./phase-03-cw-lifecycle-ls-rename-rm-push.md), [04](./phase-04-claude-hooks-tmux-and-review-ux.md), [05](./phase-05-bazel-bt-and-claude-md-template.md), [01](./phase-01-dotfiles-scaffold-and-install.md)
- bats-core docs (`setup`, `teardown`, `run`, `$BATS_TEST_TMPDIR`); shellcheck `-x`

## Overview
- Date: 2026-09-16
- Description: Real end-to-end tests against temp git repos + isolated tmux server + stub `claude`/`bazel`; shellcheck gate. No mocks of git/tmux themselves.
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Isolate tmux with `TMUX_TMPDIR=$BATS_TEST_TMPDIR/tmux` + `unset TMUX TMUX_PANE` (same effect as `tmux -L cw-test`, zero test hooks in cw code). `teardown`: `tmux kill-server || true`.
- Temp `HOME` → no user tmux.conf / git config / Claude settings touched; tmux shell = `/bin/bash` without rc.
- Local bare repo as "Gerrit": push to `refs/for/main` just creates that ref → assert with `git -C origin.git rev-parse refs/for/main`.
- Stub `claude` records argv to `$CLAUDE_LOG` then `sleep`s → assert `-n <name>` / `--continue`; poll for file (≤5s) since started via send-keys.
- Stub `bazel` (PATH-first) logs argv, emits canned output, creates fake testlogs → tests bt and `cw rm` expunge.
- Always use `-d` on `cw new/go` in tests (no client to attach/switch).
- fzf fallback: `CW_FZF=cw-no-such-fzf` (fzf lives in /usr/bin with git, cannot drop from PATH); bats is non-TTY anyway.

## Requirements
- All tests pass locally: `tests/run-tests.sh` (shellcheck then bats). Fail on any shellcheck warning (severity warning+).
- Coverage of user-requested cases: rename keeps dir, close+go resume, rm refuses dirty, fzf-less `cw go` prints list.
- Deps: `sudo pacman -S bash-bats shellcheck` (Arch pkgs verified: `shellcheck`, bats via `bash-bats`/`bats` — confirm name at install).

## Architecture
```
tests/
  test-helper.bash          temp HOME, git identity, bare origin + clone, stubs, tmux isolation, wait_for_file
  stubs/claude              argv → $CLAUDE_LOG; sleep 3600
  stubs/bazel               argv → $BAZEL_LOG; canned output per subcommand; fake testlogs
  cw-new-go-close.bats
  cw-rename-rm-from.bats
  cw-ls-push.bats
  cw-tmux-state.bats
  merge-claude-hooks.bats
  bt.bats
  install.bats
  run-tests.sh
```
Helper sketch:
```bash
setup_env() {
  export HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/home/.config"
  export CW_ROOT="$HOME/cw" TMUX_TMPDIR="$BATS_TEST_TMPDIR/tmux" SHELL=/bin/bash
  export CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log" BAZEL_LOG="$BATS_TEST_TMPDIR/bazel.log"
  export PATH="$BATS_TEST_DIRNAME/stubs:$DOTFILES/cw/.local/bin:$DOTFILES/bazel/.local/bin:$PATH"
  unset TMUX TMUX_PANE; mkdir -p "$HOME" "$TMUX_TMPDIR"
  git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch main
}
make_repo() {  # make_repo <name> [bazel]
  git init -q --bare "$BATS_TEST_TMPDIR/$1.git"
  git clone -q "$BATS_TEST_TMPDIR/$1.git" "$BATS_TEST_TMPDIR/$1"
  [ "${2:-}" = bazel ] && touch "$BATS_TEST_TMPDIR/$1/MODULE.bazel"
  git -C "$BATS_TEST_TMPDIR/$1" add -A
  git -C "$BATS_TEST_TMPDIR/$1" commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/$1" push -q -u origin main
}
commit_with_change_id() {
  git -C "$1" commit -q --allow-empty -m "$2" -m "Change-Id: I$(head -c 20 /dev/urandom | sha1sum | cut -c1-40)"
}
```

## Test Cases
cw-new-go-close.bats
- new: dir `$CW_ROOT/app/foo` exists; branch `foo` upstream `origin/main`; tmux window `foo` with `@cw_path`; claude log has `-n foo`, no `--continue`.
- new refuses: invalid name (`a b`, `x:y`), existing branch, existing dir; nothing created.
- base: `git config cw.base dev` honored; no `origin/HEAD` → falls back to `main`.
- close keeps dir, window gone; go recreates window; with fake `~/.claude/projects/<encoded>` dir → log has `--continue -n foo`; without → no `--continue`.
- go no arg + `CW_FZF=cw-no-such-fzf` → output lists `app/foo`, exit 1.
- same name in two repos → `cw go foo` exits 1 listing `app/foo`, `lib/foo`; `cw go lib/foo -d` works.
- `go --waiting -d`: window with `@claude_state ⏳` → prints its target.

cw-rename-rm-from.bats
- rename foo bar: path + inode (`stat -c %i`) unchanged; `branch.foo.cwname=bar`; window name `bar`; `cw go bar -d` resolves.
- rename --branch: branch `bar` exists, `foo` gone, upstream kept, label consistent.
- rename to existing name → refused.
- rm refuses: untracked file (dirty); unpushed commit; open window. Messages mention override flag. Dir still there.
- rm after `cw push` (cwpushed == HEAD) and window closed → succeeds; dir + branch gone.
- rm --force on dirty → removed.
- bazel repo rm → bazel log contains `clean --expunge`; `--keep-cache` → not called.
- new baz --from foo (closed, clean): same dir; branch `baz` at `origin/main`; `foo` branch deleted; label `baz`; new window.
- --from refuses open or dirty source.

cw-ls-push.bats
- ls shows sessions of two repos; STATE `closed` / `open` / emoji after `tmux set -w @claude_state ✅`.
- ls CHANGE column = first 9 chars of Change-Id after commit.
- ls --size with `CW_BAZEL_OUTPUT_USER_ROOT` + fake md5 dir containing a file, `CW_SIZE_WARN_GB=0` → size column + warning.
- push ok: `refs/for/main` == HEAD in bare origin; `branch.foo.cwpushed` set.
- push refuses: 0 commits ahead; missing Change-Id (hint mentions commit-msg); 2 commits w/o `--chain`; `--chain` pushes.

cw-tmux-state.bats
- no TMUX → exit 0, no tmux server started.
- TMUX + TMUX_PANE of test server pane: `waiting` → `@claude_state` = ⏳; `clear` unsets; bogus arg exit 0; dead server → exit 0.

merge-claude-hooks.bats
- missing settings → file with 5 events; existing `model`, `statusLine` preserved; foreign `Stop` hook preserved; second run `cmp` identical; invalid JSON input → nonzero, original untouched.

bt.bats
- fake failing run: exit code propagated (3); output has FAILED target + tail of test.log + `full log`; PASSED lines absent; log file exists.
- passing run: exit 0, short output.

install.bats (skip if no stow)
- temp HOME: `~/.local/bin/cw` symlink resolves into dotfiles; `~/.config/cw/config` mode 600; second run creates no backup dir; pre-existing real `~/.config/tmux/tmux.conf` moved to backup.

`run-tests.sh`:
```bash
set -euo pipefail; cd "$(dirname "$0")/.."
shellcheck -x -S warning install.sh scripts/*.sh cw/.local/bin/* cw/.local/lib/cw/*.sh bazel/.local/bin/bt tests/stubs/* tests/*.bash tests/run-tests.sh
bats tests/
```

## Related Code Files
- Create: `/home/tun/dotfiles/tests/test-helper.bash`, `/home/tun/dotfiles/tests/stubs/claude`, `/home/tun/dotfiles/tests/stubs/bazel`
- Create: `/home/tun/dotfiles/tests/cw-new-go-close.bats`, `/home/tun/dotfiles/tests/cw-rename-rm-from.bats`, `/home/tun/dotfiles/tests/cw-ls-push.bats`
- Create: `/home/tun/dotfiles/tests/cw-tmux-state.bats`, `/home/tun/dotfiles/tests/merge-claude-hooks.bats`, `/home/tun/dotfiles/tests/bt.bats`, `/home/tun/dotfiles/tests/install.bats`
- Create: `/home/tun/dotfiles/tests/run-tests.sh`
- Modify: cw libs only to fix bugs found (no test-only branches in code)

## Implementation Steps
1. Install bats + shellcheck.
2. Helper + stubs; one smoke test (`cw new`) green first.
3. Write bats files in order above; run after each file.
4. Add `# shellcheck source=` directives in `cw` for libs; fix all warnings.
5. Run full suite 3x to catch flakiness (tmux timing) → adjust `wait_for_file` polling, never sleeps-as-asserts.
6. Delegate to tester agent for run + report, code-reviewer agent for review.

## Todo List
- [ ] Install bats, shellcheck
- [ ] test-helper.bash + stubs
- [ ] cw-new-go-close.bats
- [ ] cw-rename-rm-from.bats
- [ ] cw-ls-push.bats
- [ ] cw-tmux-state.bats, merge-claude-hooks.bats
- [ ] bt.bats, install.bats
- [ ] run-tests.sh green 3 consecutive runs; shellcheck clean

## Success Criteria
- `tests/run-tests.sh` exit 0, 3 consecutive runs, <60s total.
- Every guard in phase 3 has a refusal test and an override test.
- Tests never touch real `~`, real tmux server, or network.

## Risk Assessment
- tmux timing flakiness → poll with timeout; tests use window ids not names.
- Stubs drift from real CLI behavior → phase 7 manual checks with real Claude/Bazel/Gerrit.
- Leaked tmux servers on failure → `teardown` kill-server; TMUX_TMPDIR per test.

## Security Considerations
- No real credentials; Change-Ids random; all under `$BATS_TEST_TMPDIR`.

## Next Steps
- Phase 7 rollout after green suite.
