#!/usr/bin/env zsh

# Builds a fake system for uua under directory $1: stub apt-get, sudo,
# curl and dpkg-query, an nvm with Node 22 installed and 24 out, npm, Bun
# and the four AI CLIs, each with an update waiting and a pause where the
# real one would download. `make demo` runs uua against it, and the tests
# drive it; nothing outside $1 is touched. FAKE_SPEED scales the pauses
# (1 is demo speed). Run uua with the environment `fakesys.zsh $1 env`
# prints.

F="${1:?usage: fakesys.zsh <dir> [env]}"

if [[ "${2:-}" == env ]]; then
  F="${F:A}"
  print -r -- "HOME=$F/home"
  print -r -- "NVM_DIR=$F/home/.nvm"
  print -r -- "XDG_STATE_HOME=$F/state"
  print -r -- "PATH=$F/bin:$F/home/.local/bin:$F/home/.bun/bin:/usr/bin:/bin"
  exit 0
fi

REAL_NODE="$(command -v node)" || { print -u2 "fakesys: node is needed"; exit 1 }

mkdir -p "$F"
F="${F:A}"

NODES="$F/home/.nvm/versions/node"
MODS="$NODES/v22.0.0/lib/node_modules"
BUNG="$F/home/.bun/install/global"

mkdir -p "$F"/{bin,db,latest,state} "$F/home/.local/bin" "$F/home/.nvm/alias" \
  "$NODES/v22.0.0/bin" "$F/home/.bun/bin" "$BUNG/node_modules"


put() {
  mkdir -p "${1:h}"
  print -r -- "$2" >"$1"
}


# Writes executable $1 from stdin, with @F@ and @NODE@ filled in.
script_to() {
  mkdir -p "${1:h}"
  sed -e "s#@F@#$F#g" -e "s#@NODE@#$REAL_NODE#g" >"$1"
  chmod +x "$1"
}


# The registry's releases, and what is installed.
put "$F/latest/npm" 10.2.0
put "$F/latest/typescript" 5.1.0
put "$F/latest/typescript-language-server" 4.1.0
put "$F/latest/bun" 1.2.0
put "$F/latest/@anthropic-ai/claude-code" 2.1.0
put "$F/latest/codex" 0.50.0
put "$F/latest/@opencode/cli" 1.1.0
put "$F/latest/@earendil-works/pi-coding-agent" 1.0.0

put "$F/db/apt-pending" 12
put "$F/db/apt-unused" 2
put "$F/db/bun" 1.1.0
put "$F/db/claude" 2.0.0
put "$F/db/codex" 0.50.0

put "$MODS/npm/version" 10.0.0
put "$MODS/typescript/version" 5.0.0
put "$MODS/@earendil-works/pi-coding-agent/version" 0.9.0
put "$F/home/.nvm/alias/default" v22.0.0

put "$BUNG/package.json" '{"dependencies": {"typescript-language-server": "^4.0.0", "@opencode/cli": "^1.0.0"}}'
put "$BUNG/node_modules/typescript-language-server/package.json" '{"version": "4.0.0"}'
put "$BUNG/node_modules/@opencode/cli/package.json" '{"version": "1.0.0"}'


script_to "$F/lib.sh" <<'EOF'
nap() {
  sleep "$(awk -v s="$1" -v k="${FAKE_SPEED:-1}" 'BEGIN { print s * k }')"
}
EOF


script_to "$F/bin/sudo" <<'EOF'
#!/bin/sh
case "$1" in
  -v) exit 0 ;;
  -n) shift; [ "$1" = true ] && exit 0 ;;
esac
exec "$@"
EOF


script_to "$F/bin/dpkg-query" <<'EOF'
#!/bin/sh
exit 1
EOF


script_to "$F/bin/apt-get" <<'EOF'
#!/bin/sh
. @F@/lib.sh
pending=$(cat @F@/db/apt-pending)
unused=$(cat @F@/db/apt-unused)

