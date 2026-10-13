#!/bin/sh
# Install or upgrade UUA without a checkout. Run as your normal user.
set -eu

fail() {
  printf 'uua: %s\n' "$*" >&2
  exit 1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@" </dev/null
  else
    sudo "$@" </dev/null
  fi
}

main() {
  [ "$(uname -s)" = Linux ] || fail 'Only Linux is supported (not macOS).'
  [ -n "${HOME:-}" ] || fail 'HOME is not set.'
  [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ] ||
    fail 'Run without sudo; only dependency installation needs elevated privileges.'

  packages=''
  command -v zsh >/dev/null 2>&1 || packages="$packages zsh"
  command -v curl >/dev/null 2>&1 || packages="$packages curl"
  command -v flock >/dev/null 2>&1 || packages="$packages util-linux"
  command -v timeout >/dev/null 2>&1 || packages="$packages coreutils"
  if [ -n "$packages" ]; then
    command -v apt-get >/dev/null 2>&1 ||
      fail "Install these packages with your package manager, then retry:$packages"
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null 2>&1 || fail "Install these packages as root, then retry:$packages"
      # Authenticate from the terminal, not the script arriving on stdin.
      sudo -v
    fi
    printf 'Installing missing dependencies:%s\n' "$packages"
    as_root apt-get update
    # Package names above are a fixed list, deliberately split into arguments.
    as_root apt-get install -y $packages
  fi
  zsh -fc 'autoload -Uz is-at-least; is-at-least 5.0 "$ZSH_VERSION"' ||
    fail 'zsh 5.0 or newer is required.'

  bindir="$HOME/.local/bin"
  mkdir -p "$bindir"
  [ ! -d "$bindir/uua" ] || fail "$bindir/uua is a directory."
  tmp=$(mktemp "$bindir/.uua-install.XXXXXX")
  trap 'rm -f -- "$tmp"' 0
  trap 'exit 1' HUP INT TERM

  printf 'Downloading UUA...\n'
  curl --fail --silent --show-error --location --connect-timeout 15 --max-time 120 \
    --retry 2 --proto '=https' --proto-redir '=https' \
    https://raw.githubusercontent.com/roy-tian/uua/master/uua -o "$tmp"
  [ -s "$tmp" ] || fail 'Downloaded script is empty; existing installation was not changed.'
  zsh -n "$tmp" || fail 'Downloaded script failed syntax validation.'
  # -f keeps rc files' startup chatter out of the captured version.
  version=$(zsh -f "$tmp" --version)
  case "$version" in
    'UUA '[0-9]*) ;;
    *) fail 'Downloaded script did not report a UUA version.' ;;
  esac
  chmod 755 "$tmp"
  # Replace a previous file or development symlink, never its target.
  mv -fT -- "$tmp" "$bindir/uua"

  # Persist PATH for the user's shell. The line is safe to source repeatedly.
  case "${SHELL:-}" in
    */zsh)
      # .zshenv may set ZDOTDIR without exporting it to this sh process.
      # Keep startup chatter out of the captured path, and stdin out of the pipe.
      rc=$(zsh -c 'print -r -u 3 -- "${ZDOTDIR:-$HOME}/.zshrc"' \
        3>&1 1>/dev/null </dev/null) || :
      # A .zshenv that quits non-interactive shells yields nothing here;
      # uua is installed by now, so default instead of failing the run.
      [ -n "$rc" ] || rc="${ZDOTDIR:-$HOME}/.zshrc"
      ;;
    */bash) rc="$HOME/.bashrc" ;;
    *) rc="$HOME/.profile" ;;
  esac
  path_line='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
  if ! grep -Fqx "$path_line" "$rc" 2>/dev/null; then
    mkdir -p "$(dirname "$rc")"
    printf '\n# UUA: user-local commands\n%s\n' "$path_line" >>"$rc"
  fi

  printf '\nInstalled %s to %s/uua\n' "$version" "$bindir"
  printf 'PATH configured in %s. Open a new terminal, then run: uua --check\n' "$rc"
  printf 'Or run now: "%s/uua" --check\n' "$bindir"
  printf 'Run this installer again to upgrade UUA.\n'
}

# Keep execution last so a truncated download cannot run a partial main body.
main "$@"
