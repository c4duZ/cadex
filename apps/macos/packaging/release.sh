#!/bin/bash
# Makes a Cadex release (docs/plans/7-mvp-release.md, fase C): Cadex.app,
# Cadex.zip with its checksum, Cadex.dmg and install.sh in dist/, plus the
# Windows zips and install.ps1 (docs/plans/13-windows-release.md), with names
# without the version, so releases/latest/download/... always gets the last.
#
#   apps/macos/packaging/release.sh                         # only builds dist/
#   apps/macos/packaging/release.sh --publish "O que mudou"  # and publishes on GitHub
#
# Before publishing, raise CFBundleShortVersionString and CFBundleVersion in
# Info.plist. latest.json, which the app reads to update itself, is signed
# with the Keychain item cadex-update-signing (docs/adr/0016-in-app-updates.md):
# without it a release does not publish. Needs create-dmg (brew) and gh logged in to the account that
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
HAS_UPDATE_KEY=0
security find-generic-password -s cadex-update-signing -a cadex >/dev/null 2>&1 && HAS_UPDATE_KEY=1
if [[ "$PUBLISH" == "1" && "$HAS_UPDATE_KEY" == "0" ]]; then
    echo "Chave de atualização não encontrada no Keychain (cadex-update-signing): ver docs/adr/0016-in-app-updates.md" >&2
    exit 1
fi

"$PACKAGING/build.sh"

# ZIP for install.sh: ditto keeps the attributes and the signature.
rm -f "$DIST/Cadex.zip" "$DIST/Cadex.zip.sha256"
(cd "$DIST" && ditto -c -k --keepParent Cadex.app Cadex.zip && shasum -a 256 Cadex.zip > Cadex.zip.sha256)
cp "$PACKAGING/install.sh" "$DIST/install.sh"

# latest.json for the in-app updater: this version's zip (not "latest", so
# the file signed is the file downloaded), its checksum and signature.
rm -f "$DIST/latest.json"
if [[ "$HAS_UPDATE_KEY" == "1" ]]; then
    security find-generic-password -s cadex-update-signing -a cadex -w \
        | swift "$PACKAGING/sign-update.swift" manifest "$DIST/Cadex.zip" "$VERSION" \
            "https://github.com/$REPO/releases/download/$TAG/Cadex.zip" "$NOTES" > "$DIST/latest.json"
else
    echo "Sem a chave cadex-update-signing: dist/ sai sem latest.json" >&2
fi

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

# The Windows app rides the same release, with the same version
# (apps/windows/packaging/build.sh), once CADEX_WINDOWS=1 says so: until it
# has run on a Windows machine (plan 13), a Mac release does not carry it.
WINDOWS=()
if [[ "${CADEX_WINDOWS:-}" == "1" ]]; then
    "$ROOT/apps/windows/packaging/build.sh"
    WINDOWS=("$DIST"/Cadex-windows-x64.zip "$DIST"/Cadex-windows-x64.zip.sha256 "$DIST"/Cadex-windows-arm64.zip "$DIST"/Cadex-windows-arm64.zip.sha256 "$DIST/install.ps1")
fi

echo "dist/: $(cd "$DIST" && ls -1 Cadex.dmg Cadex.zip Cadex.zip.sha256 install.sh latest.json 2>/dev/null | tr '\n' ' ')"
du -h "$DIST/Cadex.dmg" "$DIST/Cadex.zip"

if [[ "$PUBLISH" == "1" ]]; then
    gh release create "$TAG" -R "$REPO" --latest --title "Cadex $VERSION" --notes "$NOTES" \
        "$DIST/Cadex.dmg" "$DIST/Cadex.zip" "$DIST/Cadex.zip.sha256" "$DIST/install.sh" "$DIST/latest.json" ${WINDOWS[@]+"${WINDOWS[@]}"}
    echo "Publicada: https://github.com/$REPO/releases/tag/$TAG"
fi
