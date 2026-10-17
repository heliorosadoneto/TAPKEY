#!/usr/bin/env bash
# Instala o TAPKEY Desktop (Linux Mint / Ubuntu / Debian).
#
#   curl -fsSL https://raw.githubusercontent.com/heliorosadoneto/TAPKEY/main/install.sh | bash
#
# Ordem: usa um .deb local (dist/ ou ao lado do script) -> baixa o .deb da última
# Release do GitHub -> (se houver Flutter) compila o .deb a partir do código.
set -euo pipefail

REPO="heliorosadoneto/TAPKEY"
VERSION="0.1.0"
DEB_NAME="tapkey-desktop_${VERSION}_amd64.deb"
URL="https://github.com/${REPO}/releases/latest/download/${DEB_NAME}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

DEB=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
for c in "$HERE/dist/$DEB_NAME" "$HERE/$DEB_NAME"; do
  [ -f "$c" ] && DEB="$c" && break
done

if [ -z "$DEB" ]; then
  say "Baixando $DEB_NAME"
  if curl -fsSL "$URL" -o "$TMP/$DEB_NAME"; then
    DEB="$TMP/$DEB_NAME"
  elif command -v flutter >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    say "Release não encontrada; compilando a partir do código"
    git clone --depth 1 "https://github.com/${REPO}.git" "$TMP/src"
    ( cd "$TMP/src" && flutter pub get >/dev/null && ./packaging/build_deb.sh "$VERSION" )
    DEB="$TMP/src/dist/$DEB_NAME"
  else
    echo "Não consegui baixar o .deb e o Flutter não está instalado." >&2
    echo "Veja 'Instalação' no README para compilar manualmente." >&2
    exit 1
  fi
fi

say "Instalando $DEB (pede sua senha de administrador)"
sudo apt-get install -y "$DEB"
say "Pronto! Abra 'TAPKEY Desktop' no menu ou rode: tapkey-desktop"
