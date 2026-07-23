#!/bin/sh
# Load the host-mounted .env (may be mode 600) by copying as root, then
# drop privileges and start Node with --env-file.
set -eu

SRC="${ENV_FILE:-/app/.env}"
DST=/tmp/sharelist.env

if [ -f "$SRC" ]; then
  echo "share-list: loading env from $SRC"
  cp "$SRC" "$DST"
else
  echo "share-list: warning: $SRC not found"
  : >"$DST"
fi
chown sharelist:sharelist "$DST"
chmod 400 "$DST"

exec su-exec sharelist node --use-system-ca --env-file="$DST" dist/index.js
