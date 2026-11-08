#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_BIN="$ROOT_DIR/build/MacCtrlHTTP.app/Contents/MacOS/MacCtrlHTTP"
if [ ! -x "$APP_BIN" ]; then
    printf '%s\n' 'App is not built yet. Run scripts/build-app.sh first.' >&2
    exit 2
fi
exec "$APP_BIN"
