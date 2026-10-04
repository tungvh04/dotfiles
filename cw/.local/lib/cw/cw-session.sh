# shellcheck shell=bash
# cw session discovery: a session is any git worktree at $CW_ROOT/<repo>/<id>.

# Print every session dir (no trailing slash), one per line.
list_session_dirs() {
  local d
  for d in "$CW_ROOT"/*/*/; do
    [ -f "$d/.git" ] && echo "${d%/}"
  done
  return 0
}

session_id() { basename "$1"; }
session_repo() { basename "$(dirname "$1")"; }
# Branch name, or empty when detached. Strips refs/heads/ itself because
# --short prints "heads/x" when a tag with the same name exists.
session_branch_ref() {
  local ref
  ref="$(git -C "$1" symbolic-ref -q HEAD || true)"
  echo "${ref#refs/heads/}"
}
session_branch() {
  local b
  b="$(session_branch_ref "$1")"
  echo "${b:-(detached)}"
}

# Display name: optional label in branch.<b>.cwname (set by `cw rename`), else the id.
session_name() {
  local b
  b="$(session_branch_ref "$1")"
  if [ -n "$b" ] && git -C "$1" config "branch.$b.cwname"; then return 0; fi
  session_id "$1"
}

# Resolve "name" or "repo/name" to exactly one session dir, else die.
resolve_session() {
  local want="$1" want_repo="" want_name="$1" d
  if [[ "$want" == */* ]]; then
    want_repo="${want%%/*}"
    want_name="${want#*/}"
  fi
  local matches=()
  while IFS= read -r d; do
    [ -n "$want_repo" ] && [ "$(session_repo "$d")" != "$want_repo" ] && continue
    if [ "$(session_id "$d")" = "$want_name" ] || [ "$(session_name "$d")" = "$want_name" ]; then
      matches+=("$d")
    fi
  done < <(list_session_dirs)
  case "${#matches[@]}" in
    0) die "no session '$want' (see: cw ls)" ;;
    1) echo "${matches[0]}" ;;
    *)
      warn "'$want' is ambiguous, use one of:"
      for d in "${matches[@]}"; do echo "  $(session_repo "$d")/$(session_id "$d")" >&2; done
      exit 1
      ;;
  esac
}

# True if Claude has a saved conversation for this dir (→ resume with --continue).
# Claude stores them in ~/.claude/projects/<real path, non-alnum chars as '-'>/*.jsonl.
claude_project_exists() {
  local p
  p="$(readlink -f "$1")"
  compgen -G "$HOME/.claude/projects/${p//[^A-Za-z0-9]/-}/*.jsonl" >/dev/null
}

# Tab-separated: repo, name, branch, open|closed, dir.
session_rows() {
  local d state
  while IFS= read -r d; do
    state=closed
    [ -n "$(window_for_path "$d")" ] && state=open
    printf '%s\t%s\t%s\t%s\t%s\n' "$(session_repo "$d")" "$(session_name "$d")" \
      "$(session_branch "$d")" "$state" "$d"
  done < <(list_session_dirs)
}

# Hidden helper for shell completion: "name<TAB>repo/name" per session.
# `cw _names open` lists only sessions with an open window.
cmd__names() {
  local only="${1:-}"
  session_rows | awk -F'\t' -v only="$only" 'only != "open" || $4 == "open" { print $2 "\t" $1 "/" $2 }'
}

cmd_ls() {
  [ $# -eq 0 ] || die "usage: cw ls"
  local rows
  rows="$(session_rows)"
  [ -n "$rows" ] || {
    echo "no sessions in $CW_ROOT (start one: cw new <name>)"
    return 0
  }
  { printf 'REPO\tNAME\tBRANCH\tWINDOW\n'; cut -f1-4 <<<"$rows"; } | column -t -s $'\t'
}
