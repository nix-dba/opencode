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
BIND_HOST_DEV=false

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
      WITH_FEATURES+=("gitnexus")
      shift
      ;;
    --bind-host-dev)
      BIND_HOST_DEV=true
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
  --verbose, -v             Print the full bwrap command before execution
  --ssh-keys                Mount ~/.ssh read-only in the sandbox
  --keep-secrets            Include 'secrets' directories (they are hidden by default)
  --no-net                  Disable network access in the sandbox
  --bind-host-dev           Bind host ttyUSB* and ttyACM* serial devices into the sandbox
  -w, --workspace PATH      Bind additional workspace directory (can be repeated)

If no COMMAND is given, defaults to 'zellij' with a layout running opencode.
EOF
  exit 0
fi

mkdir -p "$HOME/.config/opencode"
mkdir -p "$HOME/.config/opencode/command"
mkdir -p "$HOME/.config/tuicr"
mkdir -p "$HOME/.config/opencode/prompts"
mkdir -p "$HOME/.config/opencode/skill"
mkdir -p "$HOME/.opencode"
mkdir -p "$HOME/.local/share/opencode"
mkdir -p "$HOME/.local/state/opencode"
mkdir -p "$HOME/.cache/opencode"

# Temp files cleanup
# Script location for referencing bundled configs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLEANUP_FILES=()
cleanup() {
  rm -rf "${CLEANUP_FILES[@]}"
  find "$HOME/.config/opencode" -mindepth 1 -type f -empty -delete 2>/dev/null
  find "$HOME/.config/opencode" -mindepth 1 -type d -empty -delete 2>/dev/null
}
trap cleanup EXIT

# Zellij isolated config (tempdir, never touches host)
ZELLIJ_TMPDIR=$(mktemp -d)
CLEANUP_FILES+=("$ZELLIJ_TMPDIR")
ZELLIJ_VER=$(zellij --version | cut -d ' ' -f 2)
mkdir -p "$ZELLIJ_TMPDIR/config/zellij"
mkdir -p "$ZELLIJ_TMPDIR/cache/zellij/$ZELLIJ_VER"
touch "$ZELLIJ_TMPDIR/cache/zellij/$ZELLIJ_VER/seen_release_notes"
cat > "$ZELLIJ_TMPDIR/config/zellij/config.kdl" << 'EOF'
show_startup_tips false
show_release_notes false
default_shell "bash"
copy_command "wl-copy"
default_mode "locked"

keybinds {
    shared_except "locked" {

    }
}
EOF

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

# Feature setup (per --with-<name> flags)
FEATURE_BINDS=()
GITNEXUS_BIND=()
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir_var="${feature^^}_DIR"
  feature_dir="${!feature_dir_var}"
  [ -d "$feature_dir" ] || continue

  # Skills
  if [ -d "$feature_dir/skill" ]; then
    for skill_path in "$feature_dir/skill"/*; do
      [ -d "$skill_path" ] || continue
      FEATURE_BINDS+=(--ro-bind-try "$skill_path" "$HOME/.config/opencode/skill/$(basename "$skill_path")")
    done
  fi

  # Prompts
  if [ -d "$feature_dir/prompts" ]; then
    for prompt_file in "$feature_dir/prompts"/*.md; do
      [ -f "$prompt_file" ] || continue
      FEATURE_BINDS+=(--ro-bind-try "$prompt_file" "$HOME/.config/opencode/prompts/$(basename "$prompt_file")")
    done
  fi

  # Feature-specific setup
  case "$feature" in
    gitnexus)
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

# Skill bind mounts (individual, preserves user's own skills)
SKILL_BINDS=()
if [ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR" ]; then
  for skill_path in "$SKILL_DIR"/*; do
    [ -d "$skill_path" ] || continue
    skill_name=$(basename "$skill_path")
    SKILL_BINDS+=(--ro-bind-try "$skill_path" "$HOME/.config/opencode/skill/$skill_name")
  done
fi

# Prompt bind mounts (individual .md files)
PROMPT_BINDS=()
if [ -n "$PROMPTS_DIR" ] && [ -d "$PROMPTS_DIR" ]; then
  for prompt_file in "$PROMPTS_DIR"/*.md; do
    [ -f "$prompt_file" ] || continue
    prompt_name=$(basename "$prompt_file")
    PROMPT_BINDS+=(--ro-bind-try "$prompt_file" "$HOME/.config/opencode/prompts/$prompt_name")
  done
fi

# Command bind mounts (individual .md files)
COMMAND_BINDS=()
if [ -n "$COMMANDS_DIR" ] && [ -d "$COMMANDS_DIR" ]; then
  for cmd_file in "$COMMANDS_DIR"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    COMMAND_BINDS+=(--ro-bind-try "$cmd_file" "$HOME/.config/opencode/command/$cmd_name")
  done
fi

# opencode.jsonc bind mount (merge overlays for each enabled feature)
OPENCODE_JSONC_BINDS=()
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

  OPENCODE_JSONC_BINDS+=(--ro-bind-try "$jsonc_current" "$HOME/.config/opencode/opencode.jsonc")
fi

SSH_BINDS=()
if [ "$MOUNT_SSH" = true ] && [ -d "$HOME/.ssh" ]; then
  SSH_BINDS=(--ro-bind-try "$HOME/.ssh" "$HOME/.ssh")
fi

# Host serial device binds (ttyUSB*, ttyACM*)
TTY_GID_ARGS=()
HOST_DEV_BINDS=()
if [ "$BIND_HOST_DEV" = true ]; then
  dialout_entry=$(getent group dialout 2>/dev/null || true)
  if [ -z "$dialout_entry" ]; then
    echo "Error: --bind-host-dev requires the 'dialout' group, which does not exist." >&2
    exit 1
  fi
  dialout_gid=$(echo "$dialout_entry" | cut -d: -f3)
  dialout_members=$(echo "$dialout_entry" | cut -d: -f4)
  if ! echo "$dialout_members" | tr ',' '\n' | grep -qx "$USER"; then
    echo "Error: --bind-host-dev requires user '$USER' to be in the 'dialout' group." >&2
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

# Default command: zellij with layout, or user override
if [ $# -eq 0 ]; then
  CMD=(zellij --layout "$LAYOUT_KDL")
else
  CMD=("$@")
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
  "${SKILL_BINDS[@]}"
  "${PROMPT_BINDS[@]}"
  "${COMMAND_BINDS[@]}"
  "${FEATURE_BINDS[@]}"
  "${OPENCODE_JSONC_BINDS[@]}"
  "${WORKSPACE_BINDS[@]}"
  "${SECRETS_SHADOW[@]}"
  --bind "$ZELLIJ_TMPDIR/config/zellij" "$HOME/.config/zellij"
  --bind "$ZELLIJ_TMPDIR/cache/zellij" "$HOME/.cache/zellij"
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
