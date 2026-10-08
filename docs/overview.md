# Overview

This repository provides a Nix flake-based sandboxed opencode2 environment. It packages opencode2 with:

- **Bubblewrap sandbox** (`sandbox.sh`) -- isolates opencode2 from the host filesystem to reduce secret exposure risk
- **Herdr** terminal workspace (agent-native session) that auto-launches opencode2
- **OmniRoute** -- official opencode v2 plugin (`@omniroute/opencode-plugin-v2`), built from source and opt-in via a host `~/.config/opencode/omniroute.json`
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command
- **Custom opencode2 commands**: `/commit`, `/docs`, `/tuicr`
- **Custom agent instructions**: general guidelines and Karpathy-style coding rules, concatenated into a global `AGENTS.md`

All tools and dependencies are version-pinned via the Nix flake lockfile for reproducible environments.
