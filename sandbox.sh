#!/usr/bin/env bash

# Defaults
SHOW_HELP=false
NET_ARGS=(--share-net)
DO_VERBOSE=false
NO_GIT_INIT=false
WITH_FEATURES=()
EXTRA_WORKSPACES=()
MOUNT_SSH=false
KEEP_SECRETS=true
BIND_SERIAL_DEV=false
NO_SANDBOX=false
RO_BINDS=()

# Parse CLI flags before any side effects
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    --no-git-init)
      NO_GIT_INIT=true
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
    --hide-secrets)
      KEEP_SECRETS=false
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

Run opencode2 inside a bubblewrap sandbox.

Options:
  -h, --help                Show this help message
  --no-git-init             Skip git repository initialization prompt
  --verbose, -v             Print the full bwrap command before execution
  --ssh-keys                Mount ~/.ssh read-only in the sandbox
  --hide-secrets            Hide 'secrets'/'secret' directories (they are visible by default)
  --no-net                  Disable network access in the sandbox
  --bind-serial-dev           Bind host ttyUSB* and ttyACM* serial devices into the sandbox
  --no-sandbox              Run opencode2 directly without bubblewrap; configs are
                            mirrored into a temporary XDG_CONFIG_HOME
  -w, --workspace PATH      Bind additional workspace directory (can be repeated)

Apps:
  nix run .                Sandbox app (bare minimum dependencies)

If no COMMAND is given, defaults to a herdr session auto-launching opencode2.
EOF
  exit 0
fi

# Seed default features (set per app by the Nix flake)
if [ -n "$DEFAULT_FEATURES" ]; then
  for feature in $DEFAULT_FEATURES; do
    if ! printf '%s\n' "${WITH_FEATURES[@]}" | grep -qx "$feature"; then
      WITH_FEATURES+=("$feature")
    fi
  done
fi

if [ "$NO_SANDBOX" != true ]; then
  mkdir -p "$HOME/.config/opencode"
  mkdir -p "$HOME/.config/opencode/commands"
  mkdir -p "$HOME/.config/tuicr"
  mkdir -p "$HOME/.config/opencode/prompts"
  mkdir -p "$HOME/.config/opencode/skills"
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
  if [ -d "$HOME/.config" ]; then
    cp -r "$HOME/.config/." "$XDG_CFG/" 2>/dev/null || true
    # The host config may contain read-only entries (e.g. leftover nix-store
    # permissions); make the mirrored tree writable so overlays can replace them.
    chmod -R u+w "$XDG_CFG" 2>/dev/null || true
  fi
fi

