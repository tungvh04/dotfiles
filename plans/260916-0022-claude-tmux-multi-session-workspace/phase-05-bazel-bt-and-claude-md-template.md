# Phase 05 — Bazel rc, `bt` wrapper, CLAUDE.md template

## Context Links
- [plan.md](./plan.md), [phase-03](./phase-03-cw-lifecycle-ls-rename-rm-push.md) (rm expunge, ls --size)
- Bazel: bazelrc order (system → workspace `.bazelrc` → `~/.bazelrc` → `--bazelrc`), https://bazel.build/remote/caching (disk cache GC, 7.4+), output directory layout
- Claude Code memory: CLAUDE.md loaded from cwd and ancestor dirs

## Overview
- Date: 2026-09-16
- Description: Make many worktrees cheap in Bazel (shared caches, idle server reaping, disk GC), give Claude compact test output (`bt`), per-repo CLAUDE.md template.
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Update 2026-09-16: repo `.bazelrc` likely sets own output location. `~/.bazelrc` loads AFTER workspace rc and overrides it → never set `output_user_root`/`output_base`; only add `--disk_cache` if repo rc has none. CLAUDE.md template = personal layer (`~/cw/<repo>/CLAUDE.md`); team monorepo CLAUDE.md untouched.
- Each worktree = own output_base (md5 of path). Cold only on first build; stays warm while dir exists. Shared `--disk_cache` makes first build in a new worktree mostly cache hits; `--repository_cache` avoids re-downloading externals.
- RAM: one Bazel JVM server per worktree that built recently; `startup --max_idle_secs` reaps idle ones → only active sessions hold memory. No cap on sessions (guidance, not limits).
- Disk: disk_cache grows unbounded without GC → `--experimental_disk_cache_gc_max_size/_max_age` (Bazel >=7.4; flag name verified in docs, still `experimental_` prefix). Unknown flag on older Bazel breaks every build → verify version before stowing `bazel` pkg.
- `~/.bazelrc` loads after workspace rc → our cache flags win. If repo sets `--nohome_rc` or `--output_user_root`, adapt (question in plan).
- `--test_output=errors` dumps whole logs inline → floods Claude context. Better: `--test_output=summary --test_summary=terse`, then tail each failed target's `test.log`; keep full log on disk for drill-down.
- Personal CLAUDE.md at `$CW_ROOT/<repo>/CLAUDE.md` applies to every session of that repo (ancestor dir), survives worktree creation (untracked files don't propagate to new worktrees).

## Requirements
- `~/.bazelrc`: disk cache, repository cache, disk GC, `max_idle_secs`; commented optional `host_jvm_args`.
- `bt [bazel test args...]`: runs tests quietly, full log to `${XDG_CACHE_HOME:-~/.cache}/bt/<dirname>-last.log`; prints: ERROR blocks (capped), non-passing targets, `Executed N out of M` line, last `BT_TAIL` (default 60) lines of each failed/timeout target's test.log (shards/attempts included), full-log path; exit code = bazel's. `BAZEL` env override (bazelisk). <120 lines.
- `templates/CLAUDE.md.template`: <80 lines, placeholders `<...>`.

## Architecture
`bazel/.bazelrc`:
```
build --disk_cache=~/.cache/bazel-disk          # verify ~ expansion; else absolute path per machine
build --repository_cache=~/.cache/bazel-repo
build --experimental_disk_cache_gc_max_size=60G  # Bazel >=7.4
build --experimental_disk_cache_gc_max_age=14d
startup --max_idle_secs=3600                     # reap idle per-worktree servers
# startup --host_jvm_args=-Xmx4g                 # cap per-server heap if RAM tight
```
`bt` flow:
```bash
bazel="${BAZEL:-bazel}"; log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/bt"; mkdir -p "$log_dir"
log="$log_dir/$(basename "$PWD")-last.log"
set +e; "$bazel" test --color=no --curses=no --noshow_progress \
  --test_output=summary --test_summary=terse "$@" >"$log" 2>&1; rc=$?; set -e
grep -E -A4 '^(ERROR|FAIL):' "$log" | head -n "${BT_ERR_LINES:-80}"
failed=$(grep -E '^//\S+\s+.*(FAILED|TIMEOUT|NO STATUS|INCOMPLETE)' "$log" | awk '{print $1}')
grep -E '^(//\S+\s+.*(FAILED|TIMEOUT|NO STATUS|FLAKY|INCOMPLETE)|Executed [0-9]+ out of|INFO: Build completed|FAILED: Build did NOT complete)' "$log"
testlogs=$("$bazel" info bazel-testlogs 2>/dev/null)   # server already warm
for t in $failed; do p=${t#//}; p=${p/://}
  find "$testlogs/$p" -name test.log 2>/dev/null | while read -r f; do
    echo "--- tail $f"; tail -n "${BT_TAIL:-60}" "$f"; done; done
echo "bt: full log $log (exit $rc)"; exit "$rc"
```
(`//pkg:name` → `pkg/name`; root-package `//:name` → `name`. Under `set -euo pipefail` every grep needs `|| true` — no match is normal.)

CLAUDE.md template outline:
```markdown
# <repo> — agent notes (personal, lives at $CW_ROOT/<repo>/CLAUDE.md)
## Build / test / lint
- Test: `bt //<pkg>/...` (NEVER raw `bazel test`; never `//...` on whole monorepo)
- Build: `bazel build //<pkg>:<target>`; Lint/format: `<cmd>`
- Find affected tests: `bazel query 'rdeps(//<scope>/..., //<pkg>:<target>)' --output=label | grep _test`
- Never `bazel clean --expunge` (kills warm cache; cw rm handles it)
## Target patterns
- <lang>: `//<dir>:<name>_test`, BUILD conventions, where protos live
## Gerrit workflow
- One session = one branch = ONE commit/change. Iterate with `git commit --amend`; keep `Change-Id:` trailer unchanged.
- Do not push; user runs `cw push` (or ask first). No relation chains.
- Review comments: use the Gerrit skill to fetch unresolved comments, fix, amend, then report.
- Commit msg: <subject convention>, body wraps 72, `Bug:`/`Test:` footers if required.
## Code conventions
- <links to style guides / key dirs / owners>
```

## Related Code Files
- Create: `/home/tun/dotfiles/bazel/.bazelrc`
- Create: `/home/tun/dotfiles/bazel/.local/bin/bt`
- Create: `/home/tun/dotfiles/templates/CLAUDE.md.template`
- Modify: `/home/tun/dotfiles/README.md` (Bazel guidance: cold/warm, RAM, disk, `--from`, `ls --size`)

## Implementation Steps
1. On monorepo box: `bazel --version` (>=7.4?), `bazel help build | grep -E 'disk_cache_gc|repository_cache'`, inspect repo `.bazelrc` for `nohome_rc`, `output_user_root`, `disk_cache`, remote cache settings.
2. Write `.bazelrc`; verify `~` expansion via `bazel info --announce_rc 2>&1 | grep disk_cache` and cache dir populated after a build; switch to absolute path if not.
3. Write `bt`; test against fake bazel (phase 6) and a real failing test on monorepo box; compare token size vs `--test_output=errors`.
4. Write CLAUDE.md template; fill for monorepo into `$CW_ROOT/<monorepo>/CLAUDE.md`; verify in a session via `/memory` that it is loaded.
5. README Bazel section.

## Todo List
- [ ] Check Bazel version/flags/repo rc on monorepo box
- [ ] .bazelrc (+ verify ~ expansion, GC flags accepted)
- [ ] bt wrapper (+ shellcheck)
- [ ] CLAUDE.md template + monorepo instance (not committed to dotfiles if it contains internal info)
- [ ] README Bazel guidance

## Success Criteria
- Second worktree first build: mostly disk-cache hits (check `INFO: ... disk cache hit` counts).
- Idle Bazel servers gone after `max_idle_secs` (`pgrep -fa 'bazel.*A-server'`).
- `bt` failing run output <~150 lines while full log retained; exit code preserved.
- Claude in new session knows to use `bt` without being told.

## Risk Assessment
- GC flags unknown on old Bazel → stow `bazel` pkg only after step 1; else drop GC lines + manual `find ~/.cache/bazel-disk -atime +14 -delete` cron note.
- disk_cache + remote cache interplay → disk cache is local layer; harmless. If repo mandates remote-only, drop disk_cache.
- Output format changes across Bazel versions → grep patterns lenient; full log path always printed.
- `bazel info bazel-testlogs` differs per config (`--config=x`) → acceptable; fallback `bazel-testlogs` symlink in workspace.

## Security Considerations
- Monorepo-specific CLAUDE.md content (internal hosts, paths) stays out of public dotfiles repo; template only generic.
- Shared disk cache is per-user dir; no cross-user sharing.

## Next Steps
- Phase 6 bt tests with fake bazel. Phase 7 validates warm-build metrics on monorepo box.
