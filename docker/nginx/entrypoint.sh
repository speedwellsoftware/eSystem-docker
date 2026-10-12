#!/bin/sh
set -eu

: "${PRIMARY_DOMAIN:?PRIMARY_DOMAIN required}"
: "${DOMAINS:?DOMAINS required}"
: "${HTTPS_PORT:=443}"
export HTTPS_PORT

LIVE_DIR="/etc/letsencrypt/live/${PRIMARY_DOMAIN}"

# Bootstrap a self-signed cert so nginx can bind :443 before certbot has
# issued a real one. The certbot sidecar replaces it within minutes and
# HUPs nginx via the shared pidfile in /run/nginx.
if [ ! -s "$LIVE_DIR/fullchain.pem" ] || [ ! -s "$LIVE_DIR/privkey.pem" ]; then
    echo "[nginx-entrypoint] no cert at $LIVE_DIR — generating bootstrap self-signed"
    mkdir -p "$LIVE_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$LIVE_DIR/privkey.pem" \
        -out    "$LIVE_DIR/fullchain.pem" \
        -subj   "/CN=${PRIMARY_DOMAIN}" \
        -addext "subjectAltName=DNS:${PRIMARY_DOMAIN}"
    chmod 600 "$LIVE_DIR/privkey.pem"
    touch "$LIVE_DIR/.bootstrap"
fi

mkdir -p /run/nginx

# Render, nginx -t and link the config: the tree mounted from the checkout,
# else the copy baked into the image. Needs the cert above to exist.
sp-nginx-conf boot

exec "$@"
