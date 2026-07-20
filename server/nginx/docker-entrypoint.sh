#!/bin/sh
set -eu

RELAY_HOST="${HOSTNAME:-sharelist.servehttp.com}"
CERT_NAME="${CERT_NAME:-$RELAY_HOST}"
CERT_PATH="/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem"

export RELAY_HOST CERT_NAME

# Only substitute our host vars — leave nginx $host / $scheme alone.
SUBST='${RELAY_HOST} ${CERT_NAME}'

mkdir -p /etc/nginx/conf.d /var/www/certbot

if [ -f "$CERT_PATH" ]; then
  envsubst "$SUBST" \
    < /etc/nginx/templates/http-redirect.conf.template > /etc/nginx/conf.d/http.conf
  envsubst "$SUBST" \
    < /etc/nginx/templates/https.conf.template > /etc/nginx/conf.d/https.conf
  echo "nginx: TLS enabled for ${RELAY_HOST} (web UI at /web/)"
else
  envsubst "$SUBST" \
    < /etc/nginx/templates/http-proxy.conf.template > /etc/nginx/conf.d/http.conf
  rm -f /etc/nginx/conf.d/https.conf
  echo "nginx: HTTP-only — obtain certs with: docker compose --profile certs run --rm certbot-init"
fi

nginx -t
exec nginx -g 'daemon off;'
