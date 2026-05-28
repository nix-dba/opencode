# Skills

Skills are available at `default/skill/` and mounted into the opencode agent's skill directory.

## GitNexus Skills

Seven skills for code intelligence via the local knowledge graph:

| Skill | Description |
|-------|-------------|
| `gitnexus-cli` | CLI commands: `analyze`, `status`, `clean`, `wiki`, `list` |
| `gitnexus-debugging` | Trace bugs and unexpected behavior via execution flow queries |
| `gitnexus-exploring` | Explore codebase architecture via resources and queries |
| `gitnexus-guide` | Master reference for all tools, resources, and graph schema |
| `gitnexus-impact-analysis` | Assess blast radius of code changes before editing |
| `gitnexus-pr-review` | Structured PR review workflow with diff analysis and risk assessment |
| `gitnexus-refactoring` | Safe code restructuring (rename, extract, split, move) |

GitNexus is configured as an MCP tool in `default/opencode.jsonc:5-13`:
```json
"mcp": {
  "gitnexus": {
    "type": "local",
    "command": ["gitnexus", "mcp"]
  }
}
```

## tuicr Skill

File: `default/skill/tuicr/SKILL.md`

Launches the `tuicr` code review TUI in a Zellij floating pane via `tuicr-wrapper.sh`. Validates prerequisites (tuicr installed, git repo, inside Zellij), launches tuicr with `zellij run --floating --blocking`, and captures any instructions exported via stdout markers.
