#!/usr/bin/env bash
# Renew Let's Encrypt certificates and refresh the copies mosquitto uses for
# the wss listener (9002), then reload nginx + restart mosquitto.
#
# Run ON THE NEW VPS as root, from the repo:
#   sudo bash refresh-certs.sh
#
# The certbot service renews automatically every 12h; this script is for
# forcing a renewal and propagating the new certs to the MQTT broker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$COMPOSE_DIR"

[ -f .env ] || { echo "no .env in $COMPOSE_DIR" >&2; exit 1; }
DOMAIN="$(grep -oP '^NGINX_DOMAIN=\K.*' .env | tr -d '\r')"
[ -n "$DOMAIN" ] || { echo "NGINX_DOMAIN not set in .env" >&2; exit 1; }
log() { printf '[certs] %s\n' "$*"; }

log "renewing for $DOMAIN..."
docker run --rm \
    -v "$COMPOSE_DIR/runtime/letsencrypt:/etc/letsencrypt" \
    -v "$COMPOSE_DIR/runtime/certbot-www:/var/www/certbot" \
    certbot/certbot renew --webroot -w /var/www/certbot \
    --cert-name "$DOMAIN" --quiet || log "renew reported no change / error"

SRC="$COMPOSE_DIR/runtime/letsencrypt/live/$DOMAIN"
DST="$COMPOSE_DIR/runtime/mqtt/certs"
if [ -f "$SRC/fullchain.pem" ] && [ -f "$SRC/privkey.pem" ]; then
    cp -L "$SRC/fullchain.pem" "$DST/fullchain.pem"
    cp -L "$SRC/privkey.pem" "$DST/privkey.pem"
    chmod 0640 "$DST"/*.pem 2>/dev/null || true
    log "refreshed mosquitto certs"
else
    log "WARNING: certificate files not found at $SRC"
fi

log "reloading nginx + restarting mqtt..."
docker compose exec -T web nginx -s reload 2>/dev/null || true
docker compose restart mqtt
log "done."
