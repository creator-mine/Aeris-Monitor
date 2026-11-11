#!/usr/bin/env sh
# Prepares mosquitto state, then re-executes the original command.
#
# Credentials (passwd + acl):
#   * If secrets already exist (migrated / previous run) -> reused as-is.
#   * Otherwise generated from MQTT_* env vars (first start).
#
# TLS (listener 9002, wss): appended to the runtime config only when
# /mosquitto/certs/{fullchain,privkey}.pem are present (migrated certs).
set -e

MQTT_USER="${MQTT_USER:-app}"
MQTT_PASSWORD="${MQTT_PASSWORD:-changeme}"
MQTT_DEVICE_USER="${MQTT_DEVICE_USER:-device}"
MQTT_DEVICE_PASSWORD="${MQTT_DEVICE_PASSWORD:-changeme}"

SECRETS=/mosquitto/secrets
CERTS=/mosquitto/certs
BASE=/mosquitto/config/mosquitto.conf
RUNTIME=/mosquitto/config/mosquitto.runtime.conf

mkdir -p "$SECRETS" "$CERTS" /mosquitto/data /mosquitto/log
# The broker expects the passwd file owned by mosquitto with mode 600.
# (`mosquitto_passwd` run as root may print a contradictory "not root"
# warning; the running broker is the authority here.)
chown -R mosquitto:mosquitto /mosquitto/data /mosquitto/log "$SECRETS" 2>/dev/null || true
chown -R mosquitto:mosquitto "$CERTS" 2>/dev/null || true
# Imported certs often come as 0640 root:root; make them readable by the
# mosquitto user after the chown above.
[ -f "$CERTS/fullchain.pem" ] && chmod 0644 "$CERTS/fullchain.pem" 2>/dev/null || true
[ -f "$CERTS/privkey.pem" ] && chmod 0640 "$CERTS/privkey.pem" 2>/dev/null || true

# --- credentials ---
if [ -s "$SECRETS/passwd" ]; then
    echo "[mqtt] reusing existing password file"
else
    touch "$SECRETS/passwd"
    mosquitto_passwd -b "$SECRETS/passwd" "$MQTT_USER" "$MQTT_PASSWORD"
    mosquitto_passwd -b "$SECRETS/passwd" "$MQTT_DEVICE_USER" "$MQTT_DEVICE_PASSWORD"
    echo "[mqtt] credentials created for '$MQTT_USER' and '$MQTT_DEVICE_USER'"
fi

chmod 0600 "$SECRETS/passwd" 2>/dev/null || true

if [ -s "$SECRETS/acl" ]; then
    echo "[mqtt] reusing existing ACL"
else
    sed -e "s|@@APP_USER@@|$MQTT_USER|g" \
        -e "s|@@DEVICE_USER@@|$MQTT_DEVICE_USER|g" \
        /mosquitto/config/acl.template > "$SECRETS/acl"
    echo "[mqtt] ACL rendered from template"
fi

# --- runtime config (base + optional TLS listener) ---
cp "$BASE" "$RUNTIME"
if [ -f "$CERTS/fullchain.pem" ] && [ -f "$CERTS/privkey.pem" ]; then
    cat >> "$RUNTIME" <<EOF

# MQTT over TLS for devices and native apps
listener 8883 0.0.0.0
protocol mqtt
certfile $CERTS/fullchain.pem
keyfile $CERTS/privkey.pem

# Secure WebSocket (TLS) for browser MQTT clients (live panel)
listener 9002 0.0.0.0
protocol websockets
certfile $CERTS/fullchain.pem
keyfile $CERTS/privkey.pem
EOF
    echo "[mqtt] TLS listeners 8883 (mqtt) and 9002 (wss) enabled"
else
    echo "[mqtt] no certificates -> TLS listeners 8883/9002 disabled"
fi

exec "$@"
