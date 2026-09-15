# Phase 08 — Clickable editor links (VS Code / IntelliJ)

## Context Links
- [plan.md](./plan.md), [phase-03](./phase-03-cw-lifecycle-ls-rename-rm-push.md) (ls/new output), [phase-04](./phase-04-claude-hooks-tmux-and-review-ux.md) (tmux.conf)
- OSC 8 hyperlinks spec: https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
- tmux `terminal-features ... hyperlinks` (tmux >=3.4)
- freedesktop `x-scheme-handler/*` + `xdg-mime`

## Overview
- Date: 2026-09-16
- Description: Click session name/links in `cw ls` / `cw new` output to open worktree in VS Code or IntelliJ; `cw code` / `cw idea` commands + tmux keys as keyboard fallback.
- Priority: P3 (nice-to-have; after phases 3+4)
- Implementation status: pending
- Review status: not reviewed

## Key Insights (checked on laptop 2026-09-16)
- Terminal = Konsole 26.04.3, profile `~/.local/share/konsole/tun.profile` has default link settings. Konsole ignores OSC 8 unless "Allow escape sequences for links" is on, and only allows schemes listed in the allowed-schemas field (default http/https/file).
- `x-scheme-handler/vscode` → `code-url-handler.desktop` (already registered). `vscode://file/<abs-path>` opens folder.
- IntelliJ (`/usr/bin/idea`, IdeaIC 2025.3) registers NO URL scheme (`idea.desktop` only `%f`). Need own `idea://` handler.
- Over SSH: `vscode://vscode-remote/ssh-remote+<host><abs-path>` opens remote worktree in laptop VS Code (Remote-SSH). `<host>` = SSH alias as laptop knows it → config `CW_SSH_HOST`, not autodetectable. IntelliJ over SSH needs Gateway → no link (YAGNI).
- `column -t` counts escape bytes → misaligned table. Format table first, append link column after.
- Links only when stdout is a tty (fzf `--plain`, pipes, tests get plain text).

## Requirements
- `cw ls`: trailing OPEN column `[code] [idea]` (tty only; `CW_LINKS=0` disables). Over SSH: `[code]` remote link only.
- `cw new`: final line `ready: <dir>  [code] [idea]`.
- `cw code [name]` / `cw idea [name]`: no name → session of `$PWD`. Local GUI → launch detached (`setsid -f code "$dir" >/dev/null 2>&1`). Over SSH (`$SSH_CONNECTION`) → print clickable link instead.
- tmux: `prefix E` → `cw code`, `prefix I` → `cw idea` in pane cwd.
- `idea-url-handler`: accepts only `idea://open?file=<pct-encoded abs path>`; decoded path must exist and resolve (realpath) inside `$CW_ROOT` (or extra roots in `CW_LINK_ALLOW`); else notify/exit 1. Never eval/interpolate URL into shell.

## Architecture
```
cw ls/new ──> cw-links.sh: osc8(url,text), url_code(dir), url_idea(dir), pct_encode
click ──> Konsole ──xdg-open──> vscode:// → code-url-handler (VS Code)
                               idea://   → idea-url-handler.desktop → ~/.local/bin/idea-url-handler → idea <dir>
```
```bash
# cw/.local/lib/cw/cw-links.sh (~60 lines)
links_on() { [ -t 1 ] && [ "${CW_LINKS:-1}" != 0 ]; }
osc8() { printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$1" "$2"; }
pct_encode() { local s=$1 o= c i; for ((i=0;i<${#s};i++)); do c=${s:i:1}
  case $c in [a-zA-Z0-9/._~-]) o+=$c;; *) printf -v c '%%%02X' "'$c"; o+=$c;; esac; done; printf '%s' "$o"; }
url_code() { if [ -n "${SSH_CONNECTION:-}" ]; then
    [ -n "${CW_SSH_HOST:-}" ] && printf 'vscode://vscode-remote/ssh-remote+%s%s' "$CW_SSH_HOST" "$(pct_encode "$1")"
  else printf 'vscode://file%s' "$(pct_encode "$1")"; fi; }
url_idea() { [ -z "${SSH_CONNECTION:-}" ] && printf 'idea://open?file=%s' "$(pct_encode "$1")"; }
link_cell() { links_on || return 0; local u
  u=$(url_code "$1") && [ -n "$u" ] && osc8 "$u" '[code]'; u=$(url_idea "$1") && osc8 "$u" ' [idea]'; }
```
`pct_encode` is byte-wise; run with `LC_ALL=C` so multibyte chars encode per byte.
`idea/.local/share/applications/idea-url-handler.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=IntelliJ URL handler (cw)
Exec=idea-url-handler %u
MimeType=x-scheme-handler/idea;
NoDisplay=true
```

