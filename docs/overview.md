# Overview

This repository provides a Nix flake-based sandboxed opencode environment. It packages opencode with:

- **Bubblewrap sandbox** (`sandbox.sh`) -- isolates opencode from the host filesystem to reduce secret exposure risk
- **Zellij** terminal workspace with a layout that auto-launches opencode
- **GitNexus** -- local knowledge graph for code intelligence (call chains, execution flows, impact analysis)
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command
- **Custom opencode commands**: `/commit`, `/docs`, `/tuicr`
- **Custom agent prompt instructions**: general guidelines, GitNexus usage rules, Karpathy-style coding rules
- **GitNexus skill set**: 7 skills for exploring, debugging, impact analysis, PR review, refactoring, CLI, and general guidance

All tools and dependencies are version-pinned via the Nix flake lockfile for reproducible environments.
