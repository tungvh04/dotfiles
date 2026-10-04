# shellcheck shell=bash
# cw tmux helpers. One tmux session per repo, one window per cw session.
# Windows are found by their @cw_path option (stable), never by window name.

# Window id (e.g. @12) showing session dir $1, or nothing (also when no tmux server runs).
window_for_path() {
  { tmux list-windows -a -F "#{window_id}	#{@cw_path}" 2>/dev/null || true; } |
    awk -F'\t' -v p="$1" '$2 == p { print $1; exit }'
}

# Command line that starts (or resumes) Claude, safely quoted for send-keys.
claude_start_cmd() {
  local name="$1" resume="$2" cmd
  # CW_CLAUDE_CMD may carry simple flags (e.g. "claude --model opus") → split on
  # whitespace on purpose, with globbing off. Quotes inside it are not supported.
  set -f
  # shellcheck disable=SC2206
  local argv=($CW_CLAUDE_CMD)
  set +f
  [ "$resume" = 1 ] && argv+=(--continue)
  argv+=(-n "$name")
  cmd="$(printf '%q ' "${argv[@]}")"
  echo "${cmd% }"
}

# Open a window for session dir $1 in tmux session $2 (created if missing), start Claude.
# Starts a shell first and types the claude command into it, so the window
# survives Claude exiting and you can see its last output.
window_create() {
  local dir="$1" sess="$2" name="$3" resume="$4" wid
  if tmux has-session -t "=$sess" 2>/dev/null; then
    wid="$(tmux new-window -d -P -F '#{window_id}' -t "=$sess:" -n "$name" -c "$dir")"
  else
    wid="$(tmux new-session -d -P -F '#{window_id}' -s "$sess" -n "$name" -c "$dir")"
  fi
  tmux set-option -w -t "$wid" @cw_path "$dir"
  tmux send-keys -t "$wid" -l -- "$(claude_start_cmd "$name" "$resume")"
  tmux send-keys -t "$wid" Enter
  echo "$wid"
}

# Show window $1: switch inside tmux, attach from a plain terminal.
focus_window() {
  local wid="$1"
  tmux select-window -t "$wid"
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$wid" 2>/dev/null || warn "no tmux client to switch; window is $wid"
  elif [ -t 0 ] && [ -t 1 ]; then
    tmux attach-session -t "$wid"
  else
    warn "not in a terminal; attach with: tmux attach -t '$wid'"
  fi
}
