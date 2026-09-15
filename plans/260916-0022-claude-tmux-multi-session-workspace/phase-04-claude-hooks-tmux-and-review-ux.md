# Phase 04 — Claude hooks, tmux.conf, diff review UX

## Context Links
- [plan.md](./plan.md), [phase-01](./phase-01-dotfiles-scaffold-and-install.md) (install calls merge script)
- Claude Code hooks reference: https://code.claude.com/docs/en/hooks (verified 2026-09-16)
- tmux(1) formats/user options; diffview.nvim (github.com/sindrets/diffview.nvim); lazygit
- Existing nvim: `/home/tun/dotfiles/nvim/.config/nvim` (lazy.nvim, `{ import = "plugins" }`, leader = space, no `<leader>g*` maps)

## Overview
- Date: 2026-09-16
- Description: Claude state dashboard in tmux status bar via hooks; tmux config w/ jump keys; Orca diff-review replacement (diffview.nvim in nvim, lazygit popup).
- Priority: P2
- Implementation status: pending
- Review status: not reviewed

## Key Insights (verified docs)
- settings shape: `"hooks": { "<Event>": [ { "matcher": "...", "hooks": [ { "type": "command", "command": "...", "timeout": 5 } ] } ] }`.
- `Stop`, `UserPromptSubmit` take no matcher. `Notification` matcher values incl. `permission_prompt`, `idle_prompt`, `elicitation_dialog`. `SessionEnd` exists.
- Exclude `idle_prompt` from ⏳: it fires ~after idle post-Stop and would overwrite ✅.
- After a permission prompt is approved Claude keeps working but no event until Stop → add `PostToolUse` → 🔄 (sync, ~10ms; not async to avoid ordering races with Stop).
- Hook processes inherit Claude env → `$TMUX`, `$TMUX_PANE` available. Hook must always exit 0 (Stop exit 2 blocks stopping).
- Set window option on pane target: `tmux set-option -w -t "$TMUX_PANE" @claude_state ⏳` → no window rename, no task-name parsing; format renders it. Works for any Claude in tmux, cw or not.
- tmux `run-shell` expands `#{}` formats → keep logic in scripts (`cw go --waiting`), not inline tmux one-liners.

## Requirements
- `cw-tmux-state <busy|waiting|done|clear>`: no-op without `$TMUX`/`$TMUX_PANE`; never fails; <30 lines.
- Hooks: UserPromptSubmit→busy, PostToolUse→busy, Notification(permission_prompt|elicitation_dialog)→waiting, Stop→done, SessionEnd→clear.
- Merge into `~/.claude/settings.json` idempotently, preserving all existing keys and any foreign hooks; backup first; validate JSON before replace.
- tmux.conf: status shows `#I <emoji> name`; prefix keys: jump to next ⏳ window, fzf session picker popup, new session prompt, lazygit popup, diff split; Alt-1..9 window select; nvim-friendly settings; Shift+Enter works in Claude (extended keys).
- `cw go --waiting`: switch to first window with `@claude_state == ⏳` (small addition to go module).
- nvim: diffview plugin spec w/ leader-g keymaps.

## Architecture
```
Claude event ──hook──> cw-tmux-state <state> ──tmux set -w @claude_state──> status bar + cw ls STATE
```
`templates/claude-hooks.json`:
```json
{ "hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "\"$HOME/.local/bin/cw-tmux-state\" busy", "timeout": 5 }] }],
  "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "\"$HOME/.local/bin/cw-tmux-state\" busy", "timeout": 5 }] }],
  "Notification":     [{ "matcher": "permission_prompt|elicitation_dialog",
                         "hooks": [{ "type": "command", "command": "\"$HOME/.local/bin/cw-tmux-state\" waiting", "timeout": 5 }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "\"$HOME/.local/bin/cw-tmux-state\" done", "timeout": 5 }] }],
  "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "\"$HOME/.local/bin/cw-tmux-state\" clear", "timeout": 5 }] }]
} }
```
`scripts/merge-claude-hooks.sh` core (remove old cw entries, append new → idempotent):
```bash
jq --slurpfile new "$TPL" '
  reduce ($new[0].hooks | to_entries[]) as $e (.;
    .hooks[$e.key] = ((.hooks[$e.key] // [])
      | map(select([.hooks[]?.command // ""] | any(test("cw-tmux-state")) | not))
      + $e.value))' "$SETTINGS" > "$tmp" && jq empty "$tmp" && cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)" && mv "$tmp" "$SETTINGS"
```
(missing settings.json → start from `{}`.)

