#!/usr/bin/env bash

# Configuration - override via environment variables
TUICR_POPUP_SIZE="${TUICR_POPUP_SIZE:-90}"              # percentage of terminal

log_info() {
  echo "$*"
}

log_warn() {
  echo "$*"
}

log_error() {
  echo "$*"
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

check_git_repo() {
  local dir="$1"
  if ! git -C "$dir" rev-parse --git-dir &> /dev/null; then
    return 1
  fi
  return 0
}

launch_tuicr_pane() {
  local target_dir="$1"
  local output_file="/tmp/tuicr-output-$$"

  # Check if --stdout is supported and set up output capture
  local tuicr_cmd
  tuicr_cmd="tuicr -w --stdout > '$output_file'"

  # log_info "Directory: $target_dir"

  # Launch tuicr in a floating pane and block until it exits
  zellij run \
    --floating \
    --blocking \
    --close-on-exit \
    --cwd "$target_dir" \
    --height "${TUICR_POPUP_SIZE}%" \
    --width "${TUICR_POPUP_SIZE}%" \
    -- bash -c "$tuicr_cmd"

  # Press y to exit tuicr and export the comments
  if [[ -s "$output_file" ]]; then
    cat "$output_file"
  else
    log_info "Nothing to do. Everything's fine"
  fi
  rm -f "$output_file"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if ! check_tuicr; then
    exit 1
  fi

  local target_dir="${1:-.}"
  target_dir=$(cd "$target_dir" && pwd)  # Get absolute path

  if ! check_git_repo "$target_dir"; then
    log_error "$target_dir is not a git repository!"
    exit 1
  fi

  if ! check_zellij; then
    log_error "Not running inside Zellij!"
    exit 1
  fi

  launch_tuicr_pane "$target_dir"
}

main "$@"
