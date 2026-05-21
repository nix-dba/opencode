#!/usr/bin/env bash
set -e -u -o pipefail

# Configuration - override via environment variables
TUICR_POPUP_SIZE="${TUICR_POPUP_SIZE:-90}"              # percentage of terminal

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[tuicr]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[tuicr]${NC} $*"
}

log_error() {
  echo -e "${RED}[tuicr]${NC} $*"
}

usage() {
  cat << EOF
Usage: $(basename "$0") [directory]

Launch tuicr in a Zellij floating pane to review git changes.

Arguments:
  directory    Git repository directory to review (default: current directory)

Environment variables:
  TUICR_POPUP_SIZE      Size of floating popup as percentage (default: 90)

Examples:
  $(basename "$0")                    # Review changes in current directory
  $(basename "$0") ~/project          # Review changes in ~/project
  TUICR_POPUP_SIZE=70 $(basename "$0") # Use 70% of screen
EOF
}

check_zellij() {
  if [[ -z "${ZELLIJ_SESSION_NAME:-}" ]]; then
    return 1
  fi
  return 0
}

check_tuicr() {
  if ! command -v tuicr &> /dev/null; then
    log_error "tuicr not found. Install it first."
    return 1
  fi
  return 0
}

check_tuicr_stdout_support() {
  tuicr --help 2>&1 | grep -q -- '--stdout'
}

check_git_repo() {
  local dir="$1"
  if ! git -C "$dir" rev-parse --git-dir &> /dev/null; then
    log_error "Not a git repository: $dir"
    return 1
  fi
  return 0
}

check_tuicr_running() {
  if zellij action list-panes 2>/dev/null | grep -q tuicr; then
    return 0
  fi
  return 1
}

launch_tuicr_pane() {
  local target_dir="$1"
  local output_file="/tmp/tuicr-output-$$"

  # Check if --stdout is supported and set up output capture
  local tuicr_cmd
  if check_tuicr_stdout_support; then
    tuicr_cmd="tuicr -w --stdout > '$output_file'"
    log_info "Using --stdout mode (output will be captured)"
  else
    tuicr_cmd="tuicr -w"
    log_warn "tuicr --stdout not supported, output will be copied to clipboard"
  fi

  log_info "Launching tuicr in floating popup (${TUICR_POPUP_SIZE}% of screen)"
  log_info "Directory: $target_dir"

  # Launch tuicr in a floating pane and block until it exits
  zellij run \
    --floating \
    --blocking \
    --close-on-exit \
    --cwd "$target_dir" \
    --height "${TUICR_POPUP_SIZE}%" \
    --width "${TUICR_POPUP_SIZE}%" \
    -- bash -c "$tuicr_cmd"

  log_info "tuicr finished"

  # Output captured instructions if --stdout was used
  if [[ -f "$output_file" ]]; then
    if [[ -s "$output_file" ]]; then
      echo ""
      echo "=== TUICR INSTRUCTIONS ==="
      cat "$output_file"
      echo "=== END TUICR INSTRUCTIONS ==="
    else
      log_info "No instructions exported from tuicr"
      log_info "If you exported to clipboard, paste the instructions here"
    fi
    rm -f "$output_file"
  else
    log_info "If you exported instructions, they are in your clipboard - paste them here"
  fi
}

main() {
  # Handle help
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  # Check for tuicr
  if ! check_tuicr; then
    exit 1
  fi

  # Determine target directory
  local target_dir="${1:-.}"
  target_dir=$(cd "$target_dir" && pwd)  # Get absolute path

  # Verify it's a git repo
  if ! check_git_repo "$target_dir"; then
    exit 1
  fi

  # Check if we're in Zellij
  if ! check_zellij; then
    log_error "Not running inside Zellij!"
    echo ""
    echo "To use tuicr with your coding agent, run that agent inside the sandbox (which starts Zellij)."
    echo ""
    echo "1. Exit the current agent session."
    echo ""
    echo "2. Restart the agent inside the sandbox."
    echo ""
    echo "3. Then run /tuicr again."
    exit 1
  fi

  # Check if tuicr is already running
  if check_tuicr_running; then
    log_warn "tuicr is already running in another pane"
    log_info "Switch to it with Alt + arrows"
    exit 0
  fi

  # Launch tuicr in a floating pane
  launch_tuicr_pane "$target_dir"
}

main "$@"
