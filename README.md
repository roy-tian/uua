# UUA — Universal Update All

Updates APT packages, Node.js (through nvm), npm, Bun, the global npm/bun
packages and a set of AI coding CLIs in one run. A single zsh script
(`uua`).

## How it runs

Every step is a job, and a job starts the moment the jobs it builds on
have finished, so everything that can run at the same time does:

```
apt ─────────────────────────────→ AI CLIs installed by apt
node ──→ npm ──→ npm -g
              └──────────────────→ AI CLIs installed by npm
bun ───→ bun -g   (after node too)
     └───────────────────────────→ AI CLIs installed by bun
AI CLIs with installers of their own, from the start
```

APT, the Node.js chain, the Bun chain and self-updating CLIs such as a
native Claude Code or Codex all run side by side. A CLI that npm or Bun
installed waits for that package manager's own update, then shares its
global tree with the sweep under a lock. With `--prune`, old Node.js
releases go last, once nothing can be running one; `--check` changes
nothing, so every job starts at once. The registry and release queries
all go out first, while the sudo password is typed.

On a terminal a live board shows every job: its state, what it is doing
and the latest line of its log, a progress bar and its time, under a bar
for the whole run. A bar only ever grows: each job counts its progress
from what its commands print (packages set up, download percentages) or
eases it in over time, and fills when the job is done. The bars are a
line in each group's color (apt, node, bun, AI CLIs, and the run) over a
faint one; without colors, as here midway through a run, "=" over "-":

```
 ⠴ UUA  =====================================================----------------------  6/11  3.5s

 SYSTEM ⠦  apt          installing 12 update(s)  Unpacking libfake…  ==========---------   3.0s
 NODE   ↑  node         22.0.0 → 24.1.0 · upgraded                   ===================   1.6s
        ↑  npm          10.0.0 → 10.2.0 · upgraded                   ===================   0.7s
        ⠏  npm -g       updating typescript                          ========-----------   0.6s
        ◌  prune        waiting for 4 jobs                           -------------------
 BUN    ↑  bun          1.1.0 → 1.2.0 · upgraded                     ===================   1.6s
        ⠹  bun -g       updating typescript-language-server  insta…  =========----------   1.3s
 AI     ↑  Claude Code  2.0.0 → 2.1.0 · upgraded                     ===================   2.3s
        ✓  Codex        0.50.0 · up to date                          ===================   0.3s
        ↑  OpenCode     1.0.0 → 1.1.0 · upgraded                     ===================   1.1s
        ⠦  Pi           updating to 1.0.0  Updating pi...            ======-------------   0.6s
```

The last frame stays, with each job's details under its row, followed by
how much the jobs overlapped. The board adapts to the terminal: it asks
whether line characters are drawn two columns wide (a CJK setting) and
falls back to "-" if so, and it never lets a row wrap.

Without a terminal (a pipe, a log, cron) each job prints once, when it
finishes. `make demo` shows the board on a fake system, updating nothing.

## Requirements

- Linux with **zsh** 5.x. APT updates need a Debian or Ubuntu system;
  elsewhere that step is skipped.
- `flock` (util-linux) and `timeout` (coreutils), present on every
  Debian/Ubuntu install.
- Each step covers a tool only when it is installed: nvm for Node.js, npm,
  bun, and any of Claude Code, Codex, OpenCode and Pi. Missing tools are
  listed and skipped.

macOS is not supported.

## Install

```sh
make install     # copies ./uua to ~/.local/bin/uua
make uninstall
```

Make sure `~/.local/bin` is on your `PATH`. `PREFIX=/usr/local make install`
installs elsewhere.

## Usage

```
uua                 run the whole pipeline
uua --check         report available updates; installs and removes nothing
uua --prune         also remove superseded releases (see below)
uua --apt           only APT packages
uua --node          only node/npm/bun and their global packages
uua --ai            only the AI CLI tools
uua --verbose       show every command's output as it runs, above the board
uua --keep-logs     keep this run's logs (kept anyway on failure)
uua --no-color      disable colors (so does NO_COLOR)
```

Group flags combine (`uua --apt --ai`). sudo is asked for once, up front,
and only when the APT group runs. Every item ends up up to date, upgraded
or failed, and the summary counts them. `uua --help` has the details.

Ctrl-C stops every job at once, except APT: it finishes the command it is
running (dpkg must not be cut off halfway) and starts nothing more.

### What gets removed

Nothing, unless `--prune` is given. With it, uua removes Node.js releases
older than the LTS (except the one the nvm `default` alias points at),
Codex releases other than the current one, and APT packages nothing needs
(`apt-get autoremove`). A release a running process uses is kept. Without
`--prune`, uua reports what it would remove.

The nvm `default` alias moves to `lts/*` only when it is unset, dangling,
or names the exact release being replaced. A pin (`22`, `lts/iron`,
`system`, ...) stays, and npm, the global packages and the AI CLIs are then
updated in the pinned Node, the one new shells get.

### Exit status

| Code | Meaning |
|------|---------|
| 0    | everything is up to date or was updated |
| 1    | something failed, or another uua run is in progress |
| 2    | invalid option |
| 100  | `--check` found updates |

### Logs

Each run logs to `~/.local/state/uua/run-<time>-<pid>/` (under
`$XDG_STATE_HOME` if set). The logs are removed after a clean run unless
`--keep-logs` is given, and only the newest 10 runs are kept.

## Development

```sh
make link        # symlink ./uua into ~/.local/bin, so edits apply at once
make check       # zsh -n syntax check + --version
make test        # tests against stub commands (no network, no sudo)
make demo        # the live board on a fake system; SPEED=0.5 halves pauses
```

The tests and the demo need `node` on `PATH`; the live-board tests run
when `script` (util-linux) is available.

The version lives in `UUA_VERSION` at the top of `uua`.

## License

MIT; see [LICENSE](LICENSE).
