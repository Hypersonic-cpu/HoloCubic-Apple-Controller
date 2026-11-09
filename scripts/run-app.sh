#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/MacCtrlHTTP.app"
if [ ! -x "$APP_DIR/Contents/MacOS/MacCtrlHTTP" ]; then
    printf '%s\n' 'App is not built yet. Run scripts/build-app.sh first.' >&2
    exit 2
fi
open "$APP_DIR"
