#!/bin/bash
# Makes a Cadex release (docs/plans/7-mvp-release.md, fase C): Cadex.app,
# Cadex.zip with its checksum, Cadex.dmg and install.sh in dist/, with names
# without the version, so releases/latest/download/... always gets the last.
#
#   apps/macos/packaging/release.sh                         # only builds dist/
#   apps/macos/packaging/release.sh --publish "O que mudou"  # and publishes on GitHub
#
# Before publishing, raise CFBundleShortVersionString and CFBundleVersion in
# Info.plist. Needs create-dmg (brew) and gh logged in to the account that
# owns the repository. create-dmg arranges the DMG window by driving the
# Finder: run it in a logged-in session (CADEX_DMG_PLAIN=1 skips that step
# and gives a DMG without the background and positions).
set -euo pipefail
PACKAGING="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PACKAGING/../../.." && pwd)"
DIST="$ROOT/dist"
REPO=c4duZ/cadex
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PACKAGING/Info.plist")
TAG="v$VERSION"

PUBLISH=0
NOTES=""
if [[ "${1:-}" == "--publish" ]]; then
    PUBLISH=1
    NOTES=${2:?"passe as notas: release.sh --publish \"O que mudou\""}
    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
        echo "A release $TAG já existe. Suba a versão no Info.plist." >&2
        exit 1
    fi
fi
command -v create-dmg >/dev/null || { echo "create-dmg não encontrado: brew install create-dmg" >&2; exit 1; }

"$PACKAGING/build.sh"

# ZIP for install.sh: ditto keeps the attributes and the signature.
rm -f "$DIST/Cadex.zip" "$DIST/Cadex.zip.sha256"
(cd "$DIST" && ditto -c -k --keepParent Cadex.app Cadex.zip && shasum -a 256 Cadex.zip > Cadex.zip.sha256)
cp "$PACKAGING/install.sh" "$DIST/install.sh"

# Drag-to-Applications image. The positions match dmg-background.swift.
STAGE="$(mktemp -d)"
cp -R "$DIST/Cadex.app" "$STAGE/"
rm -f "$DIST/Cadex.dmg"
PLAIN=()
[[ "${CADEX_DMG_PLAIN:-}" == "1" ]] && PLAIN=(--skip-jenkins)
create-dmg ${PLAIN[@]+"${PLAIN[@]}"} \
    --volname "Cadex" \
    --volicon "$DIST/Cadex.app/Contents/Resources/AppIcon.icns" \
    --background "$PACKAGING/dmg-background.tiff" \
    --window-size 660 400 \
    --icon-size 112 \
    --icon "Cadex.app" 180 190 \
    --hide-extension "Cadex.app" \
    --app-drop-link 480 190 \
    "$DIST/Cadex.dmg" "$STAGE" >/dev/null
rm -rf "$STAGE"

echo "dist/: $(cd "$DIST" && ls -1 Cadex.dmg Cadex.zip Cadex.zip.sha256 install.sh | tr '\n' ' ')"
du -h "$DIST/Cadex.dmg" "$DIST/Cadex.zip"

if [[ "$PUBLISH" == "1" ]]; then
    gh release create "$TAG" -R "$REPO" --latest --title "Cadex $VERSION" --notes "$NOTES" \
        "$DIST/Cadex.dmg" "$DIST/Cadex.zip" "$DIST/Cadex.zip.sha256" "$DIST/install.sh"
    echo "Publicada: https://github.com/$REPO/releases/tag/$TAG"
fi