## Related Code Files
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-links.sh`
- Create: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-open.sh` (`cmd_code`, `cmd_idea`)
- Create: `/home/tun/dotfiles/idea/.local/bin/idea-url-handler` (<60 lines)
- Create: `/home/tun/dotfiles/idea/.local/share/applications/idea-url-handler.desktop`
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-ls.sh` (append link column after `column -t`)
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-new.sh` (ready line)
- Modify: `/home/tun/dotfiles/cw/.local/bin/cw` (dispatch `code`, `idea`)
- Modify: `/home/tun/dotfiles/tmux/.config/tmux/tmux.conf` (`bind E`, `bind I`; `hyperlinks` feature already in phase 4)
- Modify: `/home/tun/dotfiles/templates/cw-config.example` (`CW_SSH_HOST`, `CW_LINKS`, `CW_LINK_ALLOW`)
- Modify: `/home/tun/dotfiles/install.sh` (`idea` pkg opt-in: stow + `xdg-mime default idea-url-handler.desktop x-scheme-handler/idea` + `update-desktop-database ~/.local/share/applications`)

## Implementation Steps
1. Manual Konsole setup on laptop: Settings → Edit Current Profile → Mouse → Miscellaneous → enable escape-sequence links, add `vscode://;idea://` to schemas. Diff `tun.profile` before/after to learn exact keys; document in README (optionally stow profile later).
2. Smoke test outside tmux, then inside tmux:
   `printf '\e]8;;vscode://file/home/tun/repos\e\\>> open <<\e]8;;\e\\\n'`
3. Write `cw-links.sh`; wire into `cmd_ls` (build rows → `column -t` → paste `link_cell "$dir"` per line) and `cmd_new`.
4. Write `cmd_code` / `cmd_idea` (resolve session or `$PWD`; local launch vs SSH print link).
5. Write `idea-url-handler` + `.desktop`; register via install.sh `idea` pkg; `xdg-open 'idea://open?file=/home/tun/cw/...'` test.
6. tmux binds `E` / `I`: `bind E run-shell -b -c '#{pane_current_path}' 'cw code'` (overrides default `select-layout -E`, acceptable).
7. On monorepo box over SSH: set `CW_SSH_HOST`, verify `[code]` opens Remote-SSH window on laptop.

## Todo List
- [ ] Konsole link settings + smoke test (plain, tmux, SSH)
- [ ] cw-links.sh (osc8, pct_encode, url builders, tty gate)
- [ ] ls link column (alignment intact) + new ready line
- [ ] cw code / cw idea
- [ ] idea-url-handler + desktop entry + install.sh `idea` pkg
- [ ] tmux E / I binds
- [ ] bats: no escapes when not tty / `CW_LINKS=0`; pct_encode spaces/`#`/`?`; handler rejects outside-root, `..`, missing path, wrong scheme

## Success Criteria
- Click `[code]` / `[idea]` in `cw ls` (Konsole, inside tmux) opens that worktree in <3s.
- Over SSH, `[code]` opens Remote-SSH VS Code on laptop for correct path.
- `cw ls | cat` and `cw ls --plain` contain no escape bytes; columns aligned on tty.
- `xdg-open 'idea://open?file=/etc'` does nothing (rejected).

## Risk Assessment
- Konsole setting per-profile/per-machine → README step; other terminals (kitty, wezterm, iTerm2) support OSC 8 by default.
- Escape sequences leaking into fzf/pipes → tty gate + `--plain` never adds links.
- Konsole may prompt/confirm on unknown schemes → acceptable.
- IntelliJ single-instance: `idea <dir>` opens new project window or focuses existing → acceptable.

## Security Considerations
- Any web page / terminal output can fire `idea://` → handler allowlist (realpath under `$CW_ROOT`/`CW_LINK_ALLOW`), no shell interpolation, only opens dirs/files, never executes them.
- Printing untrusted text inside OSC 8: only cw-generated dirs (validated ids) + git refnames (no control chars allowed) → no escape injection.
- Enabling Konsole escape links lets any program print deceptive links → restrict schemas to `http;https;file;vscode;idea`.

## Next Steps
- Phase 6 adds bats cases above; phase 7 rollout includes Konsole setup on both machines (monorepo box desktop too).
