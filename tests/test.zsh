#!/usr/bin/env zsh

# Tests for uua. They source the script (which then runs nothing) and
# drive its functions against stub commands, so no network, sudo or real
# package manager is touched. Run with `make test`.

ROOT="${0:A:h:h}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state"
export NO_COLOR=1
mkdir -p "$XDG_STATE_HOME/uua" "$TMP/bin"

source "$ROOT/uua"

_init_colors

integer passed=0 failed=0


expect() {
  local name="$1"
  local want="$2"
  local got="$3"

  if [[ "$want" == "$got" ]]; then
    (( passed++ ))
  else
    (( failed++ ))
    print -r -- "FAIL: $name"
    print -r -- "  want: ${(q+)want}"
    print -r -- "  got:  ${(q+)got}"
  fi
}


# Writes an executable stub script.
stub() {
  print -r -- "#!/bin/sh" >"$TMP/bin/$1"
  print -r -- "$2" >>"$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}


# ── Version comparison ──────────────────────────────────────

needs() {
  _ver_needs_update "$1" "$2" && print yes || print no
}

expect "patch bump"               yes "$(needs 1.2.3 1.2.4)"
expect "older latest"             no  "$(needs 1.2.4 1.2.3)"
expect "equal"                    no  "$(needs 1.2.3 1.2.3)"
expect "numeric, not lexical"     yes "$(needs 2.0.9 2.0.10)"
expect "prerelease to its final"  yes "$(needs 1.3.0-beta.1 1.3.0)"
expect "prerelease ahead"         no  "$(needs 1.3.0-beta.1 1.2.9)"
expect "prerelease behind"        yes "$(needs 1.2.0-rc.1 1.3.0)"
expect "prerelease target refused" no "$(needs 1.2.3 1.3.0-beta.1)"
expect "build metadata ignored"   no  "$(needs 1.2.3+build5 1.2.3)"
expect "unknown current"          no  "$(needs '' 1.0.0)"

expect "version from a banner" 0.46.0  "$(_uua_ver print 'codex-cli 0.46.0')"
expect "version with v prefix" 24.21.0 "$(_uua_ver print v24.21.0)"
expect "version before a name" 2.1.284 "$(_uua_ver print '2.1.284 (Claude Code)')"


# ── nvm default alias ───────────────────────────────────────

# What "nvm version default" resolves to, for _default_should_follow.
nvm() {
  [[ "$1" == version ]] && print -r -- "$FAKE_DEFAULT"
}

follows() {
  FAKE_DEFAULT="$2"
  _default_should_follow "$1" "$3" && print move || print keep
}

expect "alias: unset"                     move "$(follows ''         N/A)"
expect "alias: dangling"                  move "$(follows 22         N/A)"
expect "alias: pinned major"              keep "$(follows 22         v22.20.0)"
expect "alias: pinned LTS line"           keep "$(follows lts/iron   v20.19.0)"
expect "alias: system"                    keep "$(follows system     system)"
expect "alias: the replaced release"      move "$(follows v22.20.0   v22.20.0 22.20.0)"
expect "alias: that release, no upgrade"  keep "$(follows v22.20.0   v22.20.0)"
expect "alias: another release"           keep "$(follows v20.1.0    v20.1.0  22.20.0)"

unfunction nvm


# ── Global package listings ─────────────────────────────────

npm() {
  cat "$TMP/npm-ls.json"
}

cat >"$TMP/npm-ls.json" <<'EOF'
{
  "dependencies": {
    "linked":     { "version": "1.0.0", "resolved": "file:../../../code/linked" },
    "from-git":   { "version": "1.0.0", "resolved": "git+ssh://git@github.com/a/b.git#abc" },
    "is-odd":     { "version": "2.0.0" },
    "typescript": { "version": "5.0.0", "resolved": "https://registry.npmjs.org/typescript/-/typescript-5.0.0.tgz" },
    "missing":    { "required": "^1.0.0", "missing": true }
  }
}
EOF

expect "npm: registry packages only" \
  $'is-odd 2.0.0\ntypescript 5.0.0' "$(_npm_global_packages)"

print -r -- "not json" >"$TMP/npm-ls.json"
_npm_global_packages >/dev/null 2>&1
expect "npm: unreadable listing fails" 1 $?

unfunction npm

# A quote in the path would have broken the old string-spliced script.
BUN_INSTALL="$TMP/bun's"
mkdir -p "$BUN_INSTALL/install/global/node_modules/typescript" \
  "$BUN_INSTALL/install/global/node_modules/@tobilu/qmd"

cat >"$BUN_INSTALL/install/global/package.json" <<'EOF'
{
  "dependencies": {
    "@tobilu/qmd": "https://github.com/tobi/qmd",
    "typescript": "^5.0.0",
    "linked": "link:linked",
    "shorthand": "user/repo"
  }
}
EOF

print -r -- '{"version": "5.1.0"}' \
  >"$BUN_INSTALL/install/global/node_modules/typescript/package.json"
print -r -- '{"version": "0.3.0"}' \
  >"$BUN_INSTALL/install/global/node_modules/@tobilu/qmd/package.json"

expect "bun: registry packages only" "typescript 5.1.0" "$(_bun_global_packages)"

unset BUN_INSTALL


# ── Outdated detection ──────────────────────────────────────

stub npm '
case "$1" in
  view)
    case "$2" in
      foo) echo 2.0.0 ;;
      bar) echo 1.0.0 ;;
      @anthropic-ai/claude-code) echo 2.0.0 ;;
    esac ;;
  root) echo "'"$TMP"'/npm-root" ;;
