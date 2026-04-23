#!/usr/bin/env bash
INSTANCE_ID=$(openssl rand -hex 4)
PODMAN_SOCKET="/run/user/$UID/podman-${INSTANCE_ID}.sock"
PODMAN_DATA_DIR="$HOME/.local/share/containers-${INSTANCE_ID}"
export PODMAN_SOCKET

WORKSPACES=(
  "$PWD"
)

mkdir -p "$HOME/.config/opencode"
mkdir -p "$HOME/.opencode"
mkdir -p "$HOME/.local/share/opencode"
mkdir -p "$HOME/.local/state/opencode"
mkdir -p "$HOME/.cache/opencode"
mkdir -p "$PODMAN_DATA_DIR"

# Ensure /run/user/$UID exists for the podman socket
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
mkdir -p "$RUNTIME_DIR"

# Create podman config using vfs driver (no newuidmap/userns needed)
mkdir -p "$HOME/.config/containers"
cat > "$HOME/.config/containers/storage.conf" << STORAGEEOF
[storage]
driver = "vfs"
graphroot = "${PODMAN_DATA_DIR}/storage"
runroot = "${PODMAN_DATA_DIR}/run"
STORAGEEOF

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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

WORKSPACE_BINDS=()
for ws in "${WORKSPACES[@]}"; do
  if [ -d "$ws" ]; then
    WORKSPACE_BINDS+=(--bind "$ws" "$ws")
  fi
done

WAYLAND_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$UID}/${WAYLAND_DISPLAY:-wayland-0}"
if [ -S "$WAYLAND_SOCKET" ]; then
  WAYLAND_BINDS=(--bind "$WAYLAND_SOCKET" "$WAYLAND_SOCKET")
else
  WAYLAND_BINDS=()
fi

# Start podman system service OUTSIDE bubblewrap with vfs storage
podman --storage-driver vfs \
  --root "${PODMAN_DATA_DIR}/storage" \
  --runroot "${PODMAN_DATA_DIR}/run" \
  system service "unix://${PODMAN_SOCKET}" &>/dev/null &
PODMAN_PID=$!

# Wait for socket to appear
for _i in $(seq 1 30); do
  if [ -S "$PODMAN_SOCKET" ]; then
    break
  fi
  sleep 0.5
done

if [ ! -S "$PODMAN_SOCKET" ]; then
  echo "ERROR: podman socket not created" >&2
  exit 1
fi

cleanup() {
  kill "$PODMAN_PID" 2>/dev/null
  wait "$PODMAN_PID" 2>/dev/null
  rm -rf "$PODMAN_DATA_DIR"
}
trap cleanup EXIT

# Enter bubblewrap with podman socket already available
bwrap \
  --share-net \
  --die-with-parent \
  \
  --ro-bind /usr /usr \
  --ro-bind-try /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind-try /sbin /sbin \
  --ro-bind-try /nix /nix \
  --ro-bind /sys /sys \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --bind "$RUNTIME_DIR" "$RUNTIME_DIR" \
  "${WAYLAND_BINDS[@]}" \
  --ro-bind-try /run/current-system/sw/bin /run/current-system/sw/bin \
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
  --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-0}" \
  \
  --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
  --ro-bind-try /etc/ssl /etc/ssl \
  --ro-bind-try /etc/pki /etc/pki \
  --ro-bind-try /etc/ca-certificates /etc/ca-certificates \
  --ro-bind-try /etc/nix /etc/nix \
  --ro-bind-try /etc/static /etc/static \
  --ro-bind-try /etc/alternatives /etc/alternatives \
  --ro-bind-try /etc/passwd /etc/passwd \
  --ro-bind-try /etc/group /etc/group \
  --ro-bind-try /etc/machine-id /etc/machine-id \
  --ro-bind-try /etc/subuid /etc/subuid \
  --ro-bind-try /etc/subgid /etc/subgid \
  \
  --dir "$HOME" \
  --dir "${XDG_RUNTIME_DIR:-/run/user/$UID}" \
  --setenv HOME "$HOME" \
  --chdir "$PWD" \
  \
  --bind-try "$HOME/.cache/opencode" "$HOME/.cache/opencode" \
  --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode" \
  --bind-try "$HOME/.local/state/opencode" "$HOME/.local/state/opencode" \
  --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode" \
  --bind-try "$HOME/.opencode" "$HOME/.opencode" \
  --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix" \
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git" \
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --bind-try "$HOME/.cargo" "$HOME/.cargo" \
  --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts" \
  --bind "$PODMAN_SOCKET" "$PODMAN_SOCKET" \
  "${WORKSPACE_BINDS[@]}" \
  --setenv TMPDIR /tmp \
  --setenv NODE_TLS_REJECT_UNAUTHORIZED 0 \
  --setenv OPENCODE_CONFIG_DIR "$HOME/.config/opencode" \
  --setenv OPENCODE_EXPERIMENTAL "1" \
  --setenv OPENCODE_EXPERIMENTAL_PLAN_MODE "1" \
  \
  "${@:-opencode}"