case " $* " in
  *" -s upgrade "*)
    i=0; while [ $i -lt $pending ]; do echo "Inst libfake$i (1.$i)"; i=$((i + 1)); done ;;
  *" -s autoremove "*)
    i=0; while [ $i -lt $unused ]; do echo "Remv oldfake$i"; i=$((i + 1)); done ;;
  *" update "*)
    for i in 1 2 3 4 5 6; do
      echo "Get:$i http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [$((i * 317)) kB]"
      nap 0.35
    done
    echo "Reading package lists..." ;;
  *" upgrade "*)
    i=0
    while [ $i -lt $pending ]; do
      echo "Unpacking libfake$i (1.$i) over (1.0) ..."; nap 0.12
      echo "Setting up libfake$i (1.$i) ..."; nap 0.12
      i=$((i + 1))
    done
    echo 0 >@F@/db/apt-pending ;;
  *" autoremove "*)
    i=0; while [ $i -lt $unused ]; do echo "Removing oldfake$i ..."; nap 0.3; i=$((i + 1)); done
    echo 0 >@F@/db/apt-unused ;;
esac
EOF


script_to "$F/bin/curl" <<'EOF'
#!/bin/sh
. @F@/lib.sh
for a; do case "$a" in http*) url=$a ;; esac; done

case "$url" in
  */index.tab)
    nap 0.4
    printf 'version\tdate\tfiles\tnpm\tv8\tuv\tzlib\topenssl\tmodules\tlts\tsecurity\n'
    printf 'v25.0.0\t2026-09-01\t-\t11.0.0\t-\t-\t-\t-\t-\t-\tfalse\n'
    printf 'v24.1.0\t2026-08-01\t-\t10.1.0\t-\t-\t-\t-\t-\tKrypton\tfalse\n'
    printf 'v22.0.0\t2026-01-01\t-\t10.0.0\t-\t-\t-\t-\t-\tJod\tfalse\n' ;;
  */oven-sh/bun/releases/latest)
    nap 0.5
    printf 'https://github.com/oven-sh/bun/releases/tag/bun-v%s' "$(cat @F@/latest/bun)" ;;
  */codex/channels/latest)
    nap 0.6
    printf '{"tag_name": "rust-v%s"}\n' "$(cat @F@/latest/codex)" ;;
  *)
    exit 22 ;;
esac
EOF


# Enough of nvm for uua, over the releases under $NVM_DIR/versions/node.
script_to "$F/home/.nvm/nvm.sh" <<'EOF'
_fake_resolve() {
  case "$1" in
    'lts/*') ls "$NVM_DIR/versions/node" | sort -V | tail -n 1 ;;
    default) _fake_resolve "$(cat "$NVM_DIR/alias/default" 2>/dev/null)" ;;
    '') echo N/A ;;
    *)
      _fake_d=$(ls "$NVM_DIR/versions/node" | grep "^v${1#v}" | sort -V | tail -n 1)
      echo "${_fake_d:-N/A}" ;;
  esac
}

nvm() {
  _fake_cmd="$1"
  shift

  case "$_fake_cmd" in
    current)
      _fake_v=$(printf '%s' "$PATH" | tr ':' '\n' |
        sed -n "s#^$NVM_DIR/versions/node/\(v[^/]*\)/bin\$#\1#p" | head -n 1)
      echo "${_fake_v:-none}" ;;
    version)
      _fake_resolve "$1" ;;
    version-remote)
      echo v24.1.0 ;;
    install)
      . @F@/lib.sh
      echo "Downloading and installing node v24.1.0..." >&2
      for p in 12 37 64 88 100; do echo "######################## $p.0%" >&2; nap 0.3; done
      cp -a "$NVM_DIR/versions/node/v22.0.0" "$NVM_DIR/versions/node/v24.1.0"
      echo "Now using node v24.1.0" ;;
    use)
      _fake_v=$(_fake_resolve "$1")
      [ -d "$NVM_DIR/versions/node/$_fake_v" ] ||
        { echo "N/A: version $1 is not installed" >&2; return 3; }
      PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^$NVM_DIR/versions/node/" | tr '\n' ':')
      PATH="$NVM_DIR/versions/node/$_fake_v/bin:${PATH%:}"
      NVM_BIN="$NVM_DIR/versions/node/$_fake_v/bin"
      export PATH NVM_BIN
      echo "Now using node $_fake_v" ;;
    alias)
      echo "$2" >"$NVM_DIR/alias/default" ;;
    uninstall)
      rm -rf "$NVM_DIR/versions/node/v${1#v}"
      echo "Uninstalled node v${1#v}" ;;
  esac
}
EOF


script_to "$NODES/v22.0.0/bin/node" <<'EOF'
#!/bin/sh
case "$1" in
  --version) v=$(cd "$(dirname "$0")/.." && pwd); echo "${v##*/}" ;;
  *) exec @NODE@ "$@" ;;
