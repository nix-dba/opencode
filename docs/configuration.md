# Configuration

## opencode.jsonc

File: `default/opencode.jsonc`

General opencode configuration:
- **autoupdate**: `true` -- auto-update opencode
- **plugin**: `opencode-omniroute-auth@v1.1.4` -- authentication plugin for omniroute
- **mcp.gitnexus**: Local MCP server running `gitnexus mcp`
- **permission.external_directory**: Allows access to `**/.opencode/**` and `**/.gitnexus/**`
- **instructions**: Loads three prompt files: `general.md`, `gitnexus.md`, `karpathy.md`

## Zellij Layout

File: `default/layout.kdl`

A minimal Zellij layout with two panes:
1. Main pane running `opencode` via bash
2. Borderless status bar pane (1 line)

## tuicr Config

File: `default/tuicr/config.toml`

Code review TUI settings:
- `diff_view = "side-by-side"`
- `appearance = "dark"`
- `mouse = true`
- `leader = ","`
- `review_watch_interval_ms = 1000`

## Nix Flake

File: `flake.nix`

Flake outputs:
- `devShells.default` -- shell with all dependencies (bash, bubblewrap, bun, opencode, gitnexus, tuicr, zellij, git, wl-clipboard, uv)
- `apps.default` -- runs `sandbox` script
- `formatter.default` -- `nixfmt` wrapper (formats all `*.nix` files or specified paths)

Flake inputs:
- `nixpkgs` (nixpkgs-unstable)
- `llm-agents.nix` (provides opencode, gitnexus, tuicr packages)

Extra substituter: `https://cache.numtide.com`
