#!/usr/bin/env bash

# Defaults
SHOW_HELP=false
EXPERIMENTAL_ARGS=()
NET_ARGS=(--share-net)
DO_VERBOSE=false
NO_GIT_INIT=false
WITH_FEATURES=()
EXTRA_WORKSPACES=()
MOUNT_SSH=false
KEEP_SECRETS=false
BIND_SERIAL_DEV=false
NO_SANDBOX=false
RO_BINDS=()

# Parse CLI flags before any side effects
while [ "$#" -gt 0 ]; do
  case "$1" in
    --experimental-plan-mode)
      EXPERIMENTAL_ARGS=(--setenv OPENCODE_EXPERIMENTAL "1" --setenv OPENCODE_EXPERIMENTAL_PLAN_MODE "1")
      shift
      ;;
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    --no-git-init)
      NO_GIT_INIT=true
      shift
      ;;
    --with-gitnexus)
      if ! command -v gitnexus >/dev/null 2>&1; then
        echo "Error: gitnexus is not available in the light app." >&2
        echo "Use 'nix run .#full' to get a sandbox with GitNexus support." >&2
        exit 1
      fi
      WITH_FEATURES+=("gitnexus")
      shift
      ;;
    --with-memory)
      WITH_FEATURES+=("memory")
      shift
      ;;
    --bind-serial-dev)
      BIND_SERIAL_DEV=true
      shift
      ;;
    --verbose|-v)
      DO_VERBOSE=true
      shift
      ;;
    --ssh-keys)
      MOUNT_SSH=true
      shift
      ;;
    --keep-secrets)
      KEEP_SECRETS=true
      shift
      ;;
    --no-sandbox)
      NO_SANDBOX=true
      shift
      ;;
    --no-net)
      NET_ARGS=()
      shift
      ;;
    -w|--workspace)
      if [ -z "$2" ]; then
        echo "Error: --workspace requires a path argument" >&2
        exit 1
      fi
      EXTRA_WORKSPACES+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Show help and exit (no side effects)
if [ "$SHOW_HELP" = true ]; then
  cat <<EOF
Usage: sandbox.sh [OPTIONS] [COMMAND] [ARGS...]

Run opencode inside a bubblewrap sandbox.

Options:
  -h, --help                Show this help message
  --experimental-plan-mode  Enable experimental plan mode
  --no-git-init             Skip git repository initialization prompt
  --with-gitnexus           Include GitNexus code analysis tools (skills, MCP, prompts)
                            Only available in the 'full' app: run via 'nix run .#full'
  --with-memory             Include simple-memory plugin (context/memory features)
  --verbose, -v             Print the full bwrap command before execution
  --ssh-keys                Mount ~/.ssh read-only in the sandbox
  --keep-secrets            Include 'secrets' directories (they are hidden by default)
  --no-net                  Disable network access in the sandbox
  --bind-serial-dev           Bind host ttyUSB* and ttyACM* serial devices into the sandbox
  --no-sandbox              Run opencode directly without bubblewrap; configs are
                            mirrored into a temporary XDG_CONFIG_HOME
  -w, --workspace PATH      Bind additional workspace directory (can be repeated)

Apps:
  nix run .                Light app (default) - no GitNexus, bare minimum dependencies
  nix run .#full           Full app - all dependencies including GitNexus (enabled by default)

If no COMMAND is given, defaults to a herdr session auto-launching opencode.
EOF
  exit 0
fi

# Seed default features (set per app by the Nix flake: 'full' enables gitnexus by default)
if [ -n "$DEFAULT_FEATURES" ]; then
  for feature in $DEFAULT_FEATURES; do
    if ! printf '%s\n' "${WITH_FEATURES[@]}" | grep -qx "$feature"; then
      WITH_FEATURES+=("$feature")
    fi
  done
fi

