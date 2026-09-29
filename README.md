# UUA — Universal Update All

Updates APT packages, Node.js (through nvm), npm, Bun, the global npm/bun
packages and a set of AI coding CLIs in one run. A single zsh script
(`uua`).

## Pipeline

```
apt → node → npm → bun → npm -g → bun -g
                                     ↓
        ┌────────────┬─────────┬──────┴───────────────┐
        ↓            ↓         ↓                      ↓
     claude        codex   opencode                  pi
```

The core steps run in order, each building on the one before. The AI CLIs
are independent and update in parallel; writes to the global npm tree are
serialized between them.

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
uua --verbose       show every command's output as it runs
uua --keep-logs     keep this run's logs (kept anyway on failure)
uua --no-color      disable colors (so does NO_COLOR)
```

Group flags combine (`uua --apt --ai`). sudo is asked for once, up front,
and only when the APT group runs. Every item ends up up to date, upgraded
or failed, and the summary counts them. `uua --help` has the details.

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
```

The version lives in `UUA_VERSION` at the top of `uua`.

## License

MIT; see [LICENSE](LICENSE).
