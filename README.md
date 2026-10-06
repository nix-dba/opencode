# OpenCode

Sandboxed opencode2 environment with code intelligence, running via Nix with Bubblewrap isolation.

## Documentation

- [Overview](docs/overview.md) -- High-level architecture and components
- [Sandbox](docs/sandbox.md) -- Bubblewrap sandbox CLI flags and bind mounts
- [Commands](docs/commands.md) -- Custom `/commit`, `/docs`, `/tuicr` commands
- [Skills](docs/skills.md) -- Herdr and tuicr skills available to the agent
- [Prompts](docs/prompts.md) -- Agent instruction files (general, karpathy)
- [Configuration](docs/configuration.md) -- opencode.jsonc, Herdr config, tuicr config, Nix flake

## Features

- **Bubblewrap sandbox** (`sandbox.sh`) -- Isolates opencode2 from the host filesystem to reduce secret exposure risk (opt out with `--no-sandbox` to run directly on the host)
- **Herdr terminal workspace** -- Agent-native session that auto-launches opencode2
- **OmniRoute plugin** -- Official opencode v2 plugin (`@omniroute/opencode-plugin-v2`), built from a pinned source checkout and configured from the host
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command in a Herdr tab
- **Custom opencode2 commands** -- `/commit` (conventional commits), `/docs` (documentation generation), `/tuicr` (code review)
- **Custom agent instructions** -- General guidelines and Karpathy-style coding rules concatenated into a global `AGENTS.md`
- **Version-pinned** -- All tools and dependencies pinned via the Nix flake lockfile

## Usage

In your repository root run:

```sh
nix run github:nix-dba/opencode --refresh --accept-flake-config
```

or via backup repository:

```sh
nix run git+https://codeberg.org/nix-dba/opencode --refresh --accept-flake-config
```

Or from the cloned repo directly:

```sh
nix run . --refresh
```

## Quitting

Press **`ctrl+b q`** to quit. This detaches the Herdr client; because the Herdr
server runs inside the bubblewrap sandbox, quitting also tears down the sandbox
and all its processes. Re-run `nix run .` for a fresh session.

## Apps

The flake provides one sandbox app:

- **`nix run .`** -- Sandbox with bare minimum dependencies

See [docs/sandbox.md](docs/sandbox.md) for available CLI flags (`--no-net`, `--ssh-keys`, `--no-sandbox`, etc.).
