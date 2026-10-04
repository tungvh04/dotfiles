# shellcheck shell=bash
# cw rm <name|repo/name> [--force]
# Deletes a session: worktree dir + branch (+ tmux window with --force).

cmd_rm() {
  local want="" force=0 arg
  for arg in "$@"; do
    case "$arg" in
      -f | --force) force=1 ;;
      -*) die "unknown option: $arg" ;;
      *)
        [ -z "$want" ] || die "usage: cw rm <name|repo/name> [--force]"
        want="$arg"
        ;;
    esac
  done
  [ -n "$want" ] || die "usage: cw rm <name|repo/name> [--force]"

  local dir main branch wid
  dir="$(resolve_session "$want")"
  main="$(repo_main_dir "$dir")"
  branch="$(session_branch_ref "$dir")"
  wid="$(window_for_path "$dir")"

  if [ "$force" = 0 ]; then
    [ -z "$wid" ] || die "$want is open; close it first (cw close $want) or use --force"
    local status ignored unsaved
    # -unormal: ignore a user's status.showUntrackedFiles=no; ignored dirs stay collapsed.
    status="$(git -C "$dir" status --porcelain -unormal --ignored)" || die "git status failed in $dir"
    grep -qvE '^(!! |$)' <<<"$status" &&
      die "$want has uncommitted changes (git -C '$dir' status); commit them or use --force"
    # Ignored *files* (.env, local db, credentials) are often irreplaceable; ignored
    # *dirs* (node_modules/, dist/) are rebuildable and do not block.
    ignored="$(sed -n 's/^!! //p' <<<"$status" | grep -v '/$' || true)"
    if [ -n "$ignored" ]; then
      warn "$want has gitignored files that would be deleted:"
      head -5 <<<"$ignored" | sed 's/^/  /' >&2
      die "copy them somewhere safe, or use --force"
    fi
    unsaved="$(unsaved_commits "$dir" "$main")"
    if [ -n "$unsaved" ]; then
      warn "$want has commits that are not in the base branch or on any remote:"
      head -5 <<<"$unsaved" | sed 's/^/  /' >&2
      die "merge or push them, or use --force to delete them"
    fi
  fi

  # Remove first, close the window last: with --force from inside that window,
  # killing it earlier would kill this cw process mid-way.
  local flags=()
  [ "$force" = 0 ] || flags=(--force)
  git -C "$main" worktree remove "${flags[@]}" "$dir" || die "git worktree remove failed"
  # Only delete the session's own branch: if the worktree was switched to e.g.
  # master or another existing branch, that branch must survive.
  local removed_branch=""
  if [ -n "$branch" ] && [ "$branch" = "$(session_id "$dir")" ]; then
    if git -C "$main" branch -q -D "$branch"; then
      removed_branch="$branch"
    else
      warn "worktree removed but branch '$branch' could not be deleted"
    fi
  elif [ -n "$branch" ]; then
    warn "kept branch '$branch' (not this session's own branch)"
  fi
  rmdir "$(dirname "$dir")" 2>/dev/null || true
  echo "cw: removed $want (${removed_branch:+branch $removed_branch, }$dir)"
  [ -z "$wid" ] || tmux kill-window -t "$wid"
}

# Commits in the session not reachable from any remote-tracking branch or the
# local base branch, i.e. work that would be lost. One "sha subject" per line.
unsaved_commits() {
  local dir="$1" main="$2" remote base keep=(--remotes)
  remote="$(pick_remote "$main" 2>/dev/null || true)"
  base="$(detect_base "$main" "$remote" 2>/dev/null || true)"
  [ -z "$base" ] || ! git -C "$main" show-ref -q --verify "refs/heads/$base" ||
    keep+=("refs/heads/$base")
  git -C "$dir" log --oneline HEAD --not "${keep[@]}"
}