if [ "$NO_SANDBOX" != true ]; then
  mkdir -p "$HOME/.config/opencode"
  mkdir -p "$HOME/.config/opencode/command"
  mkdir -p "$HOME/.config/tuicr"
  mkdir -p "$HOME/.config/opencode/prompts"
  mkdir -p "$HOME/.config/opencode/skill"
  mkdir -p "$HOME/.opencode"
  mkdir -p "$HOME/.local/share/opencode"
  mkdir -p "$HOME/.local/state/opencode"
  mkdir -p "$HOME/.cache/opencode"
fi

# Temp files cleanup
# Script location for referencing bundled configs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLEANUP_FILES=()

# No-sandbox mode: mirror host ~/.config into a temp XDG home and overlay the bundle
CFG_TMP=""
XDG_CFG=""
XDG_STATE=""
CFG_BASE="$HOME/.config/opencode"
if [ "$NO_SANDBOX" = true ]; then
  CFG_TMP=$(mktemp -d)
  XDG_CFG="$CFG_TMP/xdg-config"
  XDG_STATE="$CFG_TMP/xdg-state"
  CFG_BASE="$XDG_CFG/opencode"
  mkdir -p "$CFG_BASE" "$XDG_CFG/herdr" "$XDG_CFG/tuicr" "$XDG_STATE"
  CLEANUP_FILES+=("$CFG_TMP")
  [ -d "$HOME/.config" ] && cp -r "$HOME/.config/." "$XDG_CFG/"
fi

# Install a config artifact: read-only bind in sandbox mode, copy into the temp tree otherwise
install_ro() {
  local src="$1" dst="$2"
  if [ "$NO_SANDBOX" = true ]; then
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
  else
    RO_BINDS+=(--ro-bind-try "$src" "$dst")
  fi
}

cleanup() {
  rm -rf "${CLEANUP_FILES[@]}"
  if [ "$NO_SANDBOX" != true ]; then
    find "$HOME/.config/opencode" -mindepth 1 -type f -empty -delete 2>/dev/null
    find "$HOME/.config/opencode" -mindepth 1 -type d -empty -delete 2>/dev/null
  fi
}
trap cleanup EXIT

# Herdr isolated config/state (tempdirs, never touches host); no-sandbox uses CFG_TMP
if [ "$NO_SANDBOX" != true ]; then
  HERDR_CFG_TMPDIR=$(mktemp -d)
  HERDR_STATE_TMPDIR=$(mktemp -d)
  CLEANUP_FILES+=("$HERDR_CFG_TMPDIR" "$HERDR_STATE_TMPDIR")
  cp "${HERDR_CONFIG:-$SCRIPT_DIR/default/herdr/config.toml}" "$HERDR_CFG_TMPDIR/config.toml"
fi

# Git init with conditional prompt
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$NO_GIT_INIT" = true ] || [ ! -t 0 ]; then
    echo "Skipped git init"
  else
    read -r -p "$PWD is not a git repo. Initialize repository now? (y/N): " answer
    case "$answer" in
      [YyjJ]* )
        git init
        git add --all .
        echo "Initialized empty git repository"
        ;;
      * )
        echo "Skipped git init"
        ;;
    esac
  fi
fi

# Workspace binds
WORKSPACES=("$PWD" "${EXTRA_WORKSPACES[@]}")
WORKSPACE_BINDS=()
for ws in "${WORKSPACES[@]}"; do
  if [ -d "$ws" ]; then
    WORKSPACE_BINDS+=(--bind "$ws" "$ws")
  fi
done

# Secrets directory shadowing (overridden by --keep-secrets)
SECRETS_SHADOW=()
if [ "$KEEP_SECRETS" = false ]; then
  for ws in "${WORKSPACES[@]}"; do
    while IFS= read -r -d '' secret_dir; do
      SECRETS_SHADOW+=(--tmpfs "$secret_dir")
    done < <(find "$ws" -type d \( -name secrets -o -name secret \) -print0 2>/dev/null)
  done
fi

