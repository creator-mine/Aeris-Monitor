#!/usr/bin/env bash
# Installer: copies ops scripts, installs cron jobs, enables persistent journald
set -euo pipefail

OPS_DIR=/opt/iot-server
mkdir -p "$OPS_DIR"

install -m 0755 /root/ops/backup.sh  "$OPS_DIR/backup.sh"
install -m 0755 /root/ops/watchdog.sh "$OPS_DIR/watchdog.sh"

# cron: backup daily 03:30, watchdog every 5 min
CRON_BACKUP="30 3 * * * $OPS_DIR/backup.sh >> /var/log/iots-backup.log 2>&1"
CRON_WATCH="*/5 * * * * $OPS_DIR/watchdog.sh"
(crontab -l 2>/dev/null | grep -v "$OPS_DIR/backup.sh" ; echo "$CRON_BACKUP") | crontab -
(crontab -l 2>/dev/null | grep -v "$OPS_DIR/watchdog.sh" ; echo "$CRON_WATCH") | crontab -

# persistent journald
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
if grep -q '^#\?Storage=auto' /etc/systemd/journald.conf; then
  sed -i 's/^#\?Storage=auto.*/Storage=persistent/' /etc/systemd/journald.conf
fi
systemctl restart systemd-journald

echo "=== installed ==="
crontab -l | grep iots
loginctl --no-pager >/dev/null 2>&1 || true
echo done