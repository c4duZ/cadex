#!/bin/bash
# Makes the Windows release files (docs/plans/13-windows-release.md, fase B):
# Cadex.exe for x64 and arm64, each zipped with LICENSE and NOTICE, and the
# checksums, in dist/ at the repository root, with names without the version
# so releases/latest/download/... always gets the last:
#
#   dist/Cadex-windows-x64.zip   dist/Cadex-windows-x64.zip.sha256
#   dist/Cadex-windows-arm64.zip dist/Cadex-windows-arm64.zip.sha256
#   dist/install.ps1
#
# The version is the Mac's (apps/macos/packaging/Info.plist), so one release
# carries both apps with one number.
set -euo pipefail
PACKAGING="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$PACKAGING/.." && pwd)"
ROOT="$(cd "$APP/../.." && pwd)"
DIST="$ROOT/dist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/apps/macos/packaging/Info.plist")

mkdir -p "$DIST"
for pair in x86_64:x64 aarch64:arm64; do
    arch=${pair%%:*}
    name=${pair##*:}
    (cd "$ROOT/core" && zig build -Doptimize=ReleaseFast -Dtarget=$arch-windows.win11_zn-gnu --prefix zig-out/windows-$arch)
    out="$APP/zig-out/release-$name"
    rm -rf "$out"
    (cd "$APP" && zig build -Doptimize=ReleaseSmall -Dtarget=$arch-windows.win11_zn-gnu -Dversion="$VERSION" --prefix "$out")
    stage="$(mktemp -d)/Cadex"
    mkdir -p "$stage"
    # The app and whatever DLL it ships with; the tests stay out.
    cp "$out/bin/Cadex.exe" "$stage/"
    find "$out/bin" -maxdepth 1 -name '*.dll' -exec cp {} "$stage/" \;
    cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$stage/"
    zip="$DIST/Cadex-windows-$name.zip"
    rm -f "$zip" "$zip.sha256"
    (cd "$(dirname "$stage")" && zip -qr -X "$zip" Cadex)
    rm -rf "$(dirname "$stage")"
    (cd "$DIST" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
done
cp "$PACKAGING/install.ps1" "$DIST/install.ps1"

echo "dist/ (Cadex $VERSION para Windows):"
(cd "$DIST" && ls -1 Cadex-windows-* install.ps1 && du -h Cadex-windows-*.zip)
