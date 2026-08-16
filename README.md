# OpenCode

Sandboxed opencode environment with code intelligence, running via Nix with Bubblewrap isolation.

## Documentation

- [Overview](docs/overview.md) -- High-level architecture and components
- [Sandbox](docs/sandbox.md) -- Bubblewrap sandbox CLI flags and bind mounts
- [Commands](docs/commands.md) -- Custom `/commit`, `/docs`, `/tuicr` commands
- [Skills](docs/skills.md) -- GitNexus and tuicr skills available to the agent
- [Prompts](docs/prompts.md) -- Agent instruction files (general, gitnexus, karpathy)
- [Configuration](docs/configuration.md) -- opencode.jsonc, Herdr config, tuicr config, Nix flake

## Features

- **Bubblewrap sandbox** (`sandbox.sh`) -- Isolates opencode from the host filesystem to reduce secret exposure risk
- **Herdr terminal workspace** -- Agent-native session that auto-launches opencode
- **GitNexus** -- Local knowledge graph for code intelligence (call chains, execution flows, impact analysis)
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command in a Herdr tab
- **Custom opencode commands** -- `/commit` (conventional commits), `/docs` (documentation generation), `/tuicr` (code review)
- **Custom agent prompts** -- General guidelines, GitNexus rules, and Karpathy-style coding rules loaded into every session
- **GitNexus skill set** -- 7 skills for exploring, debugging, impact analysis, PR review, refactoring, CLI, and guidance
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

The flake provides two sandbox apps:

- **`nix run .`** -- Light (default) with bare minimum dependencies, no GitNexus
- **`nix run .#full`** -- Full with all dependencies, GitNexus enabled by default

See [docs/sandbox.md](docs/sandbox.md) for available CLI flags (`--no-net`, `--ssh-keys`, etc.).
