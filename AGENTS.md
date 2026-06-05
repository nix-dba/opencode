# Feature Overlay System

The sandbox uses a feature overlay system to conditionally include optional tools.
Each `--with-<name>` flag maps to a sibling directory `<name>/` next to `default/`.

## Directory structure

```
default/                   # base config — always included, no optional features
├── opencode.jsonc         # base config (no feature-specific additions)
├── prompts/               # general.md, karpathy.md
├── skill/                 # tuicr/ only
├── command/
├── layout.kdl
└── tuicr/

gitnexus/                  # overlay for --with-gitnexus
├── opencode.jsonc         # optional — only feature-specific additions
├── prompts/               # gitnexus.md
└── skill/                 # gitnexus-*/
```

## How it works

Each feature directory can contain any subset of:
- `opencode.jsonc` — deep-merged into the base jsonc (objects merge recursively, arrays concatenate, scalars overlay)
- `prompts/` — `.md` files bound into `$HOME/.config/opencode/prompts/`
- `skill/` — subdirectories bound into `$HOME/.config/opencode/skill/`

The merge script at `merge-jsonc.js` handles JSONC comment stripping and deep-merge.

## Adding a new feature

1. Create `<feature>/` directory with optional `opencode.jsonc`, `prompts/`, `skill/`
2. In `flake.nix`: add `export <FEATURE>_DIR="${./<feature>}"` to the sandbox text block
3. In `sandbox.sh`:
   - Add `--with-<feature>)` case in the flag parsing block
   - Add `<feature>)` case in the feature setup block for any setup logic (dir creation, analysis prompts, etc.)
