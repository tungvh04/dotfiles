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

## Answered (2026-09-16)
- CW_ROOT = `~/cw` default (both machines).
- Monorepo Bazel version unknown; repo `.bazelrc` likely sets own output location → ph3 `ls --size` must not assume md5 path (use `bazel info output_base` behind `--size`, cache per session); ph5 `~/.bazelrc` never sets `output_user_root`/`output_base`, skip `--disk_cache` if repo rc already sets it (home rc loads after workspace rc → would override team setting). Version precheck stays (ph5 step 1).
- Gerrit commit-msg hook already installed on monorepo box → ph7 drops hook install; `cw push` Change-Id check stays as safety net.
- Monorepo box: Ubuntu (apt), tmux NOT installed → ph7 `apt install tmux stow jq fzf bats shellcheck`; lazygit via GitHub release binary if not in apt. tmux version depends on Ubuntu release (22.04 = 3.2a: popups ok, no OSC 8 hyperlinks; 24.04 = 3.4 ok) → ph4 guard `hyperlinks` feature by version; ph8 links degrade to plain text. install.sh dep hints: pacman on Arch, apt on Ubuntu.
- `cw rm` expunges Bazel output by default; `--keep-cache` opt-out.
- CLAUDE.md is per repo type: team repos (monorepo) own committed CLAUDE.md → cw never edits it; personal layer = untracked `~/cw/<repo>/CLAUDE.md` (ancestor dir). Personal repos → commit own CLAUDE.md. Template = personal layer only.
- dotfiles repo private, may go public → treat as public-ready: no company names, hostnames, Gerrit URLs, internal paths; machine-specific values only in untracked `~/.config/cw/config`.

## Unresolved questions
1. Exact Bazel version + repo `.bazelrc` flags on monorepo box → check at ph7 precheck (`bazel --version`, `cat .bazelversion`, `grep -nE 'output_user_root|output_base|disk_cache|nohome_rc' .bazelrc`).
2. Ubuntu release on monorepo box (tmux version → hyperlinks) → `lsb_release -a` at ph7.
3. (build-time) `claude --continue` with no history → fresh session? `-n` kept on continue? `/rename` exists?
