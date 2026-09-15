#!/usr/bin/env bash
# Pick a tmux session with fzf and switch to it.
#   enter   switch to session
#   ctrl-r  rename highlighted session
set -euo pipefail

self=$(realpath "$0")
list_cmd="tmux list-sessions -F '#{session_name}'"

# Subcommand used by the fzf ctrl-r binding
if [ "${1:-}" = "rename" ]; then
  old=$2
  read -r -p "Rename '$old' to: " new </dev/tty
  [ -n "$new" ] && tmux rename-session -t "=$old" "$new"
  exit 0
fi

session=$(
  eval "$list_cmd" |
    fzf --reverse --prompt='session> ' \
      --header='enter: switch · ctrl-r: rename' \
      --preview='tmux capture-pane -ep -t ={}' --preview-window=right:60% \
      --bind="ctrl-r:execute('$self' rename {})+reload($list_cmd)+clear-query"
) || exit 0

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$session"
else
  tmux attach-session -t "=$session"
fi