esac'

path=("$TMP/bin" $path)

expect "outdated: owned packages skipped" "foo 1.0.0 2.0.0" \
  "$(print -l 'foo 1.0.0' 'bar 1.0.0' '@anthropic-ai/claude-code 1.0.0' 'npm 1.0.0' |
       _outdated_packages)"

print 'unknown 1.0.0' | _outdated_packages >/dev/null
expect "outdated: registry unreachable fails" 1 $?

lister() {
  print -l 'foo 2.0.0' 'bar 1.0.0'
}

expect "still outdated: missing or behind" gone \
  "$(_still_outdated lister $'foo 1.0.0 2.0.0\nbar 0.9.0 1.0.0\ngone 1.0.0 2.0.0')"


# ── AI CLI workers ──────────────────────────────────────────

_UUA_RUN_DIR="$TMP/run"
mkdir -p "$_UUA_RUN_DIR"

stub faketool '
case "$1" in
  --version) cat "'"$TMP"'/fake-version" ;;
  update)
    echo "fake updater says hi"
    [ -f "'"$TMP"'/fake-bump" ] && echo 2.0.0 >"'"$TMP"'/fake-version"
    exit 0 ;;
esac'

stub fakeext 'echo "Updating ext-a"; echo Updated'
stub brokenext 'exit 1'

_fake_latest() {
  print 2.0.0
}

worker() {
  rm -f "$_UUA_RUN_DIR"/fake*(N)
  _worker_tool fake "$1" _fake_latest self "faketool update" "${2:-}" "" ""
  print -r -- "$(<"$_UUA_RUN_DIR/fake.result")"
}

print 1.0.0 >"$TMP/fake-version"
touch "$TMP/fake-bump"
expect "worker: upgraded" "updated|1.0.0|2.0.0|" "$(worker faketool)"

print 1.0.0 >"$TMP/fake-version"
rm -f "$TMP/fake-bump"
expect "worker: updater that does not move" \
  "failed|1.0.0|2.0.0|updater finished but faketool is still 1.0.0" "$(worker faketool)"

print 2.0.0 >"$TMP/fake-version"
expect "worker: up to date" "ok|2.0.0|2.0.0|" "$(worker faketool)"

print 1.0.0 >"$TMP/fake-version"
_UUA_CHECK_ONLY=1
expect "worker: check mode" "available|1.0.0|2.0.0|" "$(worker faketool)"
_UUA_CHECK_ONLY=0

expect "worker: not installed" "absent" "$(worker no-such-tool)"

print 2.0.0 >"$TMP/fake-version"
worker faketool fakeext >/dev/null
expect "extensions: upgraded" updated "$(<"$_UUA_RUN_DIR/fake-ext.result")"

expect "extensions: failure leaves the tool alone" "ok|2.0.0|2.0.0|" \
  "$(worker faketool brokenext)"
expect "extensions: failure is its own result" failed \
  "$(<"$_UUA_RUN_DIR/fake-ext.result")"


# ── Pruning ─────────────────────────────────────────────────

export CODEX_HOME="$TMP/codex"
releases="$CODEX_HOME/packages/standalone/releases"

for r in r1 r2 r3; do
  mkdir -p "$releases/$r/bin"
  touch "$releases/$r/codex-package.json"
done

mkdir -p "$releases/not-a-release"
ln -s "$releases/r3" "$CODEX_HOME/packages/standalone/current"

expect "codex: stale releases counted" 2 "$(_codex_prune count)"

# A process running from r1 keeps it.
cp "$(command -v sleep)" "$releases/r1/bin/sleep"
"$releases/r1/bin/sleep" 30 &
busy=$!
sleep 0.2

expect "codex: releases in use kept" 1 "$(_codex_prune remove)"
expect "codex: what is left" "not-a-release r1 r3" "${(j: :)${(@f)$(ls "$releases")}}"

kill "$busy" 2>/dev/null
wait "$busy" 2>/dev/null

unset CODEX_HOME


# ── Processes ───────────────────────────────────────────────

(
  sh -c 'sleep 31.5 & sleep 31.5'
  :
) &
tree=$!
sleep 0.2

_kill_tree "$tree"
wait "$tree" 2>/dev/null
expect "kill tree: no grandchild survives" "" "$(pgrep -f 'sleep 31.5')"

