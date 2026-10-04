# shellcheck shell=bash
# cw go [name|repo/name] [-d]   ·   cw close <name|repo/name>

cmd_go() {
  local want="" detach=0 arg
  for arg in "$@"; do
    case "$arg" in
      -d) detach=1 ;;
      -*) die "unknown option: $arg" ;;
      *)
        [ -z "$want" ] || die "usage: cw go [name|repo/name] [-d]"
        want="$arg"
        ;;
    esac
  done

  local dir
  if [ -n "$want" ]; then
    dir="$(resolve_session "$want")"
  else
    dir="$(pick_session)" || exit 1
  fi

  local wid name resume=0
  wid="$(window_for_path "$dir")"
  if [ -z "$wid" ]; then
    name="$(session_name "$dir")"
    claude_project_exists "$dir" && resume=1
    wid="$(window_create "$dir" "$(session_repo "$dir")" "$name" "$resume")"
    [ "$resume" = 1 ] && echo "cw: reopened $name, resuming its Claude conversation"
  fi
  [ "$detach" = 1 ] || focus_window "$wid"
}

# fzf picker over all sessions; without fzf or a terminal, print the list and fail.
pick_session() {
  local rows
  rows="$(session_rows)"
  [ -n "$rows" ] || die "no sessions in $CW_ROOT (start one: cw new <name>)"
  if command -v "$CW_FZF" >/dev/null && [ -t 0 ] && [ -t 2 ]; then
    local line
    line="$("$CW_FZF" --reverse --prompt='cw> ' --delimiter=$'\t' --with-nth=1,2,4 \
      --header='enter: go to session' \
      --preview='git -C {5} log --oneline --decorate -10; echo; git -C {5} status -s' \
      <<<"$rows")" || return 1
    cut -f5 <<<"$line"
  else
    cut -f1,2,4 <<<"$rows" | column -t -s $'\t' >&2
    warn "usage: cw go <name>"
    return 1
  fi
}

cmd_close() {
  [ $# -eq 1 ] || die "usage: cw close <name|repo/name>"
  local dir wid
  dir="$(resolve_session "$1")"
  wid="$(window_for_path "$dir")"
  if [ -z "$wid" ]; then
    echo "cw: $1 is already closed"
    return 0
  fi
  tmux kill-window -t "$wid"
  echo "cw: closed $1 (worktree kept; reopen with: cw go $1)"
}
