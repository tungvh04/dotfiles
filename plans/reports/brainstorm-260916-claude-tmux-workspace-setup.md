# Brainstorm: Claude Code Multi-Session Workspace (tmux everywhere)

Date: 2026-09-16

## Problem
Pain points, all confirmed:
- Context switching between sessions
- Waiting on single Claude session
- Gerrit review loop (comments → amend → new patchset)
- Slow/noisy Bazel build+test feedback

## Environment
- Laptop (Arch): tmux, nvim, VS Code, IntelliJ, Claude Code 2.1.x, currently Orca (VS Code-fork UI). Many small/mixed repos.
- Other machine: big Bazel monorepo, Gerrit, existing Gerrit API skill. Used both locally and over SSH.
- Target: 3–5 parallel tasks. Editors: mixed (nvim + IntelliJ for JVM).

## Approaches evaluated
| Approach | Pros | Cons |
|---|---|---|
| Orca / dmux (fresh worktree per task) | Ready-made, nice UX, best-of-N | Cold Bazel output_base per worktree, extra Bazel JVM RAM each, IntelliJ resync, Orca GUI bad over SSH |
| IDE-centric (N terminals in IDE) | Zero setup | Loses track at 3+, heavy indexing |
| Split: Orca laptop + tmux script monorepo | Least migration | Two workflows |
| **tmux everywhere, own `cw` script** (CHOSEN) | One workflow both machines, survives SSH/local switch, fits Bazel+Gerrit, IDE-neutral | Own ~150–250 LOC bash; must replace Orca's diff UI |

## Decision
Single `cw` tmux-based launcher on both machines, two worktree modes:
- **Slot mode** (Bazel repos, detected via `MODULE.bazel`/`WORKSPACE`): fixed persistent worktrees `ws1..wsN` (N≈3). New task = `git switch -c <task> origin/<base>` in free slot. Never delete → warm output_base.
- **Ephemeral mode** (small repos): worktree per task, removed on `cw done`.

## Components
1. **`cw` script**: `new <task> [repo]`, `ls` (slot|branch|Change-Id|claude state), `go <task>`, `done <task>`, `push`. One tmux window per task, named after task.
2. **Claude Code hooks** (`~/.claude/settings.json`): `Notification` → rename tmux window `⏳<task>`; `Stop` → `✅<task>`; `UserPromptSubmit` → `🔄<task>`. Status bar = dashboard.
3. **Bazel**: `~/.bazelrc` shared `--disk_cache` + `--repository_cache`; wrapper `bt` running `bazel test --test_output=errors` with trimmed output for Claude context.
4. **Gerrit**: 1 slot = 1 branch = 1 change; no cross-session relation chains. `cw push` = `git push origin HEAD:refs/for/<base>`. Comment handling reuses existing Gerrit skill (DRY). Change-Id hook in shared `.git/hooks` (common across worktrees).
5. **CLAUDE.md template** per repo: exact build/test/lint commands, target patterns, Gerrit conventions.
6. **Diff review (Orca replacement)**: nvim diffview.nvim / fugitive, or lazygit in split pane. IntelliJ opened on one slot at a time for JVM deep dives; `/ide` to connect Claude.
7. **Dotfiles repo**: script + tmux.conf + hooks + bazelrc synced across both machines.

## Risks / mitigations
- Review bandwidth is the real bottleneck → cap serious parallel tasks at ~3 on monorepo.
- Bazel RAM per slot server → limit slots; `--max_idle_secs` to reap idle servers.
- Losing Orca diff UX → set up diffview/lazygit before retiring Orca; keep Orca installed during 1–2 week transition.
- Script sprawl → keep YAGNI: no best-of-N, no web UI, no DB; state derived from git + tmux.
- Hook tmux calls must no-op outside tmux (`[ -n "$TMUX" ]`).

## Success metrics
- `cw new` → Claude running in correct worktree < 10s (warm slot).
- Incremental Bazel build in reused slot ≈ main checkout speed.
- Glance at tmux bar tells which sessions need input.
- Gerrit comment → new patchset without leaving tmux.
- Orca uninstalled after transition without regression.

## Next steps
1. Implementation plan (`/plan:fast`).
2. Build + test on laptop (ephemeral mode), then monorepo machine (slot mode).
3. Retire Orca after transition period.

## Sources
- https://github.com/fmfsaisai/orca
- https://dev.to/andrew-ooo/orca-review-the-ide-built-for-parallel-coding-agents-15df
- https://github.com/formkit/dmux
- https://codewithmukesh.com/blog/git-worktrees-claude-code/
