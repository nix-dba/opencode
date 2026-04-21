#!/usr/bin/env bash
WORKSPACES=(
  "$PWD"
)

mkdir -p "$HOME/.config/opencode"
mkdir -p "$HOME/.opencode"
mkdir -p "$HOME/.local/share/opencode"
mkdir -p "$HOME/.local/state/opencode"
mkdir -p "$HOME/.cache/opencode"

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

bwrap \
  --unshare-all \
  --share-net \
  --die-with-parent \
  \
  --ro-bind /usr /usr \
  --ro-bind-try /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind-try /sbin /sbin \
  --ro-bind-try /nix /nix \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs /run \
  "${WAYLAND_BINDS[@]}" \
  --ro-bind-try /run/current-system/sw/bin /run/current-system/sw/bin \
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
  --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-0}" \
  \
  --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
  --ro-bind-try /etc/ssl /etc/ssl \
  --ro-bind-try /etc/ca-certificates /etc/ca-certificates \
  --ro-bind-try /etc/nix /etc/nix \
  --ro-bind-try /etc/static/nix /etc/static/nix \
  \
  --dir "$HOME" \
  --setenv HOME "$HOME" \
  --chdir "$PWD" \
  \
  --bind-try "$HOME/.cache/opencode" "$HOME/.cache/opencode" \
  --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode" \
  --bind-try "$HOME/.local/state/opencode" "$HOME/.local/state/opencode" \
  --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode" \
  --bind-try "$HOME/.opencode" "$HOME/.opencode" \
  --bind-try "$HOME/.conig/nix" "$HOME/.config/nix" \
  "${WORKSPACE_BINDS[@]}" \
  --setenv TMPDIR /tmp \
  --setenv OPENCODE_CONFIG_DIR "$HOME/.config/opencode" \
  --setenv NODE_TLS_REJECT_UNAUTHORIZED 0 \
  \
  "${@:-bash}"
