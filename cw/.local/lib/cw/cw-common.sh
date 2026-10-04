# shellcheck shell=bash
# cw shared helpers: errors, config, name validation, repo + base branch detection.

die() {
  echo "cw: $*" >&2
  exit 1
}
warn() { echo "cw: $*" >&2; }

# Config file is sourced like .bashrc; env vars set by the caller win over it.
load_config() {
  local v file="${XDG_CONFIG_HOME:-$HOME/.config}/cw/config"
  local -A env=()
  for v in CW_ROOT CW_BASE CW_REMOTE CW_CLAUDE_CMD CW_FZF; do
    [ -z "${!v+set}" ] || env[$v]="${!v}"
  done
  # shellcheck source=/dev/null
  [ -f "$file" ] && . "$file"
  for v in "${!env[@]}"; do printf -v "$v" '%s' "${env[$v]}"; done
  : "${CW_ROOT:=$HOME/cw}" "${CW_REMOTE:=origin}" "${CW_CLAUDE_CMD:=claude}" "${CW_FZF:=fzf}"
  CW_ROOT="${CW_ROOT%/}"
}

# Names become branch, dir and tmux window names → keep them boring.
validate_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,48}$ ]] ||
    die "invalid name '$1' (letters, digits, - and _; max 49 chars)"
}

# Main checkout of the repo containing $1 (works from inside any of its worktrees).
repo_main_dir() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "not a git repository: $1"
  [ "$(git -C "$1" rev-parse --is-bare-repository)" = false ] || die "bare repositories are not supported: $1"
  dirname "$common"
}

# Repo name used for $CW_ROOT/<repo> and the tmux session (tmux dislikes . and :).
repo_name() {
  local name
  name="$(basename "$1")"
  echo "${name//[.:]/_}"
}

# Remote new branches start from: $CW_REMOTE, else the only remote, else none
# (prints nothing → local-only repo, branch from a local base).
pick_remote() {
  local main="$1" remotes
  if git -C "$main" remote get-url "$CW_REMOTE" >/dev/null 2>&1; then
    echo "$CW_REMOTE"
    return 0
  fi
  remotes="$(git -C "$main" remote)"
  [ "$(grep -c . <<<"$remotes")" -le 1 ] ||
    die "no remote '$CW_REMOTE' and several others ($(paste -sd' ' <<<"$remotes")); set CW_REMOTE in ~/.config/cw/config"
  echo "$remotes"
}

# Base branch: git config cw.base > $CW_BASE > <remote>/HEAD > main > master.
# With no remote ($2 empty) the candidates are local branches.
detect_base() {
  local main="$1" remote="$2" base prefix="refs/heads"
  [ -z "$remote" ] || prefix="refs/remotes/$remote"
  [ -n "$remote" ] || git -C "$main" rev-parse -q --verify HEAD >/dev/null ||
    die "$main has no commits yet; make a first commit, then run cw new again"
  base="$(git -C "$main" config cw.base || true)"
  [ -n "$base" ] || base="${CW_BASE:-}"
  if [ -z "$base" ] && [ -n "$remote" ]; then
    base="$(git -C "$main" symbolic-ref --short -q "refs/remotes/$remote/HEAD" || true)"
    base="${base#"$remote"/}"
  fi
  if [ -z "$base" ]; then
    local b
    for b in main master; do
      if git -C "$main" show-ref -q --verify "$prefix/$b"; then
        base="$b"
        break
      fi
    done
  fi
  [ -n "$base" ] || die "cannot detect base branch; set it with: git -C '$main' config cw.base <branch>"
  echo "$base"
}

# Offline / SSH hiccups should not block starting a task → warn only.
fetch_base() {
  git -C "$1" fetch -q "$2" "$3" 2>/dev/null ||
    warn "fetch $2/$3 failed; using the last fetched state"
}
