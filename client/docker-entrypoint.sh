#!/bin/sh
# Generate /env.js from the host-mounted .env so the SPA can pick up
# config without rebuilding the image.
set -eu

ENV_FILE="${ENV_FILE:-/config/.env}"
OUT="${ENV_JS_OUT:-/usr/share/nginx/html/env.js}"

WS_URL="${VITE_WS_URL:-wss://sharelist.servehttp.com}"
API_ORIGIN="${VITE_API_ORIGIN:-https://sharelist.servehttp.com}"
GOOGLE_CLIENT_ID="${VITE_GOOGLE_CLIENT_ID:-}"

js_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/'"'"'/\\'"'"'/g'
}

if [ -f "$ENV_FILE" ]; then
  echo "share-list-client: loading env from $ENV_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    # trim CR (Windows line endings) and skip blanks / comments
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
      ''|\#*) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    # strip optional surrounding quotes
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    case "$key" in
      VITE_WS_URL) WS_URL=$val ;;
      VITE_API_ORIGIN) API_ORIGIN=$val ;;
      VITE_GOOGLE_CLIENT_ID) GOOGLE_CLIENT_ID=$val ;;
      # Also accept server-style names if operators reuse one file
      PUBLIC_URL) WS_URL=$val ;;
      PUBLIC_HTTPS_URL) API_ORIGIN=$val ;;
      GOOGLE_WEB_CLIENT_ID) GOOGLE_CLIENT_ID=$val ;;
    esac
  done < "$ENV_FILE"
else
  echo "share-list-client: warning: $ENV_FILE not found; using defaults / process env"
fi

cat > "$OUT" <<EOF
window.__SHARE_LIST_ENV__={
  VITE_WS_URL:"$(js_escape "$WS_URL")",
  VITE_API_ORIGIN:"$(js_escape "$API_ORIGIN")",
  VITE_GOOGLE_CLIENT_ID:"$(js_escape "$GOOGLE_CLIENT_ID")"
};
EOF

exec nginx -g 'daemon off;'
