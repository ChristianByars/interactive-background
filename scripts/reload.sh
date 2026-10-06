#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Interactive Background.app"

pkill -x InteractiveBackground || true
"$ROOT/scripts/make-app.sh"
open "$APP"

sleep 1
if pgrep -x InteractiveBackground >/dev/null; then
    echo "Running from: $APP"
else
    echo "Built but not running: $APP" >&2
    exit 1
fi
