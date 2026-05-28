# OpenCode

Sandboxed opencode environment with code intelligence, running via Nix with Bubblewrap isolation.

## Documentation

- [Overview](docs/overview.md) -- High-level architecture and components
- [Sandbox](docs/sandbox.md) -- Bubblewrap sandbox CLI flags and bind mounts
- [Commands](docs/commands.md) -- Custom `/commit`, `/docs`, `/tuicr` commands
- [Skills](docs/skills.md) -- GitNexus and tuicr skills available to the agent
- [Prompts](docs/prompts.md) -- Agent instruction files (general, gitnexus, karpathy)
- [Configuration](docs/configuration.md) -- opencode.jsonc, Zellij layout, tuicr config, Nix flake

## Features

- **Bubblewrap sandbox** (`sandbox.sh`) -- Isolates opencode from the host filesystem to reduce secret exposure risk
- **Zellij terminal workspace** -- Layout auto-launches opencode with a status bar
- **GitNexus** -- Local knowledge graph for code intelligence (call chains, execution flows, impact analysis)
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command in a Zellij floating pane
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

See [docs/sandbox.md](docs/sandbox.md) for available CLI flags (`--skip-gitnexus`, `--no-net`, `--ssh-keys`, etc.).