# Wayland binds
WAYLAND_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$UID}/${WAYLAND_DISPLAY:-wayland-0}"
if [ -S "$WAYLAND_SOCKET" ]; then
  WAYLAND_BINDS=(--bind "$WAYLAND_SOCKET" "$WAYLAND_SOCKET")
else
  WAYLAND_BINDS=()
fi

# Network bind mounts (conditional on --no-net)
NET_BINDS=()
if [ "${#NET_ARGS[@]}" -gt 0 ]; then
  NET_BINDS=(
    --ro-bind-try /var/run/docker.sock /var/run/docker.sock
    --ro-bind-try /etc/resolv.conf /etc/resolv.conf
    --ro-bind-try /etc/hosts /etc/hosts
    --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
  )
fi

# Skill config artifacts (bundled defaults; user's own skills come from the host mirror in no-sandbox mode)
if [ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR" ]; then
  for skill_path in "$SKILL_DIR"/*; do
    [ -d "$skill_path" ] || continue
    skill_name=$(basename "$skill_path")
    install_ro "$skill_path" "$CFG_BASE/skill/$skill_name"
  done
fi

# Prompt config artifacts (individual .md files)
if [ -n "$PROMPTS_DIR" ] && [ -d "$PROMPTS_DIR" ]; then
  for prompt_file in "$PROMPTS_DIR"/*.md; do
    [ -f "$prompt_file" ] || continue
    prompt_name=$(basename "$prompt_file")
    install_ro "$prompt_file" "$CFG_BASE/prompts/$prompt_name"
  done
fi

# Command config artifacts (individual .md files)
if [ -n "$COMMANDS_DIR" ] && [ -d "$COMMANDS_DIR" ]; then
  for cmd_file in "$COMMANDS_DIR"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    install_ro "$cmd_file" "$CFG_BASE/command/$cmd_name"
  done
fi

# Feature setup (per --with-<name> flags) — appended after default artifacts so features win
GITNEXUS_BIND=()
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir_var="${feature^^}_DIR"
  feature_dir="${!feature_dir_var}"
  [ -d "$feature_dir" ] || continue

  # Skills
  if [ -d "$feature_dir/skill" ]; then
    for skill_path in "$feature_dir/skill"/*; do
      [ -d "$skill_path" ] || continue
      install_ro "$skill_path" "$CFG_BASE/skill/$(basename "$skill_path")"
    done
  fi

  # Prompts
  if [ -d "$feature_dir/prompts" ]; then
    for prompt_file in "$feature_dir/prompts"/*.md; do
      [ -f "$prompt_file" ] || continue
      install_ro "$prompt_file" "$CFG_BASE/prompts/$(basename "$prompt_file")"
    done
  fi

  # Feature-specific setup
  case "$feature" in
    gitnexus)
      command -v gitnexus >/dev/null 2>&1 || {
        echo "Warning: gitnexus feature enabled but binary not available; skipping setup." >&2
        continue
      }
      mkdir -p "$HOME/.gitnexus"
      GITNEXUS_BIND=(--bind-try "$HOME/.gitnexus" "$HOME/.gitnexus")
      if [ ! -d .gitnexus ] && [ -t 0 ]; then
        read -r -p "$PWD is not analysed via gitnexus. Analyse now? (y/N): " answer
        case "$answer" in
          [YyjJ]* )
            gitnexus analyze --index-only
            ;;
          * )
            echo "Skipped gitnexus analyze"
            ;;
        esac
      fi
      ;;
  esac
done

# opencode.jsonc (merge overlays for each enabled feature)
if [ -n "$OPENCODE_JSONC" ] && [ -f "$OPENCODE_JSONC" ]; then
  jsonc_current=$(mktemp)
  CLEANUP_FILES+=("$jsonc_current")
  sed "s|\"~/|\"$HOME/|g" "$OPENCODE_JSONC" > "$jsonc_current"

  for feature in "${WITH_FEATURES[@]}"; do
    feature_dir_var="${feature^^}_DIR"
    feature_dir="${!feature_dir_var}"
    [ -d "$feature_dir" ] || continue
    overlay="$feature_dir/opencode.jsonc"
    [ -f "$overlay" ] || continue

    overlay_tmp=$(mktemp)
    merged_tmp=$(mktemp)
    CLEANUP_FILES+=("$overlay_tmp" "$merged_tmp")
    sed "s|\"~/|\"$HOME/|g" "$overlay" > "$overlay_tmp"
    bun "$MERGE_SCRIPT" "$jsonc_current" "$overlay_tmp" "$merged_tmp"
    jsonc_current="$merged_tmp"
  done

  # Substitute ${OPENCODE_OMNIROUTE_AUTH} placeholder with the pre-built plugin path
  if [ -n "$OMNIROUTE_AUTH_PLUGIN" ]; then
    sed -i "s|\${OPENCODE_OMNIROUTE_AUTH}|file://$OMNIROUTE_AUTH_PLUGIN|" "$jsonc_current"
  fi

  if [ "$NO_SANDBOX" = true ]; then
    cp "$jsonc_current" "$CFG_BASE/opencode.jsonc"
    export OPENCODE_CONFIG="$CFG_BASE/opencode.jsonc"
  else
    RO_BINDS+=(--ro-bind-try "$jsonc_current" "$HOME/.config/opencode/opencode.jsonc")
  fi
fi

SSH_BINDS=()
if [ "$MOUNT_SSH" = true ] && [ -d "$HOME/.ssh" ]; then
  SSH_TMPDIR=$(mktemp -d)
  CLEANUP_FILES+=("$SSH_TMPDIR")
  cp -rL "$HOME/.ssh"/. "$SSH_TMPDIR"/ 2>/dev/null || true
  chmod 700 "$SSH_TMPDIR"
  find "$SSH_TMPDIR" -type f -exec chmod 600 {} +
  find "$SSH_TMPDIR" -type f -name '*.pub' -exec chmod 644 {} +
  SSH_BINDS+=(--ro-bind-try "$SSH_TMPDIR" "$HOME/.ssh")
fi
if [ "$MOUNT_SSH" = true ] && [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  SSH_BINDS+=(--bind-try "$SSH_AUTH_SOCK" "$SSH_AUTH_SOCK")
  SSH_BINDS+=(--setenv SSH_AUTH_SOCK "$SSH_AUTH_SOCK")
fi

# Host serial device binds (ttyUSB*, ttyACM*)
TTY_GID_ARGS=()
HOST_DEV_BINDS=()
if [ "$BIND_SERIAL_DEV" = true ]; then
  dialout_entry=$(getent group dialout 2>/dev/null || true)
  if [ -z "$dialout_entry" ]; then
    echo "Error: --bind-serial-dev requires the 'dialout' group, which does not exist." >&2
    exit 1
  fi
  dialout_gid=$(echo "$dialout_entry" | cut -d: -f3)
  dialout_members=$(echo "$dialout_entry" | cut -d: -f4)
  if ! echo "$dialout_members" | tr ',' '\n' | grep -qx "$USER"; then
    echo "Error: --bind-serial-dev requires user '$USER' to be in the 'dialout' group." >&2
    exit 1
  fi
  TTY_GID_ARGS=(--gid "$dialout_gid")

  for dev in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$dev" ] || continue
    HOST_DEV_BINDS+=(--dev-bind-try "$dev" "$dev")
  done
  if [ -d /dev/serial ]; then
    HOST_DEV_BINDS+=(--bind-try /dev/serial /dev/serial)
  fi
fi

# No-sandbox: finalize the temp config tree (herdr/tuicr overlays, launcher, path rewrite)
if [ "$NO_SANDBOX" = true ]; then
  install_ro "${HERDR_CONFIG:-$SCRIPT_DIR/default/herdr/config.toml}" "$XDG_CFG/herdr/config.toml"
  install_ro "${TUICR_CONFIG:-$SCRIPT_DIR/default/tuicr/config.toml}" "$XDG_CFG/tuicr/config.toml"
  cp "${HERDR_LAUNCHER:-$SCRIPT_DIR/default/herdr/herdr-launch.sh}" "$CFG_TMP/herdr-launch.sh"
  sed -i 's|socket="$HOME/.config/herdr/herdr.sock"|socket="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"|' "$CFG_TMP/herdr-launch.sh"
  find "$CFG_BASE" -type f \( -name '*.md' -o -name '*.jsonc' -o -name '*.sh' \) -exec \
    sed -i -e "s|\$HOME/.config/opencode|$CFG_BASE|g" \
           -e "s|$HOME/.config/opencode|$CFG_BASE|g" \
           -e "s|~/.config/opencode|$CFG_BASE|g" {} + 2>/dev/null || true
fi

# Default command: herdr session auto-launching opencode, or user override
if [ $# -eq 0 ]; then
  if [ "$NO_SANDBOX" = true ]; then
    CMD=(bash "$CFG_TMP/herdr-launch.sh")
  else
    CMD=(bash "$HOME/.herdr-launch.sh")
  fi
else
  CMD=("$@")
fi

# No-sandbox: run opencode directly with a temp XDG config/state home
if [ "$NO_SANDBOX" = true ]; then
  export XDG_CONFIG_HOME="$XDG_CFG"
  export XDG_STATE_HOME="$XDG_STATE"
  export OPENCODE_CONFIG_DIR="$CFG_BASE"
  export HERDR_CONFIG_PATH="$XDG_CFG/herdr/config.toml"
  export HERDR_SOCKET_PATH="$XDG_CFG/herdr/herdr.sock"
  export TMPDIR=/tmp
  export OPENCODE_DISABLE_AUTOCOMPACT=1
  export NODE_TLS_REJECT_UNAUTHORIZED=0
  export CARGO_NET_OFFLINE=false
  export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt

  if [ "${#EXPERIMENTAL_ARGS[@]}" -gt 0 ]; then
    export OPENCODE_EXPERIMENTAL=1
    export OPENCODE_EXPERIMENTAL_PLAN_MODE=1
  fi

  [ "${#NET_ARGS[@]}" -eq 0 ] && echo "Warning: --no-net cannot be enforced without the sandbox." >&2
  [ "$MOUNT_SSH" = true ] && echo "Warning: --ssh-keys is a no-op without the sandbox (SSH is already accessible)." >&2
  [ "$BIND_SERIAL_DEV" = true ] && echo "Warning: --bind-serial-dev is a no-op without the sandbox (devices are already accessible)." >&2
  echo "Warning: running without the sandbox: secrets/secret directories in workspaces are NOT hidden." >&2

  if [ "$DO_VERBOSE" = true ]; then
    echo "opencode (no sandbox):"
    echo "  XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    echo "  OPENCODE_CONFIG=$OPENCODE_CONFIG"
    echo "  HERDR_CONFIG_PATH=$HERDR_CONFIG_PATH"
    echo "  HERDR_SOCKET_PATH=$HERDR_SOCKET_PATH"
    echo "  CMD: ${CMD[*]}"
  fi

  # Run in-process (not exec) so the EXIT trap cleans up the temp tree afterwards.
  "${CMD[@]}"
  rc=$?
  # Stop the session's herdr server (matches the sandbox, where --die-with-parent does this).
  if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
    herdr server stop >/dev/null 2>&1 || true
  fi
  exit $rc
fi

# Assemble bwrap arguments
BWRAP_ARGS=(
  --unshare-all
  "${TTY_GID_ARGS[@]}"
  "${NET_ARGS[@]}"
  --die-with-parent
  # system bind mounts
  --ro-bind /usr /usr
  --ro-bind-try /lib /lib
  --ro-bind /lib64 /lib64
  --ro-bind /bin /bin
  --ro-bind-try /sbin /sbin
  --ro-bind-try /nix /nix
  --ro-bind /sys /sys
  "${NET_BINDS[@]}"
  --proc /proc
  --dev /dev
  "${HOST_DEV_BINDS[@]}"
  --tmpfs /tmp
  --tmpfs /run
  "${WAYLAND_BINDS[@]}"
  --ro-bind-try /run/current-system/sw/bin /run/current-system/sw/bin
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
  --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-0}"
  # etc bind mounts
  --ro-bind-try /etc/ssl /etc/ssl
  --ro-bind-try /etc/pki /etc/pki
  --ro-bind-try /etc/ca-certificates /etc/ca-certificates
  --ro-bind-try /etc/nix /etc/nix
  --ro-bind-try /etc/static /etc/static
  --ro-bind-try /etc/alternatives /etc/alternatives
  --ro-bind-try /etc/passwd /etc/passwd
  --ro-bind-try /etc/group /etc/group
  --ro-bind-try /etc/machine-id /etc/machine-id
  --ro-bind-try /etc/subuid /etc/subuid
  --ro-bind-try /etc/subgid /etc/subgid
  # home dirs
  --dir "$HOME"
  --dir "${XDG_RUNTIME_DIR:-/run/user/$UID}"
  --setenv HOME "$HOME"
  --chdir "$PWD"
  # home bind mounts
  --bind-try "$HOME/.cache/opencode" "$HOME/.cache/opencode"
  --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode"
  --bind-try "$HOME/.local/state/opencode" "$HOME/.local/state/opencode"
  --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode"
  --bind-try "$HOME/.opencode" "$HOME/.opencode"
  --tmpfs "$HOME/.config/tuicr"
  --ro-bind-try "${TUICR_CONFIG:-$SCRIPT_DIR/default/tuicr/config.toml}" "$HOME/.config/tuicr/config.toml"
  --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix"
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
  --bind-try "$HOME/.cargo" "$HOME/.cargo"
  --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts"
  "${GITNEXUS_BIND[@]}"
  "${SSH_BINDS[@]}"
  "${RO_BINDS[@]}"
  "${WORKSPACE_BINDS[@]}"
  "${SECRETS_SHADOW[@]}"
  --ro-bind-try "${HERDR_LAUNCHER:-$SCRIPT_DIR/default/herdr/herdr-launch.sh}" "$HOME/.herdr-launch.sh"
  --bind "$HERDR_CFG_TMPDIR" "$HOME/.config/herdr"
  --bind "$HERDR_STATE_TMPDIR" "$HOME/.local/state/herdr"
  --setenv HERDR_CONFIG_PATH "$HOME/.config/herdr/config.toml"
  --setenv TMPDIR /tmp
  --setenv OPENCODE_CONFIG_DIR "$HOME/.config/opencode"
  --setenv NODE_TLS_REJECT_UNAUTHORIZED 0
  --setenv OPENCODE_DISABLE_AUTOCOMPACT 1
  --setenv CARGO_NET_OFFLINE false
  --setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv NIX_SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv GIT_SSL_CAINFO /etc/ssl/certs/ca-certificates.crt
  "${EXPERIMENTAL_ARGS[@]}"
  "${CMD[@]}"
)

# Verbose: print the command before executing
if [ "$DO_VERBOSE" = true ]; then
  echo "bwrap \\"
  for arg in "${BWRAP_ARGS[@]}"; do
    printf '  %q \\\n' "$arg"
  done
fi

if ! bwrap "${BWRAP_ARGS[@]}"; then
  rc=$?
  restricted=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)
  if [ "$restricted" = "1" ]; then
    cat >&2 <<'EOF'
Error: bubblewrap failed because AppArmor is restricting unprivileged
user namespace creation. To fix:

  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | \
    sudo tee /etc/sysctl.d/20-apparmor-userns.conf
  sudo sysctl -p /etc/sysctl.d/20-apparmor-userns.conf

Then re-run this command.
EOF
  fi
  exit "$rc"
fi
