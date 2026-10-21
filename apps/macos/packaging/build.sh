#!/bin/bash
# Builds dist/Cadex.app at the repository root: universal (Apple Silicon and
# Intel), macOS 13+, signed ad hoc with the identity pinned to the bundle id.
# Needs only the Command Line Tools and Zig 0.16 (docs/adr/0007-one-step-install.md).
#
#   apps/macos/packaging/build.sh
set -euo pipefail
PACKAGING="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PACKAGING/../../.." && pwd)"
MACOS="$ROOT/apps/macos"
ZIG="${ZIG:-$HOME/.local/bin/zig}"
DIST="$ROOT/dist"
APP="$DIST/Cadex.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PACKAGING/Info.plist")

# The core for each architecture, joined into one fat libcadex.a where
# Package.swift links it: each Swift build takes its own slice.
for arch in aarch64 x86_64; do
    (cd "$ROOT/core" && "$ZIG" build -Doptimize=ReleaseFast -Dtarget="$arch-macos.13.0" --prefix "$DIST/core-$arch")
done
mkdir -p "$ROOT/core/zig-out/lib"
lipo -create "$DIST/core-aarch64/lib/libcadex.a" "$DIST/core-x86_64/lib/libcadex.a" \
    -output "$ROOT/core/zig-out/lib/libcadex.a"

# Swift per triple, joined with lipo: `swift build --arch arm64 --arch x86_64`
# needs the full Xcode. swift build does not relink when only libcadex.a
# changed, so the old executables go first (Makefile, relink).
SLICES=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx13.0"
    bin="$(cd "$MACOS" && swift build -c release --triple "$triple" --show-bin-path)"
    rm -f "$bin/Cadex"
    (cd "$MACOS" && swift build -c release --product Cadex --triple "$triple")
    SLICES+=("$bin/Cadex")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/Cadex"
# Local symbols only serve a debugger: about 3 MB less (2026-10-19).
strip -x "$APP/Contents/MacOS/Cadex"
cp "$PACKAGING/Info.plist" "$APP/Contents/Info.plist"
# Resources the code finds in the main bundle (Icon.swift, ThemeCatalog.swift):
# SwiftPM's own resource bundles would have to sit in the app's root folder.
cp "$MACOS/shared/icons/Resources/Phosphor-Regular.ttf" "$APP/Contents/Resources/"
cp "$MACOS/shared/icons/Resources/Phosphor-Fill.ttf" "$APP/Contents/Resources/"
cp "$MACOS/features/themes/Resources/catalog.json" "$APP/Contents/Resources/"
cp -R "$MACOS/shared/icons/Resources/FileIcons" "$APP/Contents/Resources/"
cp -R "$MACOS/shared/icons/Resources/ProviderLogos" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/"

# The icon in every size macOS asks for, from the large PNG.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ROOT/docs/cadex-icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ROOT/docs/cadex-icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad hoc, but with the designated requirement on the bundle id: the default
# ad hoc identity is the cdhash, and macOS would forget the permissions given
# to Cadex (folders, automation) at every new build.
codesign --force --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Cadex"))"
