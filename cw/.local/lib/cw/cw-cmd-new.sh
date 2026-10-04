# shellcheck shell=bash
# cw new <name> [repo-path] [-d]

cmd_new() {
  local name="" repo_arg="" detach=0 arg
  for arg in "$@"; do
    case "$arg" in
      -d) detach=1 ;;
      -*) die "unknown option: $arg" ;;
      *)
        if [ -z "$name" ]; then
          name="$arg"
        elif [ -z "$repo_arg" ]; then
          repo_arg="$arg"
        else
          die "usage: cw new <name> [repo-path] [-d]"
        fi
        ;;
    esac
  done
  [ -n "$name" ] || die "usage: cw new <name> [repo-path] [-d]"
  validate_name "$name"

  local main repo dir remote base start
  main="$(repo_main_dir "${repo_arg:-$PWD}")"
  repo="$(repo_name "$main")"
  dir="$CW_ROOT/$repo/$name"

  [ ! -e "$dir" ] || die "$dir already exists (resume it: cw go $repo/$name)"
  ! git -C "$main" show-ref -q --verify "refs/heads/$name" ||
    die "branch '$name' already exists in $main"
  check_repo_dir_owner "$main" "$repo"

  # Remote repo → branch tracks <remote>/<base>; local-only repo → branch from local <base>.
  remote="$(pick_remote "$main")"
  base="$(detect_base "$main" "$remote")"
  local track=()
  if [ -n "$remote" ]; then
    fetch_base "$main" "$remote" "$base"
    start="$remote/$base"
    track=(--track)
  else
    start="$base"
  fi
  git -C "$main" rev-parse -q --verify "$start^{commit}" >/dev/null ||
    die "$start not found; fetch it or set: git -C '$main' config cw.base <branch>"

  mkdir -p "$CW_ROOT/$repo"
  git -C "$main" worktree add -q "${track[@]}" -b "$name" "$dir" "$start" ||
    die "git worktree add failed"
  echo "cw: $repo/$name → $dir (branch $name from $start)"

  local wid
  wid="$(window_create "$dir" "$repo" "$name" 0)" ||
    die "worktree created but tmux window failed; retry with: cw go $repo/$name"
  [ "$detach" = 1 ] || focus_window "$wid"
}

# Two different repos with the same folder name would share $CW_ROOT/<repo> → refuse.
check_repo_dir_owner() {
  local main="$1" repo="$2" d other
  for d in "$CW_ROOT/$repo"/*/; do
    [ -f "$d/.git" ] || continue
    # Stale/pruned worktree dirs must not block new sessions.
    other="$(repo_main_dir "$d" 2>/dev/null)" || continue
    [ "$other" = "$main" ] ||
      die "$CW_ROOT/$repo already holds sessions of $other (same folder name as $main)"
    return 0
  done
}