esac
EOF


# Knows its Node release from where it lives.
script_to "$NODES/v22.0.0/bin/npm" <<'EOF'
#!/bin/sh
. @F@/lib.sh
bin=$(cd "$(dirname "$0")" && pwd)
mods="${bin%/bin}/lib/node_modules"

case "$1" in
  --version) cat "$mods/npm/version" ;;
  root) echo "$mods" ;;
  view) nap 0.3; cat "@F@/latest/$2" 2>/dev/null ;;
  ls)
    printf '{"dependencies":{'
    sep=""
    for f in "$mods"/*/version "$mods"/@*/*/version; do
      [ -f "$f" ] || continue
      name=${f#$mods/}
      name=${name%/version}
      printf '%s"%s":{"version":"%s","resolved":"https://registry.npmjs.org/%s"}' \
        "$sep" "$name" "$(cat "$f")" "$name"
      sep=","
    done
    printf '}}\n' ;;
  install)
    shift
    for spec; do
      case "$spec" in -*) continue ;; esac
      name=${spec%@latest}
      echo "npm http fetch GET 200 https://registry.npmjs.org/$name" >&2
      nap 0.6
      mkdir -p "$mods/$name"
      cat "@F@/latest/$name" >"$mods/$name/version"
    done
    echo "changed $# packages in 1s" ;;
esac
EOF


script_to "$MODS/@earendil-works/pi-coding-agent/cli.sh" <<'EOF'
#!/bin/sh
. @F@/lib.sh
dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

case "$1 $2" in
  "--version ") cat "$dir/version" ;;
  "update --self")
    echo "Updating pi..."; nap 0.8
    cat @F@/latest/@earendil-works/pi-coding-agent >"$dir/version"
    echo "Updated" ;;
  "update --extensions")
    echo "Updating pi-web-search"; nap 0.5; echo "Updated" ;;
esac
EOF

ln -s ../lib/node_modules/@earendil-works/pi-coding-agent/cli.sh "$NODES/v22.0.0/bin/pi"


script_to "$F/home/.local/bin/claude" <<'EOF'
#!/bin/sh
. @F@/lib.sh
case "$1" in
  --version) echo "$(cat @F@/db/claude) (Claude Code)" ;;
  update)
    echo "Current version: $(cat @F@/db/claude)"
    echo "Checking for updates..."; nap 0.6
    for p in 25 50 75 100; do echo "Downloading native build... $p%"; nap 0.4; done
    cat @F@/latest/@anthropic-ai/claude-code >@F@/db/claude
    echo "Successfully updated" ;;
esac
EOF


script_to "$F/home/.local/bin/codex" <<'EOF'
#!/bin/sh
. @F@/lib.sh
case "$1" in
  --version) echo "codex-cli $(cat @F@/db/codex)" ;;
  update) nap 1; cat @F@/latest/codex >@F@/db/codex ;;
esac
EOF


script_to "$F/home/.bun/bin/bun" <<'EOF'
#!/bin/sh
. @F@/lib.sh
g=@F@/home/.bun/install/global

case "$1" in
  --version) cat @F@/db/bun ;;
  upgrade)
    echo "Bun v$(cat @F@/latest/bun) is out! You're on v$(cat @F@/db/bun)"
    for p in 20 40 60 80 100; do echo "[$p%] Downloading bun-linux-x64.zip"; nap 0.3; done
    cat @F@/latest/bun >@F@/db/bun
    echo "Upgraded." ;;
  update)
    shift
    for a; do
      case "$a" in -*) continue ;; esac
      echo "installed $a@$(cat "@F@/latest/$a")"; nap 0.4
      printf '{"version": "%s"}\n' "$(cat "@F@/latest/$a")" >"$g/node_modules/$a/package.json"
    done ;;
esac
EOF


script_to "$BUNG/node_modules/@opencode/cli/bin/opencode" <<'EOF'
#!/bin/sh
. @F@/lib.sh
dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

case "$1" in
  --version) sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dir/package.json" ;;
  upgrade)
    echo "Upgrading opencode..."; nap 1
    printf '{"version": "%s"}\n' "$(cat @F@/latest/@opencode/cli)" >"$dir/package.json"
    echo "Upgrade complete" ;;
esac
EOF

ln -s ../install/global/node_modules/@opencode/cli/bin/opencode "$F/home/.bun/bin/opencode"
