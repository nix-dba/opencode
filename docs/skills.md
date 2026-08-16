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

## herdr Skill

File: `default/skill/herdr/SKILL.md`

The official Herdr agent skill. Teaches opencode to control the session it runs in: inspect and split panes, run commands, read output, wait for state changes, and coordinate sibling agents via the `herdr` CLI. Guarded by `HERDR_ENV=1`.

## tuicr Skill

File: `default/skill/tuicr/SKILL.md`

Launches the `tuicr` code review TUI in a new Herdr tab via `tuicr-wrapper.sh`. Validates prerequisites (tuicr installed, git repo, inside Herdr), creates a tab and runs tuicr with `herdr tab create` + `herdr pane run`, and captures any instructions exported via stdout markers.