`cw-tmux-state`:
```bash
#!/usr/bin/env bash
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
case "${1:-}" in
  busy) s='🔄';; waiting) s='⏳';; done) s='✅';;
  clear) tmux set-option -wu -t "$TMUX_PANE" @claude_state 2>/dev/null; exit 0;;
  *) exit 0;;
esac
tmux set-option -w -t "$TMUX_PANE" @claude_state "$s" 2>/dev/null || true
exit 0
```
`tmux.conf`: **MODIFY the existing file** (added 2026-09-16, commit 4fc1a07 + uncommitted edits). It already has: prefix `C-a`, mouse, base-index 1, renumber, escape-time 10, focus-events, vi copy mode, `|`/`-` splits, hjkl panes, `prefix r` reload, `prefix s` fzf session switcher popup (`scripts/tmux-session-switcher-fzf.sh`, ctrl-r rename), and a One Dark status bar. Keep all of that and the palette. Add only these lines:
```tmux
set -as terminal-features ',xterm*:RGB:extkeys:hyperlinks'
set -s extended-keys on
set -g status-interval 2
# inject state emoji into existing One Dark formats
setw -g window-status-format "#[fg=#5c6370] #I:#{?@claude_state,#{@claude_state} ,}#W "
setw -g window-status-current-format "#[bg=#3e4452,fg=#e5c07b,bold] #I:#{?@claude_state,#{@claude_state} ,}#W#{?window_zoomed_flag, 󰊓,} "
bind -n M-1 select-window -t :=1   # ... through M-9
bind W run-shell 'cw go --waiting'
bind f display-popup -E -w 80% -h 60% 'cw go'   # cw session picker; existing `prefix s` stays for tmux sessions
bind N command-prompt -p 'cw session name:' "display-popup -E -d '#{pane_current_path}' 'cw new %1'"
bind g display-popup -E -w 90% -h 90% -d '#{pane_current_path}' lazygit
bind D split-window -h -c '#{pane_current_path}' "nvim -c 'DiffviewOpen @{u}'"
```
Check there are no key conflicts: none of `W f N g D` or `M-1..9` are bound in the current file. Default tmux `prefix f` (find-window) and `prefix D` (choose-client) get overridden, which is acceptable. DRY: reuse the rename-prompt pattern from the existing switcher script in the `cw go` fzf picker (ctrl-r → `cw rename`).
nvim `lua/plugins/diffview.lua`:
```lua
return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = 'Diff working tree' },
    { '<leader>gu', '<cmd>DiffviewOpen @{u}<cr>', desc = 'Diff whole change vs upstream' },
    { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = 'File history' },
    { '<leader>gq', '<cmd>DiffviewClose<cr>', desc = 'Close diffview' },
  },
  opts = {},
}
```
Review flow (replaces Orca): status bar ✅ → `prefix W`/`prefix f` jump → `prefix D` diff vs upstream (whole Gerrit change incl. amended commit) or `prefix g` lazygit → comment back to Claude. JVM deep dive: open session dir in IntelliJ, `/ide` in Claude.

## Related Code Files
- Create: `/home/tun/dotfiles/cw/.local/bin/cw-tmux-state`
- Create: `/home/tun/dotfiles/templates/claude-hooks.json`
- Create: `/home/tun/dotfiles/scripts/merge-claude-hooks.sh`
- Modify: `/home/tun/dotfiles/tmux/.config/tmux/tmux.conf` (existing; append only, keep prefix C-a + One Dark)
- Keep: `/home/tun/dotfiles/tmux/.config/tmux/scripts/tmux-session-switcher-fzf.sh` (tmux sessions; cw picker handles worktree sessions)
- Create: `/home/tun/dotfiles/nvim/.config/nvim/lua/plugins/diffview.lua`
- Modify: `/home/tun/dotfiles/cw/.local/lib/cw/cw-cmd-go-close.sh` (`--waiting`)
- Modify: `/home/tun/dotfiles/nvim/.config/nvim/lazy-lock.json` (auto by `:Lazy sync`)
- Modify (via script, not repo): `~/.claude/settings.json`

## Implementation Steps
1. Write `cw-tmux-state`; `chmod +x`; manual test inside tmux: `cw-tmux-state waiting` → bar shows ⏳ (after tmux.conf loaded).
2. Write `claude-hooks.json` + `merge-claude-hooks.sh` (requires jq; `SETTINGS=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}` for tests).
3. Run merge on laptop; diff before/after: only `hooks` key added; rerun → identical file.
4. Start Claude in tmux, verify transitions: prompt→🔄, permission prompt→⏳, approve→🔄 on next tool, finish→✅, exit→cleared. Check `/hooks` menu lists them.
5. tmux.conf; `tmux source`; verify Shift+Enter newline in Claude, colors in nvim, popups.
6. Add `--waiting` to `cmd_go`.
7. diffview.lua; `:Lazy sync`; commit lock file.
8. `sudo pacman -S lazygit` (laptop); monorepo box equivalent.

## Todo List
- [ ] cw-tmux-state script
- [ ] claude-hooks.json + merge-claude-hooks.sh (idempotent, backup, validate)
- [ ] Verify event transitions live in Claude 2.1.272
- [ ] tmux.conf (status format, binds, extended keys)
- [ ] `cw go --waiting`
- [ ] diffview.lua + lazy-lock update
- [ ] install lazygit

## Success Criteria
- Glance at bar shows which sessions need input (⏳) / finished (✅) / working (🔄).
- Merge script: existing settings keys untouched; running twice yields byte-identical file.
- Claude outside tmux: no errors, no delay.
- `prefix D` opens full change diff in <2s.

## Risk Assessment
- Hook event/matcher names change in future Claude versions → isolated in one JSON template; `/hooks` check in step 4.
- PostToolUse overhead on tool-heavy runs → ~10ms each; drop PostToolUse if noticeable.
- Interrupt (Esc) may not fire Stop → state stuck 🔄 until next prompt; acceptable.
- Emoji width issues in some terminals → fallback letters (`W/D/B`) via env in script if needed.
- tmux on monorepo box <3.2 → no popups; binds degrade (use `new-window` variants).

## Security Considerations
- Hook command fixed path under `$HOME/.local/bin`; no stdin parsing, no eval.
- settings.json backup kept locally; contains no secrets committed (template only has hooks).

## Next Steps
- Phase 6 tests: state script against isolated tmux server; merge idempotency.
