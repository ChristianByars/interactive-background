#!/usr/bin/env bash
# Quits the running app, rebuilds it from THIS checkout and relaunches it. Usage: scripts/reload.sh (any cwd)
# Works from the main checkout or any worktree: it builds and opens the app next to the script.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Interactive Background.app"

pkill -x InteractiveBackground || true
"$ROOT/scripts/make-app.sh"   # set -e: a failed build stops here, so a stale build/ app is never opened
open "$APP"

sleep 1
if pgrep -x InteractiveBackground >/dev/null; then
    echo "Running from: $APP"
else
    echo "Built but not running: $APP" >&2
    exit 1
fi