started=$SECONDS
_run_spinner "slow" "$TMP/slow.log" 1 sleep 20 2>/dev/null
expect "spinner: time limit" 124 $?
expect "spinner: stopped promptly" 1 "$(( SECONDS - started < 5 ))"
expect "spinner: limit logged" "uua: stopped after 1s without finishing" "$(<"$TMP/slow.log.err")"

_run_spinner "quick" "$TMP/quick.log" 0 sh -c 'echo out; echo err >&2; exit 3' 2>/dev/null
expect "spinner: foreground status" 3 $?
expect "spinner: stdout apart from stderr" "out" "$(<"$TMP/quick.log")"


sleep 30 &
child=$!
expect "child: own child recognized" 0 "$(_is_my_child "$child"; print $?)"
kill "$child"
wait "$child" 2>/dev/null
expect "child: reaped pid refused" 1 "$(_is_my_child "$child"; print $?)"
expect "child: unrelated process refused" 1 "$(_is_my_child 1; print $?)"


# ── --verbose ───────────────────────────────────────────────

has() {
  [[ "$1" == *"$2"* ]] && print yes || print no
}

_UUA_VERBOSE=1

out="$(_run_spinner "loud" "$TMP/loud.log" 5 sh -c 'echo out; echo err >&2; printf last' 2>/dev/null)"
expect "verbose: stdout shown" yes "$(has "$out" "   out")"
expect "verbose: stderr shown" yes "$(has "$out" "   err")"
expect "verbose: unterminated last line shown" yes "$(has "$out" "   last")"
expect "verbose: stdout log" $'out\nlast' "$(<"$TMP/loud.log")"
expect "verbose: stderr log" err "$(<"$TMP/loud.log.err")"
expect "verbose: no follower left behind" "" "$_UUA_FOLLOW"

out="$(_run_spinner "loud fg" "$TMP/loud-fg.log" 0 sh -c 'echo fg-out; exit 4' 2>/dev/null; print "rc=$?")"
expect "verbose: foreground output shown" yes "$(has "$out" "   fg-out")"
expect "verbose: foreground status kept" yes "$(has "$out" "rc=4")"

out="$(_run_spinner "loud slow" "$TMP/loud-slow.log" 1 sh -c 'echo before; sleep 20' 2>/dev/null; print "rc=$?")"
expect "verbose: time limit still applies" yes "$(has "$out" "rc=124")"
expect "verbose: output before the limit shown" yes "$(has "$out" "   before")"

# The parallel stage labels each worker's lines with its log's name.
print 1.0.0 >"$TMP/fake-version"
touch "$TMP/fake-bump"
rm -f "$_UUA_RUN_DIR"/fake*(N)

out="$(
  _UUA_TOOLS=('fake|Fake|faketool|_fake_latest|self|faketool update|||')
  _parallel_tools 2>/dev/null
)"
expect "verbose: worker output labelled" yes "$(has "$out" "   [fake] fake updater says hi")"
expect "verbose: worker still reported" yes "$(has "$out" "Fake: 1.0.0 → 2.0.0 (upgraded)")"

_UUA_VERBOSE=0

out="$(_run_spinner "quiet" "$TMP/quiet.log" 5 sh -c 'echo hidden' 2>/dev/null)"
expect "quiet: output only in the log" "" "$out"


# ── Run lock ────────────────────────────────────────────────

_acquire_run_lock
expect "lock: acquired" 0 $?

_UUA_HAVE_RUN_LOCK=0
_acquire_run_lock
expect "lock: held by a live run" "1 $$" "$? $REPLY"

true &
dead=$!
wait "$dead"
print -r -- "$dead" >"$_UUA_RUN_LOCK/pid"

_acquire_run_lock
expect "lock: reclaimed from a dead run" 0 $?

_release_run_lock
expect "lock: released" no "$([[ -e "$_UUA_RUN_LOCK" ]] && print yes || print no)"


# ── Command line ────────────────────────────────────────────

expect "cli: version" "UUA 0.1.0" "$(zsh "$ROOT/uua" --version)"
expect "cli: --verbose accepted" "UUA 0.1.0" "$(zsh "$ROOT/uua" --verbose --version)"

zsh "$ROOT/uua" --bogus 2>/dev/null
expect "cli: unknown option" 2 $?

stub claude 'echo "1.0.0 (Claude Code)"'

# No nvm here: an AI-only run switches to nvm's default Node, which
# would pull the real tools and npm back onto PATH.
out="$(PATH="$TMP/bin:/usr/bin:/bin" NVM_DIR="$TMP/no-nvm" zsh "$ROOT/uua" --check --ai 2>/dev/null)"
expect "cli: --check exits 100 when updates exist" 100 $?
expect "cli: --check reports the update" yes \
  "$([[ "$out" == *"Claude Code: 1.0.0 → 2.0.0 (update available)"* ]] && print yes || print no)"
expect "cli: absent tools are listed, not counted" yes \
  "$([[ "$out" == *"-  Codex: not installed"* && "$out" == *"Summary: 1 item(s)"* ]] && print yes || print no)"


print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
