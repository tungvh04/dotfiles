# Phase 07 — Rollout + Orca retirement

## Context Links
- [plan.md](./plan.md), [brainstorm success metrics](../reports/brainstorm-260916-claude-tmux-workspace-setup.md)
- All previous phases; README in `/home/tun/dotfiles/README.md`

## Overview
- Date: 2026-09-16
- Description: Install on laptop (small repos) first, then monorepo box (Bazel + Gerrit, local + SSH); run Orca in parallel 1–2 weeks; uninstall Orca when metrics hold.
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights
- Laptop exercises core flow (new/go/close/rename/rm, hooks, review UX) cheaply; Bazel/Gerrit specifics only testable on monorepo box.
- Real bottleneck is review bandwidth, not session count → guidance: ~3 sessions actively iterated at once; others closed (cost: disk only).
- tmux server survives SSH disconnect; reboot kills windows but `cw go` resumes Claude conversations → verify explicitly.
- Existing sessions created by Orca (its own worktrees) are not adopted; finish them in Orca.

## Requirements
- Laptop: suite green, install, 3 days daily use, fix friction.
- Monorepo box: pre-checks (Bazel version/flags, repo rc, Gerrit remote + commit-msg hook, tmux version, stow/bats availability), install, validate metrics.
- Rollback: `stow -D cw tmux bazel` + restore `~/.claude/settings.json.bak.*` + backups dir.

## Architecture
Rollout sequence:
```
laptop: tests green → install.sh cw tmux (nvim restow opt-in) → hooks merged → daily use (Orca still installed)
monorepo box: clone dotfiles → prechecks → install.sh cw tmux bazel → CLAUDE.md in $CW_ROOT/<repo>/ → throwaway Gerrit change (WIP) → daily use
week 2 end: metrics review → uninstall Orca on laptop (and box if present)
```

## Related Code Files
- Modify: `/home/tun/dotfiles/README.md` (rollback section, lessons learned)
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/*.sh` (friction fixes only)
- Create (not in dotfiles, machine-local): `$CW_ROOT/<monorepo>/CLAUDE.md`, `~/.config/cw/config`
- Delete: none in dotfiles

## Implementation Steps
1. Laptop: `tests/run-tests.sh`; `./install.sh cw tmux`; `./install.sh nvim` (diffview); restart tmux server or `prefix r`; set `CW_ROOT`.
2. Laptop smoke: `cw new try1 ~/repos/<small-repo>` → state emojis flow → `prefix D` review → commit → `cw close try1` → `cw go try1` (resume) → `cw rename try1 try-one` → `cw rm try-one --force`.
3. Reboot test: create session, reboot, `cw go` picker → resume works.
4. Commit dotfiles (conventional commits, e.g. `feat(cw): add tmux multi-session launcher`); push dotfiles remote.
5. Monorepo box prechecks (phase 5 step 1; `git remote -v`; `ls "$(git rev-parse --git-common-dir)/hooks/commit-msg"`; `git config core.hooksPath`; `tmux -V`; `stow --version`).
6. Install `./install.sh cw tmux bazel`; write `~/.config/cw/config` (`CW_ROOT` on big disk); `git config cw.base <branch>` if origin/HEAD missing.
7. Fill CLAUDE.md template into `$CW_ROOT/<monorepo>/CLAUDE.md`.
8. Validate metrics: `cw new` <10s; incremental build in session ≈ main checkout; second session first build mostly disk-cache hits; idle servers reaped; `bt` output compact; `cw push` WIP change then Gerrit skill comment round → amend → `cw push` new patchset, all inside tmux; SSH detach/reattach keeps sessions.
9. `cw ls --size` after a week → tune `CW_SIZE_WARN_GB`, GC max size.
10. After 1–2 weeks without Orca use: uninstall Orca (`pacman -R`/AppImage removal per how installed), remove its worktrees after finishing tasks.

## Todo List
- [ ] Laptop install + smoke + reboot resume test
- [ ] Commit + push dotfiles
- [ ] Monorepo prechecks
- [ ] Monorepo install + config + CLAUDE.md
- [ ] Gerrit WIP change end-to-end (push, comments via skill, amend, repush)
- [ ] Bazel warm/cold + RAM + disk checks
- [ ] 1–2 week parallel run, friction log
- [ ] Uninstall Orca

## Success Criteria (from brainstorm)
- `cw new` → Claude running in correct worktree <10s (excluding first fetch/build).
- Incremental Bazel build in existing session ≈ main checkout speed.
- Status bar alone tells which sessions need input.
- Gerrit comment → new patchset without leaving tmux.
- Orca uninstalled, no regression reported after 1 week.

## Risk Assessment
- Disk explosion on monorepo box (output_base per session) → `cw ls --size` warning, `cw rm`, `--from` recycling; weekly check.
- Hook/tmux emoji rendering over SSH terminal → fallback letters (phase 4 risk).
- Muscle memory / friction → keep Orca during transition; log friction, fix in cw.
- Dotfiles public repo leaking monorepo info → CLAUDE.md instance + config stay machine-local.

## Security Considerations
- No internal hostnames, Gerrit URLs, or tokens committed to dotfiles.
- settings.json backups remain local.

## Next Steps
- Post-transition: consider (only if needed) `cw` completion script, Change-Id hook auto-install, stale-session report. YAGNI until friction proves need.
