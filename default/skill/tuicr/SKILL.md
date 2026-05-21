---
name: tuicr
description: Review local git changes with tuicr TUI via Zellij floating pane
---

# tuicr - TUI Change Reviewer

Launch the `tuicr` TUI tool in a Zellij floating pane to interactively review local git changes.

## Usage

```
/tuicr [directory]
```

Or simply mention wanting to review changes with tuicr.

## How It Works

Since coding agents cannot run interactive TUI applications directly, this skill uses a Zellij workaround:

1. Detects if the current agent session is running inside Zellij (via `$ZELLIJ_SESSION_NAME`)
2. If yes: Opens tuicr in a floating popup using `zellij run --floating --blocking`
3. If no: Provides instructions to restart the agent inside the sandbox
4. After tuicr exits: Captures any instructions exported via `--stdout`

> **Tip:** In the sandbox environment, you can also press **`Alt r`** to open tuicr directly (configured as a keybinding in `sandbox.sh`).

## Determining the Directory

**Important:** You must determine the correct git repository directory based on context.

Consider:
- The user's current working directory
- Any repository they've been working in during the session
- Explicit directory mentioned in their request
- The git status output if available

Common patterns:
- "review my changes" -> use current working directory
- "review changes in myproject" -> find that repo path
- After editing files -> use the directory of those files

## Workflow

1. **Determine target directory**:
   - Check current working directory
   - Consider recent file operations
   - Ask user if ambiguous

2. **Run the wrapper script** with a 10-minute timeout:
   ```bash
   <skill-directory>/tuicr-wrapper.sh [directory]
   ```

   **IMPORTANT:** Always set `timeout: 600000` (10 minutes) on the Bash tool call.
   The script uses `zellij run --blocking` which waits for tuicr to exit, and without
   the extended timeout the agent may background the command after 2 minutes.

3. **Handle the result**:
   - If successful: tuicr opens in a floating popup and blocks until user exits
   - If not in Zellij: relay the instructions to use the sandbox
   - If not a git repo: inform user and ask for correct path

4. **Process instructions from tuicr output**:

   The script output may contain instructions between markers:
   ```
   === TUICR INSTRUCTIONS ===
   <instructions here>
   === END TUICR INSTRUCTIONS ===
   ```

   **If instructions are present:** Parse and execute them. These are typically
   code changes or actions the user approved during the review.

   **If no instructions in output:** The script will say "No instructions exported"
   or mention clipboard. Tell the user:
   > "No instructions were exported from tuicr. If you exported to clipboard,
   > paste the instructions here and I'll execute them."

## Configuration

The wrapper script supports environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TUICR_POPUP_SIZE` | `90` | Size of floating popup as percentage of terminal |

Example with custom settings:
```bash
TUICR_POPUP_SIZE=70 <skill-directory>/tuicr-wrapper.sh /path/to/repo
```

## Example Invocations

User says: "review my changes"
-> Run tuicr-wrapper.sh with current working directory

User says: "let me review the changes in myproject"
-> Find myproject path based on context
-> Run tuicr-wrapper.sh with that path

User says: "/tuicr ~/projects/myapp"
-> Run tuicr-wrapper.sh with `~/projects/myapp`

## Zellij Tips (relay to user if needed)

- Switch focus between panes: `Alt + arrows`
- Resize the floating pane: `Ctrl+n` to enter resize mode, then `h/j/k/l`
- Toggle floating pane visibility: `Alt+f`
- Close the floating tuicr pane: Press `q` to exit tuicr (pane auto-closes)
- Lock/unlock Zellij: `Ctrl+g`
- The `Alt r` keybinding is pre-configured in the sandbox for quick access

## Error Handling

| Error | Action |
|-------|--------|
| Not in Zellij | Tell the user to restart the agent inside the sandbox |
| Not a git repo | Ask user for correct directory |
| tuicr not installed | Tell user to install tuicr |
| tuicr already running | Tell user to switch to the existing tuicr pane via `Alt + arrows` |

## When NOT to use

- When user just wants `git diff` output (use git directly)
- When reviewing remote/PR changes (use gh CLI or web)
- When user explicitly asks for non-interactive review
