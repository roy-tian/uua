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
path=("$TMP/bin" $path)

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


has() {
  [[ "$1" == *"$2"* ]] && print yes || print no
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

# An executable, not a function: the listing runs under flock.
stub npm 'cat "'"$TMP"'/npm-ls.json"'

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


# ── Prefetched queries ──────────────────────────────────────

_UUA_CACHE="$TMP/cache"
mkdir -p "$_UUA_CACHE"

_prefetch slow 5 sh -c 'sleep 0.3; echo 1.2.3'
expect "fetch: waits for the prefetched answer" 1.2.3 "$(_fetch slow 5 print live)"
expect "fetch: no prefetch, asked now" live "$(_fetch other 5 print live)"

_prefetch broken 5 false
out="$(_fetch broken 5 print live)"
expect "fetch: a failed prefetch is not asked again" "1 " "$? $out"

started=$SECONDS
_limited 1 sh -c 'echo early; sleep 20' >"$TMP/limited.out"
expect "limited: time limit" 124 $?
expect "limited: stopped promptly" 1 "$(( SECONDS - started < 5 ))"
expect "limited: output passes through" early "$(<"$TMP/limited.out")"

# The prefetched "foo 3.0.0" wins over the registry's 2.0.0; bar, which
# the prefetch lacks, is looked up; baz's lookup failed and stays failed.
_prefetch globals 5 print -l 'foo 3.0.0' 'baz -'
expect "outdated: prefetched releases used" "foo 1.0.0 3.0.0" \
  "$(print -l 'foo 1.0.0' 'bar 0.5.0' 'baz 1.0.0' | _outdated_packages globals | head -n 1)"
expect "outdated: missing ones looked up" "bar 0.5.0 1.0.0" \
  "$(print -l 'foo 1.0.0' 'bar 0.5.0' 'baz 1.0.0' | _outdated_packages globals | tail -n 1)"

_UUA_CACHE=""


# ── Tool owners ─────────────────────────────────────────────

stub native-tool 'echo 1.0.0'

mkdir -p "$TMP/nvm/versions/node/v1.0.0/bin" "$TMP/bun/install/global/node_modules/x" "$TMP/links"
print -r -- '#!/bin/sh' >"$TMP/nvm/versions/node/v1.0.0/bin/npm-tool"
print -r -- '#!/bin/sh' >"$TMP/bun/install/global/node_modules/x/bun-tool"
chmod +x "$TMP/nvm/versions/node/v1.0.0/bin/npm-tool" "$TMP/bun/install/global/node_modules/x/bun-tool"
ln -s "$TMP/bun/install/global/node_modules/x/bun-tool" "$TMP/links/bun-tool"

owner() {
  NVM_DIR="$TMP/nvm" BUN_INSTALL="$TMP/bun" _tool_owner "$1"
  print -r -- "$REPLY"
}

path=("$TMP/nvm/versions/node/v1.0.0/bin" "$TMP/links" $path)

expect "owner: nvm's npm"       npm    "$(owner npm-tool)"
expect "owner: bun global"      bun    "$(owner bun-tool)"
expect "owner: own installer"   native "$(owner native-tool)"
expect "owner: not installed"   absent "$(owner no-such-tool)"

path=(${path:#$TMP/nvm/versions/node/v1.0.0/bin})
path=(${path:#$TMP/links})


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

out="$(_report_tool fake)"
expect "report: row" yes "$(has "$out" "✓ 2.0.0 · up to date")"
expect "report: extensions failure" yes "$(has "$out" "✗ extensions update failed")"


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
_run_task "slow" "$TMP/slow.log" 1 sleep 20
expect "task: time limit" 124 $?
expect "task: stopped promptly" 1 "$(( SECONDS - started < 5 ))"
expect "task: limit logged" "uua: stopped after 1s without finishing" "$(<"$TMP/slow.log.err")"

_run_task "quick" "$TMP/quick.log" 0 sh -c 'echo out; echo err >&2; exit 3'
expect "task: foreground status" 3 $?
expect "task: stdout apart from stderr" "out" "$(<"$TMP/quick.log")"

sleep 30 &
child=$!
expect "child: own child recognized" 0 "$(_is_my_child "$child"; print $?)"
kill "$child"
wait "$child" 2>/dev/null
expect "child: reaped pid refused" 1 "$(_is_my_child "$child"; print $?)"
expect "child: unrelated process refused" 1 "$(_is_my_child 1; print $?)"


# ── --verbose ───────────────────────────────────────────────

_UUA_VERBOSE=1

out="$(_run_task "loud" "$TMP/loud.log" 5 sh -c 'echo out; echo err >&2; printf last')"
expect "verbose: stdout shown" yes "$(has "$out" "   [loud] out")"
expect "verbose: stderr shown" yes "$(has "$out" "   [loud] err")"
expect "verbose: unterminated last line shown" yes "$(has "$out" "   [loud] last")"
expect "verbose: stdout log" $'out\nlast' "$(<"$TMP/loud.log")"
expect "verbose: stderr log" err "$(<"$TMP/loud.log.err")"
expect "verbose: no follower left behind" "" "$_UUA_FOLLOW"

out="$(_run_task "loud fg" "$TMP/loud-fg.log" 0 sh -c 'echo fg-out; exit 4'; print "rc=$?")"
expect "verbose: foreground output shown" yes "$(has "$out" "   [loud-fg] fg-out")"
expect "verbose: foreground status kept" yes "$(has "$out" "rc=4")"

out="$(_run_task "loud slow" "$TMP/loud-slow.log" 1 sh -c 'echo before; sleep 20'; print "rc=$?")"
expect "verbose: time limit still applies" yes "$(has "$out" "rc=124")"
expect "verbose: output before the limit shown" yes "$(has "$out" "   [loud-slow] before")"

_UUA_VERBOSE=0

out="$(_run_task "quiet" "$TMP/quiet.log" 5 sh -c 'echo hidden')"
expect "quiet: output only in the log" "" "$out"


# ── Progress ────────────────────────────────────────────────

pbar() {
  _pbar "$1" 10 ""
  print -r -- "$REPLY"
}

expect "bar: not started"            "----------" "$(pbar 0)"
expect "bar: half done"              "=====-----" "$(pbar 0.5)"
expect "bar: done"                   "==========" "$(pbar 1)"
expect "bar: unfinished never full"  "=========-" "$(pbar 0.999)"
expect "bar: started shows"          "=---------" "$(pbar 0.01)"

# In color: one line, its done part in the given color over a faint
# track.
expect "bar: in color" $'\e[32m━━━\e[90m━\e[0m' \
  "$(C_RESET=$'\e[0m'; _UUA_GC[track]=$'\e[90m'; _pbar 0.75 4 $'\e[32m'; print -r -- "$REPLY")"

_UUA_JOB_DIR="$TMP/watch"
mkdir -p "$_UUA_JOB_DIR"

# How far a job has got, from what its log shows.
watch() {
  print -r -- "$2" >"$_UUA_JOB_DIR/$1.act"
  _UUA_J_TAILAT[$1]=0
  _job_watch "$1"
  printf '%.2f' "$_UUA_J_PROG[$1]"
}

print -l "Unpacking a" "Setting up a" "Unpacking b" "Setting up b" >"$TMP/apt.log"
expect "progress: lines counted" 0.65 \
  "$(watch apt "installing"$'\t'"$TMP/apt.log"$'\t0.35\t0.95\t10\tSetting up\t4')"

print -r -- "######################## 40.0%" >"$TMP/dl.log"
expect "progress: a printed percentage" 0.42 \
  "$(watch dl "downloading"$'\t'"$TMP/dl.log"$'\t0.1\t0.9\t8\t\t0')"

watch up "one"$'\t\t0.5\t0.6\t100\t\t0' >/dev/null
expect "progress: never shrinks" 0.50 "$(watch up "two"$'\t\t0\t0.1\t100\t\t0')"

watch slow "waiting"$'\t\t0.2\t0.5\t0.2\t\t0' >/dev/null
sleep 0.6
_job_watch slow
expect "progress: eased in over time" 1 "$(( _UUA_J_PROG[slow] > 0.45 && _UUA_J_PROG[slow] <= 0.5 ))"

for t in 0.04:0.0s 12.34:12.3s 65.2:1m05s 3725:1h02m; do
  _fmt_secs "${t%%:*}"
  expect "time: ${t%%:*}" "${t#*:}" "$REPLY"
done


# ── Jobs ────────────────────────────────────────────────────

_UUA_JOB_DIR="$TMP/jobs"

reset_plan() {
  _UUA_PLAN=()
  _UUA_J_NAME=() _UUA_J_GROUP=() _UUA_J_DEPS=() _UUA_J_FUNC=() _UUA_J_LIMIT=()
  _UUA_J_OWNER=() _UUA_J_STATE=() _UUA_J_PID=() _UUA_J_START=() _UUA_J_END=()
  _UUA_J_ROW=() _UUA_J_ACT=() _UUA_J_TAIL=() _UUA_J_TAILAT=()
  _UUA_UPTODATE=0 _UUA_UPDATED=0 _UUA_AVAILABLE=0 _UUA_FAILED_STEPS=0
  rm -rf -- "$_UUA_JOB_DIR"
  mkdir -p "$_UUA_JOB_DIR"
}

_job_slow_a() {
  _activity "working"
  sleep 1
  TEST_VAR=from-a
  _job_export TEST_VAR
  _row ok "a done"
  _mark_uptodate
}

_job_slow_b() {
  sleep 1
  _row updated "b done"
  _sub note "a detail"
  _mark_updated
}

_job_after_a() {
  _row ok "saw $TEST_VAR"
  _mark_uptodate
}

reset_plan
_plan_add a one a "" _job_slow_a
_plan_add b one b "" _job_slow_b
_plan_add c two c a _job_after_a
_plan_add d two d "c not-planned" _job_after_a

_plan_run >"$TMP/plan.out"
out="$(<"$TMP/plan.out")"

expect "jobs: independent ones run side by side" 1 "$(( _UUA_T_END - _UUA_T0 < 1.8 ))"
expect "jobs: a dependent waits" 1 "$(( _UUA_J_START[c] >= _UUA_J_END[a] ))"
expect "jobs: variables handed on" "ok|saw from-a" "$_UUA_J_ROW[c]"
expect "jobs: unplanned dependency ignored" "ok|saw from-a" "$_UUA_J_ROW[d]"
expect "jobs: outcomes counted" "3 1 0" "$_UUA_UPTODATE $_UUA_UPDATED $_UUA_FAILED_STEPS"
expect "jobs: printed when done" yes "$(has "$out" "↑ b            b done")"
expect "jobs: sub-lines printed" yes "$(has "$out" "· a detail")"

_job_stuck() {
  _run_task "stuck" "$TMP/stuck.log" 0 sh -c 'echo "last words"; sleep 20'
}

_job_dies() {
  exit 3
}

reset_plan
_plan_add stuck one stuck "" _job_stuck 1
_plan_add dies one dies "" _job_dies

started=$SECONDS
_plan_run >/dev/null

expect "jobs: time limit" "failed|stopped after 1s without finishing" "$_UUA_J_ROW[stuck]"
expect "jobs: stopped promptly" 1 "$(( SECONDS - started < 5 ))"
expect "jobs: the log tail kept" yes "$(has "$(<"$_UUA_JOB_DIR/stuck.sub")" "tail|last words")"
expect "jobs: a job that died" "failed|ended without a result" "$_UUA_J_ROW[dies]"
expect "jobs: both counted as failures" 2 "$_UUA_FAILED_STEPS"
expect "jobs: nothing left running" "" "$(pgrep -f 'last words')"

# Every board line fits the terminal, whatever its width.
reset_plan
_plan_add a one "a job" "" _job_slow_b
_plan_add r two "running" "" _job_slow_b
_plan_add w two "a waiting job with a long name" "r" _job_slow_b
(( _UUA_T0 = EPOCHREALTIME - 10, _UUA_T_END = EPOCHREALTIME ))
_UUA_J_STATE[a]=done _UUA_J_ROW[a]="updated|$(printf 'x%.0s' {1..200})"
(( _UUA_J_START[a] = _UUA_T0, _UUA_J_END[a] = _UUA_T0 + 4 ))
_UUA_J_STATE[r]=run
(( _UUA_J_START[r] = _UUA_T0 + 2 ))
print -r -- "note|a sub-line" >"$_UUA_JOB_DIR/a.sub"
print -r -- "installing"$'\t'"$TMP/progress.log" >"$_UUA_JOB_DIR/r.act"
print -r -- $'Get:1 first\rGet:2 \e[1msecond\e[0m\r' >"$TMP/progress.log"

# The board's lines without their escape sequences (colors, and the
# column numbers each column starts at).
plain() {
  setopt localoptions extendedglob
  print -r -- "${(F)${@//$'\e'\[[0-9;?]#[A-Za-z]/}}"
}

for cols in 120 100 80 60 40; do
  _UUA_COLS=$cols
  _board_lines 0
  widest=0

  for line in "${(@f)$(plain "${reply[@]}")}"; do
    (( ${#line} > widest )) && widest=${#line}
  done

  expect "board: fits $cols columns" 1 "$(( widest < cols ))"
done

_UUA_COLS=100
_board_lines 0
expect "board: a waiting row" yes "$(has "$(plain $reply)" "◌  a waiting j… waiting for running")"
expect "board: the latest log line" yes "$(has "$(plain $reply)" "installing  Get:2 second")"
expect "board: columns placed" yes "$(has "$reply[3]" $'\e[12G')"

# A log line in Chinese is cut by its width on screen, not its length.
print -r -- "正在设置软件包正在设置软件包正在设置软件包正在设置软件包正在设置软件包" >"$TMP/progress.log"
_UUA_J_TAILAT[r]=0
_UUA_COLS=80
_board_lines 0
line="$(plain "$reply[4]")"
expect "board: wide characters fit" 1 "$(( ${(m)#line} < 80 ))"

_UUA_J_STATE[r]=done _UUA_J_ROW[r]="ok|fine" _UUA_J_END[r]=$_UUA_T_END
_UUA_J_STATE[w]=done _UUA_J_ROW[w]="absent|not installed"
_UUA_J_START[w]=$_UUA_T_END _UUA_J_END[w]=$_UUA_T_END
_UUA_COLS=100
_board_lines 1
expect "board: the header" yes "$(has "$reply[1]" " ✓ UUA $UUA_VERSION  ==")"
expect "board: sub-lines in the last frame" yes "$(has "$(plain $reply)" "· a sub-line")"
expect "board: a full bar when done" yes "$(has "$(plain $reply)" "…  ===================  ")"
expect "board: the run's bar" yes "$(has "$(plain $reply[1])" " ✓ UUA $UUA_VERSION  ===")"

# The AI CLI jobs, with the updater's output streamed under --verbose.
print 1.0.0 >"$TMP/fake-version"
touch "$TMP/fake-bump"
rm -f "$_UUA_RUN_DIR"/fake*(N)
reset_plan

out="$(
  _UUA_TOOLS=('fake|Fake|faketool|_fake_latest|self|faketool update|||')
  _UUA_FILTERED=1 _UUA_WANT_AI=1 _UUA_VERBOSE=1
  _UUA_STREAM="$TMP/stream.log"
  : >"$_UUA_STREAM"
  _plan_build
  _plan_run
)"
expect "verbose: job output labelled" yes "$(has "$out" "   [fake] fake updater says hi")"
expect "verbose: job still reported" yes "$(has "$out" "Fake         1.0.0 → 2.0.0 · upgraded")"


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

expect "cli: version" "UUA 0.1.1" "$(zsh "$ROOT/uua" --version)"
expect "cli: --verbose accepted" "UUA 0.1.1" "$(zsh "$ROOT/uua" --verbose --version)"

zsh "$ROOT/uua" --bogus 2>/dev/null
expect "cli: unknown option" 2 $?

stub claude 'echo "1.0.0 (Claude Code)"'

# No nvm here: an AI-only run switches to nvm's default Node, which
# would pull the real tools and npm back onto PATH.
out="$(PATH="$TMP/bin:/usr/bin:/bin" NVM_DIR="$TMP/no-nvm" zsh "$ROOT/uua" --check --ai 2>/dev/null)"
expect "cli: --check exits 100 when updates exist" 100 $?
expect "cli: --check reports the update" yes \
  "$(has "$out" "Claude Code  1.0.0 → 2.0.0 · update available")"
expect "cli: absent tools are listed" yes "$(has "$out" "– Codex        not installed")"
expect "cli: absent tools are not counted" yes "$(has "$out" "Summary  1 item(s)")"

# The same run on a terminal: the live board, its last frame kept.
if command -v script >/dev/null 2>&1; then
  out="$(
    PATH="$TMP/bin:/usr/bin:/bin" NVM_DIR="$TMP/no-nvm" \
      script -qec "stty cols 100 rows 30; zsh '$ROOT/uua' --check --ai" /dev/null 2>/dev/null
  )"
  expect "live: exit status kept" 100 $?
  expect "live: cursor hidden, then shown" yes \
    "$([[ "$out" == *$'\e[?25l'*$'\e[?25h'* ]] && print yes || print no)"
  expect "live: no autowrap while redrawing" yes \
    "$([[ "$out" == *$'\e[?7l'*$'\e[?7h'* ]] && print yes || print no)"
  expect "live: the last frame" yes "$(has "$(plain "$out")" "1.0.0 → 2.0.0 · update available")"
  expect "live: the progress bars" yes "$(has "$out" "=====")"
  expect "live: the summary" yes "$(has "$out" "Summary  1 item(s)")"
fi


# ── Terminal width ──────────────────────────────────────────

# A terminal that draws "━" two columns wide says so when asked where
# the cursor went: zpty plays the terminal, answering the query.
if zmodload zsh/zpty 2>/dev/null; then
  probe() {
    local out

    zpty probe "zsh -c 'source ${(q)ROOT}/uua; stty -echo -icanon; _ambiguous_wide && print WIDE || print NARROW'"
    zpty -r probe out '*'$'\e''\[6n'
    zpty -w -n probe $'\e[1;'"$1"R
    zpty -r probe out '*(WIDE|NARROW)*'
    zpty -d probe

    [[ "$out" == *WIDE* ]] && print wide || print narrow
  }

  expect "probe: a terminal drawing it wide" wide "$(probe 3)"
  expect "probe: a terminal drawing it narrow" narrow "$(probe 2)"

  # A key pressed instead of an answer: no hang, narrow after the wait.
  stray() {
    local out

    zpty probe "zsh -c 'source ${(q)ROOT}/uua; stty -echo -icanon; _ambiguous_wide && print WIDE || print NARROW'"
    zpty -r probe out '*'$'\e''\[6n'
    zpty -w -n probe x
    zpty -r probe out '*(WIDE|NARROW)*'
    zpty -d probe

    [[ "$out" == *WIDE* ]] && print wide || print narrow
  }

  started=$EPOCHREALTIME
  expect "probe: a stray key does not hang it" narrow "$(stray)"
  expect "probe: gives up in time" 1 "$(( EPOCHREALTIME - started < 3 ))"

  # A whole board on such a terminal, in color: its bars are drawn with
  # "-", which is narrow everywhere.
  wide_board() {
    local out all=""

    zpty board "stty cols 100 rows 30; env -u NO_COLOR TERM=xterm-256color PATH=${(q)TMP}/bin:/usr/bin:/bin NVM_DIR=${(q)TMP}/no-nvm zsh ${(q)ROOT}/uua --check --ai"
    zpty -r board out '*'$'\e''\[6n'
    all+="$out"
    zpty -w -n board $'\e[1;3R'

    while zpty -r board out; do
      all+="$out"
      [[ "$out" == *"Summary"* ]] && break
    done

    zpty -d board
    print -r -- "$all"
  }

  out="$(wide_board)"
  expect "wide: bars drawn with -" yes "$(has "$out" "---")"
  expect "wide: no ━ bars" no "$(has "$out" "━━")"
fi


# ── A whole run ─────────────────────────────────────────────

# Against the fake system of tests/fakesys.zsh: every tool behind, Node
# 22 installed with 24 out.
fake_build() {
  rm -rf -- "$1"
  zsh "$ROOT/tests/fakesys.zsh" "$1"
  fake_env=($(zsh "$ROOT/tests/fakesys.zsh" "$1" env) LANG=C.UTF-8 NO_COLOR=1)
}

fake_run() {
  fake_build "$1"
  shift
  env -i $fake_env "$@"
}

F="$TMP/fake"
out="$(fake_run "$F" FAKE_SPEED=0.1 zsh "$ROOT/uua" --prune)"
expect "run: succeeds" 0 $?

mods="$F/home/.nvm/versions/node/v24.1.0/lib/node_modules"
expect "run: every tool upgraded" "0 1.2.0 2.1.0 1.0.0 10.2.0 5.1.0" \
  "$(<"$F/db/apt-pending") $(<"$F/db/bun") $(<"$F/db/claude") $(<"$mods/@earendil-works/pi-coding-agent/version") $(<"$mods/npm/version") $(<"$mods/typescript/version")"
expect "run: bun globals and bun's CLI" yes \
  "$(grep -q 4.1.0 "$F/home/.bun/install/global/node_modules/typescript-language-server/package.json" &&
     grep -q 1.1.0 "$F/home/.bun/install/global/node_modules/@opencode/cli/package.json" && print yes)"
expect "run: the old Node pruned" v24.1.0 "$(ls "$F/home/.nvm/versions/node")"
expect "run: the default follows lts/*" 'lts/*' "$(<"$F/home/.nvm/alias/default")"

# Jobs print as they finish, so the order shows who waited for whom.
order=(${(f)"$(print -r -- "$out" | sed -n 's/^[✓↑✗] \([A-Za-z -]*[a-z]\)  .*/\1/p')"})
before() {
  (( ${order[(i)$1]} < ${order[(i)$2]} )) && print yes || print "no: ${(j:, :)order}"
}

expect "run: npm after node"      yes "$(before node npm)"
expect "run: npm -g after npm"    yes "$(before npm "npm -g")"
expect "run: Pi after npm"        yes "$(before npm Pi)"
expect "run: OpenCode after bun"  yes "$(before bun OpenCode)"
expect "run: bun -g after node"   yes "$(before node "bun -g")"
expect "run: prune last"          prune "$order[-1]"
expect "run: jobs overlapped" yes \
  "$([[ "$out" =~ '([0-9.]+)× in parallel' ]] && (( match[1] > 1.5 )) && print yes)"

# Stopped halfway: every job is stopped at once but APT, which finishes
# the command it is running and starts nothing more.
fake_build "$F"
env -i $fake_env FAKE_SPEED=0.5 zsh "$ROOT/uua" >"$TMP/stopped.out" &
main=$!

# Once APT's metadata refresh is under way.
for i in {1..100}; do
  logs=("$F"/state/uua/run-*/apt-update.log(NL+0))
  (( $#logs )) && break
  sleep 0.05
done

kill -TERM "$main"
wait "$main"
expect "stop: exit status" 143 $?
out="$(<"$TMP/stopped.out")"
expect "stop: jobs interrupted" yes "$(has "$out" "✗ Claude Code  interrupted")"
expect "stop: the update not finished" 2.0.0 "$(<"$F/db/claude")"
expect "stop: APT started nothing more" yes "$(has "$out" "· not started: installing 12 update(s)")"
expect "stop: nothing left running" "" "$(pgrep -f "$F/")"

# --verbose on a terminal: the commands' output scrolls above the board.
if command -v script >/dev/null 2>&1; then
  out="$(fake_run "$F" FAKE_SPEED=0.1 TERM=xterm \
    script -qec "stty cols 90 rows 30; zsh '$ROOT/uua' --verbose" /dev/null 2>/dev/null)"
  expect "live verbose: succeeds" 0 $?
  expect "live verbose: output streamed" yes "$(has "$out" "[apt-update] Get:1 http")"
  expect "live verbose: the last frame" yes "$(has "$out" "12 package(s) upgraded")"
fi


print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