# Install a config artifact: read-only bind in sandbox mode, copy into the temp tree otherwise
install_ro() {
  local src="$1" dst="$2"
  if [ "$NO_SANDBOX" = true ]; then
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -r "$src" "$dst"
    # Bundled artifacts come from the read-only nix store; make copies writable
    # so later overlays and temp-tree cleanup can operate on them.
    chmod -R u+w "$dst" 2>/dev/null || true
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

# Secrets directory shadowing (opt-in via --hide-secrets)
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
    install_ro "$skill_path" "$CFG_BASE/skills/$skill_name"
  done
fi

# Command config artifacts (individual .md files)
if [ -n "$COMMANDS_DIR" ] && [ -d "$COMMANDS_DIR" ]; then
  for cmd_file in "$COMMANDS_DIR"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    install_ro "$cmd_file" "$CFG_BASE/commands/$cmd_name"
  done
fi

# Feature setup (per --with-<name> flags) — appended after default artifacts so features win
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir_var="${feature^^}_DIR"
  feature_dir="${!feature_dir_var}"
  [ -d "$feature_dir" ] || continue

  # Skills
  if [ -d "$feature_dir/skill" ]; then
    for skill_path in "$feature_dir/skill"/*; do
      [ -d "$skill_path" ] || continue
      install_ro "$skill_path" "$CFG_BASE/skills/$(basename "$skill_path")"
    done
  fi
done

# AGENTS.md: opencode2 loads instructions from AGENTS.md, not from the
# `instructions` config field (accepted but not resolved in V2). Concatenate
# the bundled base prompts with any enabled feature prompts, in order, into a
# single global AGENTS.md.
AGENTS_PARTS=()
if [ -n "$PROMPTS_DIR" ] && [ -d "$PROMPTS_DIR" ]; then
  for prompt_file in "$PROMPTS_DIR"/*.md; do
    [ -f "$prompt_file" ] && AGENTS_PARTS+=("$prompt_file")
  done
fi
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir_var="${feature^^}_DIR"
  feature_dir="${!feature_dir_var}"
  [ -d "$feature_dir/prompts" ] || continue
  for prompt_file in "$feature_dir/prompts"/*.md; do
    [ -f "$prompt_file" ] && AGENTS_PARTS+=("$prompt_file")
  done
done
if [ "${#AGENTS_PARTS[@]}" -gt 0 ]; then
  AGENTS_TMP=$(mktemp)
  CLEANUP_FILES+=("$AGENTS_TMP")
  : > "$AGENTS_TMP"
  for prompt_file in "${AGENTS_PARTS[@]}"; do
    cat "$prompt_file" >> "$AGENTS_TMP"
    printf '\n' >> "$AGENTS_TMP"
  done
  install_ro "$AGENTS_TMP" "$CFG_BASE/AGENTS.md"
fi

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

  # OmniRoute gateway resolution (host first, then a reachable default):
  #   1. OMNIROUTE_BASE_URL env (always wins when set)
  #   2. ~/.config/opencode/omniroute.json `baseURL`
  #   3. default https://omni-route.k8s.lan/v1, but only if it is reachable
  # Host/env overrides are used even if unreachable; only the default is
  # probed. Under --no-net the plugin is always disabled. When no gateway is
  # available the plugin entry is removed so it never loads with an empty
  # catalog. Credentials come from OMNIROUTE_API_KEY /
  # OMNIROUTE_MANAGEMENT_API_KEY or the OpenCode integration credential.
  if jq -e '.plugins' "$jsonc_current" >/dev/null 2>&1; then
    omni_opts='{}'
    omni_host_opts="$HOME/.config/opencode/omniroute.json"
    if [ -f "$omni_host_opts" ]; then
      omni_opts=$(jq -c '.' "$omni_host_opts" 2>/dev/null || echo '{}')
    fi

    omni_base=""
    omni_source=""
    if [ "${#NET_ARGS[@]}" -gt 0 ]; then
      omni_base="${OMNIROUTE_BASE_URL:-}"
      omni_source="OMNIROUTE_BASE_URL"
      if [ -z "$omni_base" ]; then
        omni_base=$(jq -r '.baseURL // empty' <<<"$omni_opts" 2>/dev/null || true)
        omni_source="host config"
      fi
      if [ -z "$omni_base" ]; then
        omni_default="https://omni-route.k8s.lan/v1"
        if curl -k -s -o /dev/null --connect-timeout 3 --max-time 5 "$omni_default"; then
          omni_base="$omni_default"
          omni_source="default (reachable)"
        fi
      fi
    fi

    if [ -n "$omni_base" ]; then
      echo "OmniRoute gateway: $omni_base ($omni_source)" >&2
      omni_opts=$(jq -c --arg u "$omni_base" '. + {baseURL: $u}' <<<"$omni_opts")
      omni_tmp=$(mktemp)
      CLEANUP_FILES+=("$omni_tmp")
      jq -c --argjson o "$omni_opts" \
        '(.plugins[]? | select(.package == "${OMNIROUTE_PLUGIN_V2}") | .options) = $o' \
        "$jsonc_current" > "$omni_tmp"
      jsonc_current="$omni_tmp"
    else
      echo "OmniRoute gateway unavailable; disabling the OmniRoute plugin." >&2
      omni_tmp=$(mktemp)
      CLEANUP_FILES+=("$omni_tmp")
      jq -c '
        (.plugins // []) |= map(select(.package != "${OMNIROUTE_PLUGIN_V2}"))
        | if (.plugins | length) == 0 then del(.plugins) else . end
      ' "$jsonc_current" > "$omni_tmp"
      jsonc_current="$omni_tmp"
    fi
  fi

  # Substitute ${OMNIROUTE_PLUGIN_V2} placeholder with the pre-built plugin path
  if [ -n "$OMNIROUTE_PLUGIN_V2" ]; then
    sed -i "s|\${OMNIROUTE_PLUGIN_V2}|file://$OMNIROUTE_PLUGIN_V2|" "$jsonc_current"
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
  sed -i "s|socket=\"$HOME/.config/herdr/herdr.sock\"|socket=\"${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}\"|" "$CFG_TMP/herdr-launch.sh"
  find "$CFG_BASE" -type f \( -name '*.md' -o -name '*.jsonc' -o -name '*.sh' \) -exec \
    sed -i -e "s|\$HOME/.config/opencode|$CFG_BASE|g" \
           -e "s|$HOME/.config/opencode|$CFG_BASE|g" \
           -e "s|~/.config/opencode|$CFG_BASE|g" {} + 2>/dev/null || true
fi

# Default command: herdr session auto-launching opencode2, or user override
if [ $# -eq 0 ]; then
  if [ "$NO_SANDBOX" = true ]; then
    CMD=(bash "$CFG_TMP/herdr-launch.sh")
  else
    CMD=(bash "$HOME/.herdr-launch.sh")
  fi
else
  CMD=("$@")
fi

# No-sandbox: run opencode2 directly with a temp XDG config/state home
if [ "$NO_SANDBOX" = true ]; then
  export XDG_CONFIG_HOME="$XDG_CFG"
  export XDG_STATE_HOME="$XDG_STATE"
  export OPENCODE_CONFIG_DIR="$CFG_BASE"
  export HERDR_CONFIG_PATH="$XDG_CFG/herdr/config.toml"
  export HERDR_SOCKET_PATH="$XDG_CFG/herdr/herdr.sock"
  export TMPDIR=/tmp
  export NODE_TLS_REJECT_UNAUTHORIZED=0
  export CARGO_NET_OFFLINE=false
  export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt

  [ "${#NET_ARGS[@]}" -eq 0 ] && echo "Warning: --no-net cannot be enforced without the sandbox." >&2
  [ "$MOUNT_SSH" = true ] && echo "Warning: --ssh-keys is a no-op without the sandbox (SSH is already accessible)." >&2
  [ "$BIND_SERIAL_DEV" = true ] && echo "Warning: --bind-serial-dev is a no-op without the sandbox (devices are already accessible)." >&2
  if [ "$KEEP_SECRETS" = false ]; then
    echo "Warning: --hide-secrets cannot be enforced without the sandbox: secrets/secret directories in workspaces are NOT hidden." >&2
  fi

  if [ "$DO_VERBOSE" = true ]; then
    echo "opencode2 (no sandbox):"
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
  --tmpfs "$HOME/.local/state/opencode"
  --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode"
  --bind-try "$HOME/.opencode" "$HOME/.opencode"
  --tmpfs "$HOME/.config/tuicr"
  --ro-bind-try "${TUICR_CONFIG:-$SCRIPT_DIR/default/tuicr/config.toml}" "$HOME/.config/tuicr/config.toml"
  --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix"
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
  --bind-try "$HOME/.cargo" "$HOME/.cargo"
  --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts"
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
  --setenv CARGO_NET_OFFLINE false
  --setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv NIX_SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv GIT_SSL_CAINFO /etc/ssl/certs/ca-certificates.crt
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
