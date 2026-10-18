#!/usr/bin/env bash
# Gera dist/tapkey-desktop_<versão>_amd64.deb a partir de desktop/ + agent/.
# Requisitos: flutter (com suporte a Linux desktop), dpkg-deb, strip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
PKG="tapkey-desktop"
STAGE="$ROOT/build/deb/${PKG}_${VERSION}"
OUT="$ROOT/dist/${PKG}_${VERSION}_amd64.deb"

echo "==> Compilando TAPKEY Desktop (release)"
( cd "$ROOT/desktop" && flutter build linux --release )
BUNDLE="$ROOT/desktop/build/linux/x64/release/bundle"

echo "==> Montando pacote em $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/$PKG" "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/256x256/apps" \
         "$STAGE/usr/share/icons/hicolor/48x48/apps"

cp -a "$BUNDLE/." "$STAGE/opt/$PKG/"
mkdir -p "$STAGE/opt/$PKG/agent"
for f in agent.py cursor_bridge.py tapkey_cursor_hook.py; do install -m 755 "$ROOT/agent/$f" "$STAGE/opt/$PKG/agent/$f"; done

# reduz o tamanho
find "$STAGE/opt/$PKG" -type f \( -name '*.so' -o -name 'tapkey_desktop' \) ! -name 'libapp.so' -exec strip --strip-unneeded {} + 2>/dev/null || true

cat > "$STAGE/usr/bin/$PKG" <<'WRAP'
#!/bin/sh
exec /opt/tapkey-desktop/tapkey_desktop "$@"
WRAP
chmod 755 "$STAGE/usr/bin/$PKG"

install -m 644 "$ROOT/packaging/tapkey-desktop.desktop" "$STAGE/usr/share/applications/$PKG.desktop"
convert "$ROOT/desktop/assets/icon.png" -resize 256x256 "$STAGE/usr/share/icons/hicolor/256x256/apps/$PKG.png"
convert "$ROOT/desktop/assets/icon.png" -resize 48x48 "$STAGE/usr/share/icons/hicolor/48x48/apps/$PKG.png"

SIZE_KB=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<CTRL
Package: $PKG
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Hélio Rosado Neto <heliorosadoneto@users.noreply.github.com>
Depends: python3, openssl, libgtk-3-0, libayatana-appindicator3-1
Recommends: librsvg2-bin
Installed-Size: $SIZE_KB
Homepage: https://github.com/heliorosadoneto/TAPKEY
Description: TAPKEY Desktop - controle seu notebook pelo celular
 Companheiro do app TAPKEY: mostra um QR para parear o celular, liga o
 agente local (Python) que abre aplicativos do notebook e fica na bandeja.
CTRL
install -m 755 "$ROOT/packaging/postinst" "$STAGE/DEBIAN/postinst"
install -m 755 "$ROOT/packaging/prerm" "$STAGE/DEBIAN/prerm"

chmod -R go-w "$STAGE"; find "$STAGE" -type d -exec chmod 755 {} +
mkdir -p "$ROOT/dist"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$OUT"
echo "==> Pronto: $OUT ($(du -h "$OUT" | cut -f1))"
