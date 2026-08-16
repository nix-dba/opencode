#!/usr/bin/env bash

set -euo pipefail

# Start the headless herdr server, create a workspace for $PWD, auto-launch
# opencode in its root pane, then attach the client. The client blocks until
# the user detaches; bwrap then tears down the namespace (killing the server).

herdr server >/dev/null 2>&1 &

socket="$HOME/.config/herdr/herdr.sock"
for _ in $(seq 1 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done

resp=$(herdr workspace create --cwd "$PWD" --no-focus)
root_pane=$(printf '%s' "$resp" | jq -r '.result.root_pane.pane_id')

herdr pane run "$root_pane" "opencode"

herdr
