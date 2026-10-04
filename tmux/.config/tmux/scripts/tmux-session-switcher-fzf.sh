#!/usr/bin/env bash
# Pick a tmux session or window with fzf and switch to it.
# Sessions are listed with their windows indented below (same colors as C-a w).
#   type to filter · ctrl-n/ctrl-p (or arrows) move · esc/ctrl-c quit
#   enter   switch to the highlighted session / window
#   ctrl-r  rename the highlighted session / window
set -euo pipefail

self=$(realpath "$0")

# One line per session and per window: "<target id>\t<colored label>".
list() {
  local cur
  cur=$(tmux display -p '#{window_id}' 2>/dev/null || true)
  tmux list-windows -a -F \
    '#{session_id}	#{session_name}	#{session_windows}	#{session_attached}	#{window_id}	#{window_index}	#{window_name}	#{window_panes}' |
    awk -F'\t' -v cur="$cur" '
      function rgb(r, g, b) { return sprintf("\033[38;2;%d;%d;%dm", r, g, b) }
      BEGIN { green = rgb(152,195,121); blue = rgb(97,175,239); grey = rgb(92,99,112)
              yellow = rgb(229,192,123); bold = "\033[1m"; off = "\033[0m" }
      $1 != sid {
        sid = $1; n = 0
        printf "%s\t%s%s󰆍 %s%s  %s%d window%s%s\n", $1, green, bold, $2, off, grey, $3,
          ($3 > 1 ? "s" : ""), ($4 > 0 ? yellow "  attached" off : off)
      }
      {
        n++
        printf "%s\t  %s%s %s %d %s%s%s%s\n", $5, grey, (n == $3 ? "└─" : "├─"), blue, $6, $7,
          ($8 > 1 ? grey "  " $8 " panes" : ""), ($5 == cur ? yellow "  ●" : ""), off
      }'
}

case "${1:-}" in
  list)
    list
    exit 0
    ;;
  rename) # Subcommand used by the fzf ctrl-r binding; $2 = session ($id) or window (@id)
    target=$2
    if [[ "$target" == @* ]]; then kind=window; else kind=session; fi
    old=$(tmux display -p -t "$target" "#{${kind}_name}")
    read -r -p "Rename $kind '$old' to: " new </dev/tty
    [ -z "$new" ] || tmux "rename-$kind" -t "$target" "$new"
    exit 0
    ;;
esac

lines=$(list)
# Start with the cursor on the current window.
start=$(awk -F'\t' -v cur="$(tmux display -p '#{window_id}')" '$1 == cur { print NR; exit }' <<<"$lines")

target=$(
  fzf --ansi --reverse --highlight-line --prompt='switch> ' \
    --delimiter='\t' --with-nth=2 \
    --header=$'ctrl-n/p move · enter switch\nctrl-r rename · esc quit' \
    --bind="load:pos(${start:-1})" \
    --preview='tmux capture-pane -ep -t {1}' --preview-window=right:60% \
    --bind="ctrl-r:execute('$self' rename {1})+reload('$self' list)+clear-query" \
    <<<"$lines" | cut -f1
) || exit 0

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$target"
else
  tmux attach-session -t "$target"
fi
