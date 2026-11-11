#!/usr/bin/env bash
# B3: watchdog - restart iot-server if health probe fails
LOG=/var/log/iots-watchdog.log

ts() { date '+%F %T'; }

if ! curl -fsS --max-time 10 http://127.0.0.1:3100/api/v1/health >/dev/null 2>&1; then
  echo "$(ts) health failed -> restarting iot-server" >> "$LOG"
  systemctl restart iot-server
  sleep 6
  if curl -fsS --max-time 10 http://127.0.0.1:3100/api/v1/health >/dev/null 2>&1; then
    echo "$(ts) recovered" >> "$LOG"
  else
    echo "$(ts) STILL DOWN after restart" >> "$LOG"
  fi
fi