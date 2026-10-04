# dotfiles

Packages are installed with [GNU stow](https://www.gnu.org/software/stow/).

```bash
./install.sh          # cw + tmux (default)
./install.sh nvim     # only the listed packages
```

Re-running is safe. Real files in the way are moved to `~/.dotfiles-backup/<timestamp>/`.

| Package | What |
|---|---|
| `cw`   | `cw` command: parallel Claude Code sessions in tmux |
| `tmux` | tmux config (prefix `C-a`), fzf session picker |
| `nvim` | Neovim config |

## cw

One task = one git worktree + one branch + one tmux window + one Claude conversation.
Sessions live in `~/cw/<repo>/<name>`; the tmux session is named after the repo.

```bash
cd ~/work/myrepo
cw new fix-login        # worktree + branch fix-login from origin/<base>, window, Claude
cw go                   # fzf picker over all sessions
cw go fix-login         # jump to it (reopens + resumes Claude if it was closed)
cw close fix-login      # close the window; worktree and branch stay
cw ls                   # list sessions
cw rm fix-login         # delete worktree + branch (refuses if open, dirty or unmerged;
                        # --force overrides all three)
```

Config: `~/.config/cw/config` (created from `templates/cw-config.example`).
Base branch per repo: `git config cw.base <branch>`.
Remote: `origin`, else the repo's only remote; repos without a remote branch from local `main`/`master`.

## tmux keys (prefix `C-a`)

| Keys | Action |
|---|---|
| `C-a d` | detach (everything keeps running; `tmux attach` or `cw go` to return) |
| `C-a s` | fzf session picker (`ctrl-r` renames) |
| `C-a n` / `C-a p` | next / previous window |
| `C-a w` | tree of all sessions and windows |
| `C-a \|` / `C-a -` | split side by side / top and bottom |
| `C-a h/j/k/l` | move between panes; `H/J/K/L` resize |
| `C-a z` | zoom the current pane (toggle) |
| `C-a [` | scroll / copy mode (`v` select, `y` copy, `q` quit) |
| `C-a r` | reload tmux config |
