#!/usr/bin/env bash
# B5: nightly backups of IoT server data + mosquitto credentials
set -euo pipefail

STAMP="$(date +%F_%H%M)"
DEST="/var/backups/iots/$STAMP.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$DEST")"
cp -a /opt/iot-server/data "$TMP/data"
if [ -f /etc/mosquitto/passwd ]; then cp -a /etc/mosquitto/passwd "$TMP/"; fi
if [ -f /etc/mosquitto/acl ]; then cp -a /etc/mosquitto/acl "$TMP/"; fi

tar -czf "$DEST" -C "$TMP" .
find /var/backups/iots -type f -name "*.tar.gz" -mtime +14 -delete
echo "$(date '+%F %T') backup ok: $DEST ($(du -h "$DEST" | cut -f1))"