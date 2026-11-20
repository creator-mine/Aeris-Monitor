#!/usr/bin/env bash
# Import a migration bundle onto the NEW VPS and bring up the Docker stack.
#
# Run ON THE NEW VPS as root, from inside the repository (deploy/docker/migrate):
#
#   sudo bash import.sh /root/iot-migration-spe4naz.online-<stamp>.tar.gz
#
# Optional:
#   --repo DIR     repository root (default: three levels above this script)
#   --no-up        prepare files/.env only, do not start the stack
#   --no-docker    skip Docker installation
#
# What it does:
#   1. installs Docker (unless present)
#   2. unpacks the bundle into ./runtime/ (bind-mount source of the stack)
#   3. writes .env from the imported secrets
#   4. applies firewall rules
#   5. `docker compose up -d --build`
set -euo pipefail

BUNDLE=""
REPO=""
DO_UP=1
DO_DOCKER=1

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --no-up) DO_UP=0; shift ;;
        --no-docker) DO_DOCKER=0; shift ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) BUNDLE="$1"; shift ;;
    esac
done

[ "$(id -u)" = "0" ] || { echo "run as root (sudo)" >&2; exit 1; }
[ -n "$BUNDLE" ] || { echo "usage: import.sh <bundle.tar.gz> [--repo DIR] [--no-up]" >&2; exit 2; }
[ -f "$BUNDLE" ] || { echo "bundle not found: $BUNDLE" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
COMPOSE_DIR="$REPO/deploy/docker"
[ -f "$COMPOSE_DIR/docker-compose.yml" ] || { echo "compose not found at $COMPOSE_DIR" >&2; exit 1; }

log() { printf '[import] %s\n' "$*"; }

# --- 1. docker ---------------------------------------------------------------
if [ "$DO_DOCKER" = "1" ] && ! command -v docker >/dev/null 2>&1; then
    log "installing docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
if command -v docker >/dev/null 2>&1; then
    docker compose version >/dev/null 2>&1 || {
        log "installing docker compose plugin..."
        apt-get update -y && apt-get install -y docker-compose-plugin
    }
fi

# --- 2. unpack ---------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$BUNDLE" -C "$TMP"
B="$(find "$TMP" -maxdepth 1 -mindepth 1 -type d | head -1)"
[ -n "$B" ] || { echo "bundle has no top-level directory" >&2; exit 1; }
log "bundle: $(basename "$B")"

DOMAIN="$(grep -oP '^domain:\s+\K\S+' "$B/MANIFEST.txt" 2>/dev/null || echo spe4naz.online)"

R="$COMPOSE_DIR/runtime"
mkdir -p "$R"/{data,site,mqtt/data,mqtt/log,mqtt/secrets,mqtt/certs,letsencrypt,certbot-www}

copy_tree() { # src dst  (copy contents if src exists)
    if [ -d "$1" ]; then mkdir -p "$2"; cp -a "$1/." "$2/"; log "  $2 <- $1"; fi
}

copy_tree "$B/server-data"      "$R/data"
copy_tree "$B/mqtt/secrets"     "$R/mqtt/secrets"
copy_tree "$B/mqtt/certs"       "$R/mqtt/certs"
copy_tree "$B/letsencrypt"      "$R/letsencrypt"
copy_tree "$B/site/iot-site"    "$R/site"
copy_tree "$B/site/app"         "$R/site/app"

# nginx serves from a non-root worker; make sure everything is traversable
# and readable regardless of the ownership preserved from the old host.
if [ -d "$R/site" ]; then chmod -R a+rX "$R/site" 2>/dev/null || true; fi

# The old VPS shipped a certbot deploy hook that copied certs into
# /etc/mosquitto (absent in the container). Remove it so `certbot renew`
# does not fail; MQTT certs are refreshed by migrate/refresh-certs.sh.
if [ -d "$R/letsencrypt/renewal-hooks/deploy" ]; then
    rm -f "$R/letsencrypt/renewal-hooks/deploy/"*.sh 2>/dev/null || true
    rmdir "$R/letsencrypt/renewal-hooks/deploy" 2>/dev/null || true
    log "  removed legacy certbot deploy hooks"
fi

# Keep only the renewal config for DOMAIN and point its webroot at the path
# nginx serves inside the container (/var/www/certbot). Drop the rest (other
# domains from the old multi-site host are not served here).
if [ -d "$R/letsencrypt/renewal" ]; then
    for conf in "$R/letsencrypt/renewal"/*.conf; do
        [ -e "$conf" ] || continue
        n="$(basename "$conf" .conf)"
        if [ "$n" != "$DOMAIN" ]; then
            rm -f "$conf"; log "  dropped renewal conf for $n"
        else
            sed -i 's#/var/www/letsencrypt#/var/www/certbot#g' "$conf"
            log "  normalized renewal conf for $n (webroot=/var/www/certbot)"
        fi
    done
fi

# Fallback: seed static site from the repository if the bundle had none.
if [ -z "$(ls -A "$R/site" 2>/dev/null)" ] && [ -d "$REPO/deploy/site" ]; then
    cp -a "$REPO/deploy/site/." "$R/site/"
    log "  seeded runtime/site from repo deploy/site"
fi

# --- 3. compose .env ---------------------------------------------------------
ENVF="$B/env/iot-server-env"
val() { grep -oP "^$1=\K.*" "$ENVF" 2>/dev/null | head -1 || true; }

PANEL_PASSWORD="$(val PANEL_PASSWORD)"
MQTT_PASSWORD="$(val MQTT_PASSWORD)"
MQTT_USER="$(val MQTT_USER)"; MQTT_USER="${MQTT_USER:-app}"
MQTT_DEVICE_USER="$(val MQTT_DEVICE_USER)"; MQTT_DEVICE_USER="${MQTT_DEVICE_USER:-device}"
MQTT_DEVICE_PASSWORD="$(val MQTT_DEVICE_PASSWORD)"

STALE_MS="$(val STALE_MS)";                       STALE_MS="${STALE_MS:-180000}"
MAX_DEVICES_PER_IP="$(val MAX_DEVICES_PER_IP)";   MAX_DEVICES_PER_IP="${MAX_DEVICES_PER_IP:-20}"
RATE_LIMIT_REGISTER="$(val RATE_LIMIT_REGISTER)"; RATE_LIMIT_REGISTER="${RATE_LIMIT_REGISTER:-20}"
RATE_LIMIT_HEARTBEAT="$(val RATE_LIMIT_HEARTBEAT)"; RATE_LIMIT_HEARTBEAT="${RATE_LIMIT_HEARTBEAT:-120}"
RATE_LIMIT_WRITE="$(val RATE_LIMIT_WRITE)";       RATE_LIMIT_WRITE="${RATE_LIMIT_WRITE:-60}"
RATE_LIMIT_READ="$(val RATE_LIMIT_READ)";         RATE_LIMIT_READ="${RATE_LIMIT_READ:-120}"

ENV_OUT="$COMPOSE_DIR/.env"
if [ -f "$ENV_OUT" ]; then
    cp -a "$ENV_OUT" "$ENV_OUT.bak.$(date +%F_%H%M%S)"
    log "existing .env backed up"
fi
umask 077
cat > "$ENV_OUT" <<EOF
# Generated by migrate/import.sh on $(date -u '+%F %T UTC')
NGINX_DOMAIN=$DOMAIN
NGINX_TLS=1
CERTBOT_EMAIL=
PANEL_PASSWORD=$PANEL_PASSWORD
MQTT_USER=$MQTT_USER
MQTT_PASSWORD=$MQTT_PASSWORD
MQTT_DEVICE_USER=$MQTT_DEVICE_USER
MQTT_DEVICE_PASSWORD=$MQTT_DEVICE_PASSWORD
STALE_MS=$STALE_MS
MAX_DEVICES_PER_IP=$MAX_DEVICES_PER_IP
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_REGISTER=$RATE_LIMIT_REGISTER
RATE_LIMIT_HEARTBEAT=$RATE_LIMIT_HEARTBEAT
RATE_LIMIT_WRITE=$RATE_LIMIT_WRITE
RATE_LIMIT_READ=$RATE_LIMIT_READ
EOF
log "wrote $ENV_OUT (domain=$DOMAIN)"
if [ -z "$MQTT_DEVICE_PASSWORD" ]; then
    log "WARNING: MQTT_DEVICE_PASSWORD is empty — device registration stays open until it is set in .env"
fi

# Certificates/key material should not be world-readable.
chown -R root:root "$R/letsencrypt" "$R/mqtt/certs" "$R/mqtt/secrets" 2>/dev/null || true
chmod 0600 "$R/mqtt/secrets/passwd" 2>/dev/null || true

# --- 4. firewall -------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    for p in 22 80 443 8883 9002; do ufw allow "$p"/tcp >/dev/null 2>&1 || true; done
    ufw deny 3100/tcp >/dev/null 2>&1 || true
    yes | ufw enable >/dev/null 2>&1 || true
    log "ufw rules applied"
fi

# --- 5. up -------------------------------------------------------------------
if [ "$DO_UP" = "1" ]; then
    log "docker compose --profile certbot up -d --build"
    ( cd "$COMPOSE_DIR" && docker compose --profile certbot up -d --build )
    log "waiting for health..."
    for i in $(seq 1 30); do
        if curl -fsS --max-time 3 "http://127.0.0.1/healthz" >/dev/null 2>&1; then
            log "healthy"; break
        fi
        sleep 2
    done
    ( cd "$COMPOSE_DIR" && docker compose ps )
else
    log "prepared only (--no-up). Start with: cd $COMPOSE_DIR && docker compose --profile certbot up -d --build"
fi

echo
log "done."
echo "  panel:  https://$DOMAIN/panel/"
echo "  api:    https://$DOMAIN/api/v1/health"
echo "  app:    https://$DOMAIN/app/"
