#!/usr/bin/env bash
# Install dotfiles packages with GNU stow. Safe to re-run.
#   ./install.sh            → default packages (cw tmux)
#   ./install.sh nvim       → only the listed packages
# Conflicting real files are moved to ~/.dotfiles-backup/<timestamp>/, never deleted.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DEFAULT_PKGS=(cw tmux)
# Already stowed as whole-dir symlinks (~/.config/nvim → dotfiles); keep them folded.
FOLDED_PKGS=" nvim tmux "

die() {
  echo "install: $*" >&2
  exit 1
}
warn() { echo "install: warning: $*" >&2; }

pkg_hint() {
  if grep -qi arch /etc/os-release 2>/dev/null; then
    echo "sudo pacman -S $*"
  elif grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    echo "sudo apt install $*"
  else
    echo "install: $*"
  fi
}

check_deps() {
  local missing=() t
  for t in git tmux jq stow; do command -v "$t" >/dev/null || missing+=("$t"); done
  [ ${#missing[@]} -eq 0 ] || die "missing required tools → $(pkg_hint "${missing[@]}")"
  missing=()
  for t in fzf shellcheck; do command -v "$t" >/dev/null || missing+=("$t"); done
  [ ${#missing[@]} -eq 0 ] || warn "optional tools missing → $(pkg_hint "${missing[@]}")"
  # Popups (fzf pickers) need tmux >= 3.2.
  local v
  v="$(tmux -V | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
  [ -z "$v" ] || printf '3.2\n%s\n' "$v" | sort -V -C || warn "tmux $v < 3.2: popups will not work"
  # cw uses `git rev-parse --path-format=absolute` (git >= 2.31).
  v="$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
  [ -z "$v" ] || printf '2.31\n%s\n' "$v" | sort -V -C || die "git $v is too old for cw (need >= 2.31)"
}

# Move real files that would block stow out of the way.
backup_conflicts() {
  local pkg="$1" src rel target
  while IFS= read -r src; do
    rel="${src#"$DOTFILES/$pkg/"}"
    target="$HOME/$rel"
    [ -e "$target" ] || [ -L "$target" ] || continue
    case "$(readlink -f "$target")" in "$DOTFILES"/*) continue ;; esac
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$target" "$BACKUP_DIR/$rel"
    echo "  backed up ~/$rel → $BACKUP_DIR/$rel"
  done < <(find "$DOTFILES/$pkg" \( -type f -o -type l \))
}

stow_pkg() {
  local pkg="$1" flags=(--restow -d "$DOTFILES" -t "$HOME")
  [ -d "$DOTFILES/$pkg" ] || die "no package '$pkg' in $DOTFILES"
  # --no-folding: never turn shared dirs like ~/.local/bin into a symlink into dotfiles.
  [[ "$FOLDED_PKGS" == *" $pkg "* ]] || flags+=(--no-folding)
  backup_conflicts "$pkg"
  stow "${flags[@]}" "$pkg"
  echo "stowed $pkg"
}

main() {
  local pkgs=("$@")
  [ ${#pkgs[@]} -gt 0 ] || pkgs=("${DEFAULT_PKGS[@]}")
  check_deps
  # Without these, stow would fold the whole dir into a symlink into dotfiles and
  # machine-specific files (e.g. ~/.config/cw/config) would land inside the repo.
  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/lib"
  local p
  for p in "${pkgs[@]}"; do stow_pkg "$p"; done

  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/cw/config"
  if [[ " ${pkgs[*]} " == *" cw "* ]] && [ ! -f "$cfg" ]; then
    install -Dm600 "$DOTFILES/templates/cw-config.example" "$cfg"
    echo "created $cfg (edit per machine)"
  fi

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not in PATH; add to your shell rc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
  [ ! -d "$BACKUP_DIR" ] || echo "backups in $BACKUP_DIR"
}

main "$@"
