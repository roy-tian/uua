#!/bin/sh
# Installer integration tests: isolated HOME/PATH, no network or real sudo/APT.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
on_exit() {
  # A failed assertion aborts under set -eu before reporting which test
  # broke; this trap is the last chance to keep its installer output.
  status=$?
  if [ "$status" -ne 0 ]; then
    printf 'FAILED (exit %s); installer output follows:\n' "$status" >&2
    [ -n "${home:-}" ] && [ -f "$home/output" ] && sed 's/^/  /' "$home/output" >&2
  fi
  rm -rf -- "$TMP"
}
trap on_exit 0
passed=0

setup() {
  home="$TMP/home-$passed"
  bin="$TMP/bin-$passed"
  mkdir -p "$home" "$bin"
  for tool in mkdir mktemp rm grep dirname chmod mv zsh flock timeout; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_OS:-Linux}"\n' >"$bin/uname"
  printf '#!/bin/sh\necho 1000\n' >"$bin/id"
  cat >"$bin/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then dest=$2; break; fi
  shift
done
case "${DOWNLOAD:-ok}" in
  fail) printf 'partial' >"$dest"; exit 22 ;;
  empty) : >"$dest" ;;
  invalid) printf 'if\n' >"$dest" ;;
  wrong) printf 'echo not-uua\n' >"$dest" ;;
  *) /bin/cp "$ROOT/uua" "$dest" ;;
esac
STUB
  chmod +x "$bin/uname" "$bin/id" "$bin/curl"
}

run() {
  env -i HOME="$home" PATH="$bin" SHELL=/bin/bash ROOT="$ROOT" "$@" \
    /bin/sh "$ROOT/install.sh" >"$home/output" 2>&1
}

ok() {
  passed=$((passed + 1))
  printf 'PASS: %s\n' "$1"
}

setup
run
[ -x "$home/.local/bin/uua" ]
cmp "$ROOT/uua" "$home/.local/bin/uua"
grep -q 'UUA: user-local commands' "$home/.bashrc"
cp "$home/.bashrc" "$home/rc-before"
run
cmp "$home/rc-before" "$home/.bashrc"
# Simulate a fresh shell loading its startup file twice.
actual=$(env -i HOME="$home" PATH=/usr/bin /bin/sh -c '. "$HOME/.bashrc"; . "$HOME/.bashrc"; printf "%s" "$PATH"')
[ "$actual" = "$home/.local/bin:/usr/bin" ]
ok 'install, repeat upgrade and idempotent PATH'

setup
mkdir -p "$home/.local/bin"
printf 'original checkout\n' >"$home/source"
ln -s "$home/source" "$home/.local/bin/uua"
run
[ ! -L "$home/.local/bin/uua" ]
[ "$(cat "$home/source")" = 'original checkout' ]
ok 'replace development symlink without modifying checkout'

for mode in fail empty invalid wrong; do
  setup
  mkdir -p "$home/.local/bin"
  printf 'previous installation\n' >"$home/.local/bin/uua"
  if run DOWNLOAD="$mode"; then
    printf 'FAIL: accepted %s download\n' "$mode" >&2
    exit 1
  fi
  [ "$(cat "$home/.local/bin/uua")" = 'previous installation' ]
  [ "$(find "$home/.local/bin" -name '.uua-install.*' | wc -l)" -eq 0 ]
  ok "reject $mode download and preserve old installation"
done

setup
if run FAKE_OS=Darwin; then exit 1; fi
[ ! -e "$home/.local/bin/uua" ]
ok 'reject unsupported OS'

setup
if run SUDO_USER=someone; then exit 1; fi
grep -q 'Run without sudo' "$home/output"
ok 'reject sudo installation into the wrong HOME'

setup
rm "$bin/zsh"
if run; then exit 1; fi
grep -q 'Install these packages with your package manager' "$home/output"
ok 'missing dependency without APT produces actionable error'

setup
rm "$bin/zsh" "$bin/flock"
cat >"$bin/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/apt-log"
[ "$1" != -v ] || exit 0
exec "$@"
STUB
cat >"$bin/apt-get" <<'STUB'
#!/bin/sh
[ "${APT_FAIL:-0}" = 0 ] || exit 1
if [ "$1" = install ]; then
  /bin/ln -s "$REAL_ZSH" "${PATH}/zsh"
  /bin/ln -s "$REAL_FLOCK" "${PATH}/flock"
fi
STUB
chmod +x "$bin/sudo" "$bin/apt-get"
if run APT_FAIL=1; then exit 1; fi
[ ! -e "$home/.local/bin/uua" ]
run REAL_ZSH="$(command -v zsh)" REAL_FLOCK="$(command -v flock)"
grep -qx 'apt-get install -y zsh util-linux' "$home/apt-log"
[ -x "$home/.local/bin/uua" ]
ok 'install only missing packages; stop on APT failure'

setup
run SHELL=/bin/zsh ZDOTDIR="$home/custom-zsh"
[ -f "$home/custom-zsh/.zshrc" ]
[ ! -e "$home/.bashrc" ]
ok 'respect zsh ZDOTDIR'

setup
mkdir -p "$home/custom zsh"
printf 'ZDOTDIR="$HOME/custom zsh"\n' >"$home/.zshenv"
printf '# Existing user configuration\n' >"$home/custom zsh/.zshrc"
# Zsh honors this variable, but the installer child sh does not inherit it.
env -i HOME="$home" PATH="$bin" SHELL=/bin/zsh ROOT="$ROOT" \
  zsh -c '/bin/sh "$ROOT/install.sh"' >"$home/output" 2>&1
[ ! -e "$home/.zshrc" ]
grep -q 'UUA: user-local commands' "$home/custom zsh/.zshrc"
actual=$(env -i HOME="$home" PATH="$bin" SHELL=/bin/zsh \
  zsh -ic 'command -v uua')
  [ "$actual" = "$home/.local/bin/uua" ]
ok 'resolve unexported ZDOTDIR from .zshenv and find uua in a fresh shell'

setup
printf 'echo "loading dev environment"\n' >"$home/.zshenv"
run SHELL=/bin/zsh
[ -x "$home/.local/bin/uua" ]
grep -q 'UUA: user-local commands' "$home/.zshrc"
ok 'ignore .zshenv output when reading the version'

setup
printf '[[ $- != *i* ]] && exit\n' >"$home/.zshenv"
run SHELL=/bin/zsh
[ -x "$home/.local/bin/uua" ]
grep -q 'UUA: user-local commands' "$home/.zshrc"
ok 'default the rc location when .zshenv quits non-interactive shells'

printf '\n%s installer tests passed.\n' "$passed"
