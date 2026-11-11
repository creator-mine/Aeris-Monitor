#!/usr/bin/env bash
# Export the current (bare-metal) IoT server state into a migration bundle.
#
# Run ON THE OLD VPS as root. Read-only: it only copies files out.
#
#   sudo bash export.sh [DOMAIN] [OUTDIR]
#   # defaults: DOMAIN=spe4naz.online  OUTDIR=/root
#
# Produces: $OUTDIR/iot-migration-<DOMAIN>-<STAMP>.tar.gz
# (+ .sha256). Copy that file to the new VPS and run import.sh there.
set -euo pipefail

DOMAIN="${1:-spe4naz.online}"
OUTDIR="${2:-/root}"
STAMP="$(date +%F_%H%M)"
NAME="iot-migration-${DOMAIN}-${STAMP}"

SRC_SERVER=/opt/iot-server
SRC_ENV=/etc/iot-server/env
SRC_UNIT=/etc/systemd/system/iot-server.service
SRC_MOSQ=/etc/mosquitto
SRC_LE=/etc/letsencrypt
SRC_SITE=/var/www/iot-site
SRC_APP=/var/www/app
SRC_NGINX=/etc/nginx/sites-available/iot-site

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
B="$TMP/$NAME"
mkdir -p "$B"/{env,server-data,mqtt/secrets,mqtt/certs,site,reference}

log() { printf '[export] %s\n' "$*"; }

# --- server data ------------------------------------------------------------
if [ -d "$SRC_SERVER/data" ]; then
    cp -a "$SRC_SERVER/data/." "$B/server-data/"
    log "server data: $(find "$B/server-data" -type f | wc -l) files"
else
    log "WARNING: $SRC_SERVER/data not found"
fi

# --- secrets -----------------------------------------------------------------
if [ -f "$SRC_ENV" ]; then cp -a "$SRC_ENV" "$B/env/iot-server-env"; log "captured $SRC_ENV"; fi
if [ -f "$SRC_UNIT" ]; then cp -a "$SRC_UNIT" "$B/reference/iot-server.service"; fi

if [ -f "$SRC_UNIT" ]; then
    token="$(grep -oP 'REGISTER_TOKEN=\K\S+' "$SRC_UNIT" | head -1 || true)"
    if [ -n "$token" ]; then
        printf '%s\n' "$token" > "$B/env/register-token.txt"
        log "captured REGISTER_TOKEN"
    fi
fi

if [ -f "$SRC_MOSQ/passwd" ]; then cp -a "$SRC_MOSQ/passwd" "$B/mqtt/secrets/passwd"; log "captured mosquitto passwd"; fi
if [ -f "$SRC_MOSQ/acl" ]; then cp -a "$SRC_MOSQ/acl" "$B/mqtt/secrets/acl"; log "captured mosquitto acl"; fi
for f in fullchain.pem privkey.pem; do
    if [ -f "$SRC_MOSQ/certs/$f" ]; then
        cp -a "$SRC_MOSQ/certs/$f" "$B/mqtt/certs/$f"
    fi
done
if [ -f "$B/mqtt/certs/fullchain.pem" ]; then log "captured mosquitto TLS certs"; fi

# --- Let's Encrypt -----------------------------------------------------------
if [ -d "$SRC_LE" ]; then
    cp -a "$SRC_LE" "$B/letsencrypt"
    log "captured Let's Encrypt state ($(du -sh "$B/letsencrypt" | cut -f1))"
fi

# --- web content -------------------------------------------------------------
if [ -d "$SRC_SITE" ]; then
    mkdir -p "$B/site/iot-site"
    cp -a "$SRC_SITE/." "$B/site/iot-site/"
    log "site: $(du -sh "$B/site/iot-site" | cut -f1)"
fi
if [ -d "$SRC_APP" ]; then
    mkdir -p "$B/site/app"
    cp -a "$SRC_APP/." "$B/site/app/"
    log "web app: $(du -sh "$B/site/app" | cut -f1)"
fi

# --- reference configs -------------------------------------------------------
if [ -f "$SRC_NGINX" ]; then cp -a "$SRC_NGINX" "$B/reference/iot-site.nginx.conf"; fi
if [ -f "$SRC_MOSQ/conf.d/iot.conf" ]; then cp -a "$SRC_MOSQ/conf.d/iot.conf" "$B/reference/mosquitto-iot.conf"; fi

# --- manifest ----------------------------------------------------------------
{
    echo "IoT migration bundle"
    echo "created:    $(date -u '+%F %T UTC')"
    echo "host:       $(hostname)"
    echo "os:         $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
    echo "kernel:     $(uname -r)  $(uname -m)"
    echo "domain:     $DOMAIN"
    echo "node:       $(node -v 2>/dev/null || echo -)"
    echo "mosquitto:  $(mosquitto -h 2>/dev/null | head -1 || echo -)"
    echo "nginx:      $(nginx -v 2>&1 || echo -)"
    echo
    echo "contents:"
    ( cd "$B" && find . -type f -o -type l | sort | sed 's/^/  /' )
    echo
    echo "server data files:"
    ( cd "$B/server-data" 2>/dev/null && find . -type f | sort | sed 's/^/  /' ) || true
} > "$B/MANIFEST.txt"

log "packing..."
tar -czf "$OUTDIR/$NAME.tar.gz" -C "$TMP" "$NAME"
( cd "$OUTDIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )

log "done:"
echo "  $OUTDIR/$NAME.tar.gz"
echo "  $(du -h "$OUTDIR/$NAME.tar.gz" | cut -f1)  sha256 $(cut -d' ' -f1 "$OUTDIR/$NAME.tar.gz.sha256")"
echo
echo "Next: copy the .tar.gz to the new VPS and run:"
echo "  sudo bash import.sh $NAME.tar.gz"
