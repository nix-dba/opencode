#!/usr/bin/env bash

# Defaults
SHOW_HELP=false
EXPERIMENTAL_ARGS=()
NET_ARGS=(--share-net)
DO_VERBOSE=false
NO_GIT_INIT=false
SKIP_GITNEXUS=false
EXTRA_WORKSPACES=()
YOLO_ARGS=()

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
    --skip-gitnexus)
      SKIP_GITNEXUS=true
      shift
      ;;
    --verbose|-v)
      DO_VERBOSE=true
      shift
      ;;
    --yolo)
      YOLO_ARGS=(--setenv OPENCODE_YOLO "true")
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
  --skip-gitnexus           Skip gitnexus analysis prompt
  --verbose, -v             Print the full bwrap command before execution
  --yolo                    Set OPENCODE_YOLO=true in the sandbox
  --no-net                  Disable network access in the sandbox
  -w, --workspace PATH      Bind additional workspace directory (can be repeated)

If no COMMAND is given, defaults to 'opencode'.
EOF
  exit 0
fi

mkdir -p "$HOME/.config/opencode"
mkdir -p "$HOME/.config/opencode/prompts"
mkdir -p "$HOME/.config/opencode/skill"
mkdir -p "$HOME/.gitnexus"
mkdir -p "$HOME/.opencode"
mkdir -p "$HOME/.local/share/opencode"
mkdir -p "$HOME/.local/state/opencode"
mkdir -p "$HOME/.cache/opencode"

# Temp files cleanup
CLEANUP_FILES=()
cleanup() {
  rm -f "${CLEANUP_FILES[@]}"
}
trap cleanup EXIT

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

if [ ! -d .gitnexus ]; then
  if [ "$SKIP_GITNEXUS" = true ] || [ ! -t 0 ]; then
    echo "Skipped gitnexus analyze"
  else
    read -r -p "$PWD is not analysed via gitnexus. Analyse repository now? (y/N): " answer
    case "$answer" in
      [YyjJ]* )
        gitnexus analyze --index-only
        ;;
      * )
        echo "Skipped gitnexus analyze"
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

# opencode.jsonc bind mount (expand ~ to $HOME before mounting)
OPENCODE_JSONC_BINDS=()
if [ -n "$OPENCODE_JSONC" ] && [ -f "$OPENCODE_JSONC" ]; then
  jsonc_tmp=$(mktemp)
  CLEANUP_FILES+=("$jsonc_tmp")
  sed "s|\"~/|\"$HOME/|g" "$OPENCODE_JSONC" > "$jsonc_tmp"
  OPENCODE_JSONC_BINDS+=(--ro-bind-try "$jsonc_tmp" "$HOME/.config/opencode/opencode.jsonc")
fi

# Assemble bwrap arguments
BWRAP_ARGS=(
  --unshare-all
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
  --dir "$HOME/.gitnexus"
  --dir "${XDG_RUNTIME_DIR:-/run/user/$UID}"
  --setenv HOME "$HOME"
  --chdir "$PWD"
  # home bind mounts
  --bind-try "$HOME/.cache/opencode" "$HOME/.cache/opencode"
  --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode"
  --bind-try "$HOME/.local/state/opencode" "$HOME/.local/state/opencode"
  --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode"
  --bind-try "$HOME/.opencode" "$HOME/.opencode"
  --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix"
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
  --bind-try "$HOME/.cargo" "$HOME/.cargo"
  --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts"
  --bind-try "$HOME/.gitnexus" "$HOME/.gitnexus"
  "${SKILL_BINDS[@]}"
  "${PROMPT_BINDS[@]}"
  "${OPENCODE_JSONC_BINDS[@]}"
  "${WORKSPACE_BINDS[@]}"
  --setenv TMPDIR /tmp
  --setenv OPENCODE_CONFIG_DIR "$HOME/.config/opencode"
  --setenv NODE_TLS_REJECT_UNAUTHORIZED 0
  --setenv OPENCODE_DISABLE_AUTOCOMPACT 1
  --setenv CARGO_NET_OFFLINE false
  --setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv NIX_SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
  --setenv GIT_SSL_CAINFO /etc/ssl/certs/ca-certificates.crt
  "${YOLO_ARGS[@]}"
  "${EXPERIMENTAL_ARGS[@]}"
  "${@:-opencode}"
)

# Verbose: print the command before executing
if [ "$DO_VERBOSE" = true ]; then
  echo "bwrap \\"
  for arg in "${BWRAP_ARGS[@]}"; do
    printf '  %q \\\n' "$arg"
  done
fi

bwrap "${BWRAP_ARGS[@]}"
