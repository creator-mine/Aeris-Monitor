#!/usr/bin/env bash
#
# Builds the Linux (.deb) installer for the IoT Modular App.
# Run on Ubuntu/Debian with a Flutter Linux-desktop toolchain.
#
# One-time prerequisites:
#   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
#     liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev \
#     libserialport-dev libnotify-dev dpkg-dev
#   flutter config --enable-linux-desktop
#
# Usage: ./build-linux-deb.sh [version]   (default version: 1.1.0)
#
set -euo pipefail

VERSION="${1:-1.1.0}"
ARCH="${ARCH:-amd64}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$HERE/../../mobile_app" && pwd)"
BUNDLE="$APP_DIR/build/linux/x64/release/bundle"
STAGE="$HERE/build/aeris-monitor_${VERSION}_${ARCH}"
OUT="$HERE/output/aeris-monitor_${VERSION}_${ARCH}.deb"
ICON="$HERE/icons/aeris-monitor.png"

echo "== flutter build linux =="
( cd "$APP_DIR" && flutter pub get && flutter build linux --release )

if [ ! -x "$BUNDLE/aeris" ]; then
  echo "ERROR: bundle not found at $BUNDLE" >&2
  exit 1
fi

echo "== staging .deb =="
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/usr/lib/aeris-monitor" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/512x512/apps"

cp -r "$BUNDLE/." "$STAGE/usr/lib/aeris-monitor/"
ln -sf ../lib/aeris-monitor/aeris "$STAGE/usr/bin/aeris-monitor"
cp "$ICON" "$STAGE/usr/share/icons/hicolor/512x512/apps/aeris-monitor.png"

cat > "$STAGE/usr/share/applications/aeris-monitor.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=IoT Modular App
GenericName=IoT Manager
Comment=Управление модульной IoT-системой
Exec=/usr/bin/aeris-monitor
Icon=aeris-monitor
Terminal=false
Categories=Utility;Development;
StartupWMClass=online.spe4naz.aeris
EOF

cat > "$STAGE/DEBIAN/control" <<EOF
Package: aeris-monitor
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: IoT Modular <iot@localhost>
Section: utils
Priority: optional
Depends: libgtk-3-0, libnotify4, libsecret-1-0
Description: Modular IoT System desktop application
 Flutter desktop client for the modular IoT system: dashboard,
 device management, firmware build/flash and import.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache   >/dev/null 2>&1 && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
exit 0
EOF
cp "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

mkdir -p "$HERE/output"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
echo "Built: $OUT"
ls -la "$OUT"
