# Sandbox

The bubblewrap sandbox (`sandbox.sh`) provides a security boundary around opencode sessions.

## Usage

```sh
nix run github:nix-dba/opencode --refresh --accept-flake-config
```

Or from the cloned repo directly:

```sh
nix run . --refresh
```

## CLI Flags

Defined in `sandbox.sh:69-86`:

| Flag | Description |
|------|-------------|
| `--experimental-plan-mode` | Enable experimental planning mode |
| `--no-git-init` | Skip git repository initialization prompt |
| `--with-gitnexus` | Include GitNexus code analysis tools (skills, MCP, prompts) |
| `--with-memory` | Include simple-memory plugin (context/memory features) |
| `--verbose`, `-v` | Print the full bwrap command before execution |
| `--ssh-keys` | Mount `~/.ssh` read-only in the sandbox |
| `--no-net` | Disable network access in the sandbox |
| `-w`, `--workspace PATH` | Bind additional workspace directory (repeatable) |

## Behavior

- Creates necessary directories (`~/.config/opencode`, `~/.opencode`, etc.) before sandbox entry
- If the current directory is not a git repo, prompts to initialize one
- If `--with-gitnexus` is passed and the repo lacks `.gitnexus`, prompts to run `gitnexus analyze --index-only`
- Uses an isolated Zellij config (temp directory) to avoid polluting host Zellij state (`sandbox.sh:118-137`)
- Default command is `zellij --layout <layout.kdl>` which runs opencode inside Zellij
- If arguments are provided, they are passed directly as the sandbox command instead
- Network binds (`docker.sock`, `resolv.conf`, `hosts`, `nsswitch.conf`) are conditional on `--no-net`
- Wayland socket is auto-detected and mounted for GUI clipboard support
- SSH keys are mounted only when `--ssh-keys` is passed
- Individual skill, prompt, and command directories are mounted as read-only bind mounts from the flake default directory, plus per-feature overlays for enabled `--with-*` flags

## Sandbox Bind Mounts

The sandbox (`sandbox.sh:254-325`) mounts:
- System: `/usr`, `/lib`, `/lib64`, `/bin`, `/sbin`, `/nix`, `/sys`, `/proc`, `/dev`
- Network files (conditional): `/etc/resolv.conf`, `/etc/hosts`, `/etc/nsswitch.conf`, `/var/run/docker.sock`
- TLS/SSL: `/etc/ssl`, `/etc/pki`, `/etc/ca-certificates`, `/etc/nix`, `/etc/static`
- User config: `~/.config/opencode` (read-write), `~/.config/tuicr` (tmpfs), `~/.config/git`, `~/.config/nix`
- User data: `~/.cache/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`
- GitNexus: `~/.gitnexus` (read-write, only when `--with-gitnexus`)
- Zellij: isolated temp config and cache directories
