---
title: "Claude tmux multi-session workspace (cw)"
description: "Replace Orca with a tmux-based cw launcher: unlimited named persistent worktree sessions, Claude state in tmux bar, Gerrit push, Bazel-friendly."
status: pending
priority: P2
effort: 22.5h
branch: n/a
tags: [infra, tooling, tmux, bazel, gerrit, claude-code]
created: 2026-09-16
---

# Claude tmux multi-session workspace (cw)

## Overview
One tmux workflow on both machines (laptop small repos, monorepo box Bazel+Gerrit, local or SSH).
Session = persistent worktree `$CW_ROOT/<repo>/<id>` + branch + tmux window + Claude conversation. One mode for all repos.
State derived from git worktrees + tmux only; optional label in `branch.<b>.cwname`. Everything lives in `/home/tun/dotfiles` (stow packages; GitHub `tungvh04/dotfiles`); this plan also lives there (`dotfiles/plans/`), so it syncs to the monorepo machine. Existing `tmux` package (prefix C-a, fzf session switcher, One Dark bar) gets extended, not replaced.
Input: [brainstorm report](../reports/brainstorm-260916-claude-tmux-workspace-setup.md) (slots design superseded by user change: no slots, unlimited sessions).

## Phases

| # | Phase | Status | Effort | Link |
|---|-------|--------|--------|------|
| 1 | Dotfiles scaffold, config, install.sh | Pending | 1.5h | [phase-01](./phase-01-dotfiles-scaffold-and-install.md) |
| 2 | cw core + new / go / close | Pending | 5h | [phase-02](./phase-02-cw-core-new-go-close.md) |
| 3 | cw ls / rename / rm / --from / push (Gerrit) | Pending | 5h | [phase-03](./phase-03-cw-lifecycle-ls-rename-rm-push.md) |
| 4 | Claude hooks, tmux.conf, diff review UX | Pending | 2.5h | [phase-04](./phase-04-claude-hooks-tmux-and-review-ux.md) |
| 5 | Bazel rc, bt wrapper, CLAUDE.md template | Pending | 2h | [phase-05](./phase-05-bazel-bt-and-claude-md-template.md) |
| 6 | Tests (bats) + shellcheck | Pending | 4h | [phase-06](./phase-06-tests-and-shellcheck.md) |
| 7 | Rollout + Orca retirement | Pending | 1h (+2wk calendar) | [phase-07](./phase-07-rollout-and-orca-retirement.md) |
| 8 | Clickable editor links (VS Code / IntelliJ), `cw code`/`cw idea` | Pending | 1.5h | [phase-08](./phase-08-clickable-editor-links.md) |

Order: 1 → 2 → 3 → (4, 5 parallel) → 8 → 6 → 7. Write bats tests alongside 2/3 where cheap; phase 6 completes coverage.

## Key decisions
- Dir id fixed at creation; `rename` never moves dir (Bazel output_base = md5(workspace path); Claude history keyed by project path).
- Claude state shown via tmux window option `@claude_state` rendered in `window-status-format`, not by renaming windows (no name parsing, works for any Claude in tmux).
- Windows located by `@cw_path` option (stable), never by name.
- Bazel cost handled by guidance: shared disk/repo cache, `--max_idle_secs`, `cw ls --size` warning, `cw new --from` recycling, `cw rm` expunges output_base.
- Per-repo instructions: `$CW_ROOT/<repo>/CLAUDE.md` (Claude loads ancestor CLAUDE.md) so untracked personal file applies to every session.
- Editor links: OSC 8 hyperlinks in `cw ls`/`new` (tty only) → `vscode://` (Remote-SSH when over SSH) + own allowlisted `idea://` handler; Konsole must allow escape links.
- 1 session = 1 branch = 1 Gerrit change; `cw push` refuses chains unless `--chain`.

## Dependencies
- Laptop: git, tmux (>=3.2 popups; have 3.7b), jq, stow, fzf (have); install `shellcheck bash-bats lazygit` (pacman).
- Monorepo box: same + bazel/bazelisk; existing Gerrit API skill (reused for comments); Gerrit commit-msg hook.
- Claude Code hooks: Notification (matcher), Stop, UserPromptSubmit, PostToolUse, SessionEnd (verified against code.claude.com/docs/en/hooks).

## Unresolved questions
1. `CW_ROOT` default `~/cw` OK? Monorepo box may need it on a specific big disk.
2. ~~Claude project-dir encoding~~ Resolved 2026-09-16: `~/.claude/projects/` shows `/`→`-`. cw needs no encoding logic: run `claude --continue` in the worktree dir. Still to check in phase 2: whether `--continue` falls back to a fresh session when there is no history.
3. Does `claude --continue -n <name>` keep/update display name? Is `/rename` available inside Claude? Verify.
4. Bazel version on monorepo box: >=7.4 needed for `--experimental_disk_cache_gc_max_size`; any repo `.bazelrc` overriding `output_user_root`/`disk_cache` or using `--nohome_rc`?
5. Gerrit remote name (`origin`?) and whether repo already installs commit-msg hook / sets `core.hooksPath`.
6. ~~tmux prefix~~ Resolved: existing dotfiles tmux.conf uses `C-a`. Still open: tmux version on monorepo box (need >=3.4 for hyperlinks, >=3.2 popups).
7. Second machine OS / package manager (stow, bats, shellcheck availability).
8. Is team OK with a committed repo CLAUDE.md, or keep personal-only under `$CW_ROOT/<repo>/`?
9. Is dotfiles remote public? Decides whether any monorepo-specific content may live there.
10. `cw rm` in Bazel repos runs `bazel clean --expunge` by default — OK, or prefer opt-in?
