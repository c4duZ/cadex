#!/bin/sh
# Installs Cadex on this Mac (docs/adr/0007-one-step-install.md):
#
#   curl -fsSL https://github.com/c4duZ/cadex/releases/latest/download/install.sh | sh
#
# Downloads the latest Cadex.zip and its checksum from the GitHub release,
# checks it, and puts Cadex.app in /Applications (or ~/Applications when
# /Applications is not writable). No sudo, nothing else is downloaded.
# CADEX_DOWNLOAD (a URL or a folder) and CADEX_INSTALL_DIR override the
# source and the destination, for testing this script.
set -eu

BASE="${CADEX_DOWNLOAD:-https://github.com/c4duZ/cadex/releases/latest/download}"

fail() {
    echo "cadex: $1" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "o Cadex é um app do macOS"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || fail "o Cadex precisa do macOS 13 ou mais novo (este é o $(sw_vers -productVersion))"

if [ -n "${CADEX_INSTALL_DIR:-}" ]; then
    dest="$CADEX_INSTALL_DIR"
elif [ -w /Applications ]; then
    dest=/Applications
else
    dest="$HOME/Applications"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() {
    case "$BASE" in
        http://* | https://*) curl -fsSL "$BASE/$1" -o "$work/$1" || fail "não consegui baixar $BASE/$1" ;;
        *) cp "$BASE/$1" "$work/$1" || fail "não achei $BASE/$1" ;;
    esac
}

echo "Baixando o Cadex..."
fetch Cadex.zip
fetch Cadex.zip.sha256
expected=$(cut -d' ' -f1 < "$work/Cadex.zip.sha256")
actual=$(shasum -a 256 "$work/Cadex.zip" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || fail "o download veio diferente do publicado (checksum não confere); nada foi instalado"

ditto -x -k "$work/Cadex.zip" "$work/app" || fail "o arquivo baixado não abriu"
[ -d "$work/app/Cadex.app" ] || fail "o arquivo baixado não tem o Cadex.app"

mkdir -p "$dest"
rm -rf "$dest/Cadex.app"
mv "$work/app/Cadex.app" "$dest/Cadex.app"
# curl does not mark downloads, but a copy made by other means might be:
# only this app loses the mark, so it opens without the browser warning.
xattr -dr com.apple.quarantine "$dest/Cadex.app" 2>/dev/null || true

echo "Cadex instalado em $dest/Cadex.app"
echo "Para abrir: open \"$dest/Cadex.app\""
