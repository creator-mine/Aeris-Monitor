#!/usr/bin/env bash
# Daily snapshot of the IoT stack state (./runtime + .env) with rotation.
# Restore: extract archive in deploy/docker/ and `docker compose up -d`.
# Intended to run from root's cron: 0 3 * * * /opt/iot/deploy/docker/backup.sh
set -euo pipefail

BASE=/opt/iot/deploy/docker
OUT=/var/backups/iot
LOG=/var/log/iot-backup.log
KEEP=14
STAMP=$(date +%F_%H%M%S)
ARCHIVE="$OUT/iot-$STAMP.tar.gz"

mkdir -p "$OUT"
cd "$BASE"

log(){ echo "[backup] $(date -Is) $*" >> "$LOG"; }

log "start"

if tar -czf "$ARCHIVE" runtime .env --warning=no-file-changed; then
    tar -tzf "$ARCHIVE" >/dev/null 2>&1 || { log "verify failed, removing bad archive"; rm -f "$ARCHIVE"; exit 1; }
    chmod 600 "$ARCHIVE"
    ln -sf "$(basename "$ARCHIVE")" "$OUT/iot-latest.tar.gz"
    find "$OUT" -maxdepth 1 -name 'iot-*.tar.gz' -mtime +"$KEEP" -delete
    log "ok archive=$(basename "$ARCHIVE") size=$(du -h "$ARCHIVE" | cut -f1) kept=$(find "$OUT" -maxdepth 1 -name 'iot-*.tar.gz' | wc -l)"
else
    rm -f "$ARCHIVE"
    log "FAILED tar; previous backups untouched"
    exit 1
fi