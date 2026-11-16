#!/bin/bash
# Builds dist/Cadex.app at the repository root: universal (Apple Silicon and
# Intel), macOS 13+, signed ad hoc with the identity pinned to the bundle id.
# Needs the Command Line Tools, Zig 0.16 and, for the memory engine, Rust by
# rustup (docs/adr/0028-project-memory.md); whoever installs gets binaries only
# (docs/adr/0007-one-step-install.md).
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
# The `cadex` program the agent sessions Cadex opens run (core/features/agent-tools):
# Contents/Helpers, since Contents/MacOS/cadex would clash with Cadex on a
# case-insensitive disk. Signed first: the app's signature seals it.
mkdir -p "$APP/Contents/Helpers"
lipo -create "$DIST/core-aarch64/bin/cadex" "$DIST/core-x86_64/bin/cadex" -output "$APP/Contents/Helpers/cadex"
strip -x "$APP/Contents/Helpers/cadex"
codesign --force --sign - -i "$BUNDLE_ID.cadex" "$APP/Contents/Helpers/cadex"
# Each slice must run after lipo, strip and the signature: the x86_64 one once
# crashed after codesign (exit 139, 2026-11-14; core/build.zig, headerpad).
SMOKE="$(mktemp -d)"
for slice in arm64 x86_64; do
    if ! arch -"$slice" /usr/bin/true 2>/dev/null; then echo "skip: no $slice runtime (Rosetta) to test cadex"; continue; fi
    echo '{"session_id":"smoke","rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1}}}' \
        | CLAUDE_CONFIG_DIR="$SMOKE/none" CADEX_USAGE_DIR="$SMOKE/$slice" arch -"$slice" "$APP/Contents/Helpers/cadex" statusline >/dev/null \
        && [ -f "$SMOKE/$slice/sessions/smoke.json" ] || { echo "cadex ($slice) failed in the bundle"; exit 1; }
done
# The terminal daemon (terminal.keepSessions, core/features/terminal): the same
# signing and check; a second one on the same socket must find the first.
lipo -create "$DIST/core-aarch64/bin/cadex-terminald" "$DIST/core-x86_64/bin/cadex-terminald" \
    -output "$APP/Contents/Helpers/cadex-terminald"
strip -x "$APP/Contents/Helpers/cadex-terminald"
codesign --force --sign - -i "$BUNDLE_ID.terminald" "$APP/Contents/Helpers/cadex-terminald"
for slice in arm64 x86_64; do
    if ! arch -"$slice" /usr/bin/true 2>/dev/null; then echo "skip: no $slice runtime (Rosetta) to test cadex-terminald"; continue; fi
    arch -"$slice" "$APP/Contents/Helpers/cadex-terminald" --socket "$SMOKE/$slice.sock" & daemon=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SMOKE/$slice.sock" ] && break; sleep 0.2; done
    [ -S "$SMOKE/$slice.sock" ] && arch -"$slice" "$APP/Contents/Helpers/cadex-terminald" --socket "$SMOKE/$slice.sock" \
        || { kill $daemon 2>/dev/null; echo "cadex-terminald ($slice) failed in the bundle"; exit 1; }
    kill $daemon; wait $daemon 2>/dev/null || true
done
# The memory engine (core/features/memory, docs/adr/0028-project-memory.md):
# Rust, built for size per architecture, joined like the others. Each slice
# must answer on its socket, and no LLM provider may be compiled in: Cadex
# runs no model of its own (the fat LTO drops them; 2026-11-15).
CARGO="${CARGO:-$HOME/.cargo/bin/cargo}"
MEMORY="$ROOT/core/features/memory/server"
for target in aarch64-apple-darwin x86_64-apple-darwin; do
    (cd "$MEMORY" && "$CARGO" build --release --locked --target "$target")
done
lipo -create "$MEMORY/target/aarch64-apple-darwin/release/cadex-memory" \
    "$MEMORY/target/x86_64-apple-darwin/release/cadex-memory" -output "$APP/Contents/Helpers/cadex-memory"
codesign --force --sign - -i "$BUNDLE_ID.memory" "$APP/Contents/Helpers/cadex-memory"
if strings "$APP/Contents/Helpers/cadex-memory" | grep -E -q \
    'api\.anthropic\.com|api\.openai\.com|generativelanguage\.googleapis\.com|api\.voyageai\.com|api\.githubcopilot\.com'; then
    echo "cadex-memory carries an LLM provider endpoint"; exit 1
fi
for slice in arm64 x86_64; do
    if ! arch -"$slice" /usr/bin/true 2>/dev/null; then echo "skip: no $slice runtime (Rosetta) to test cadex-memory"; continue; fi
    arch -"$slice" "$APP/Contents/Helpers/cadex-memory" --socket "$SMOKE/m-$slice.sock" \
        --data-dir "$SMOKE/memory-$slice" --no-embeddings 2>/dev/null & engine=$!
    ok=""
    for _ in $(seq 1 50); do
        [ "$(curl -s --unix-socket "$SMOKE/m-$slice.sock" http://localhost/healthz 2>/dev/null)" = ok ] && { ok=1; break; }
        sleep 0.2
    done
    kill $engine 2>/dev/null; wait $engine 2>/dev/null || true
    [ -n "$ok" ] || { echo "cadex-memory ($slice) failed in the bundle"; exit 1; }
done
rm -rf "$SMOKE"
# Resources the code finds in the main bundle (Icon.swift, ThemeCatalog.swift):
# SwiftPM's own resource bundles would have to sit in the app's root folder.
cp "$MACOS/shared/icons/Resources/Phosphor-Regular.ttf" "$APP/Contents/Resources/"
cp "$MACOS/shared/icons/Resources/Phosphor-Fill.ttf" "$APP/Contents/Resources/"
cp "$MACOS/features/themes/Resources/catalog.json" "$APP/Contents/Resources/"
cp -R "$MACOS/shared/icons/Resources/FileIcons" "$APP/Contents/Resources/"
cp -R "$MACOS/shared/icons/Resources/ProviderLogos" "$APP/Contents/Resources/"
# The skills plugin the session kit passes by --plugin-dir (plan 20, ADR 0024).
cp -R "$MACOS/features/agent-tools/plugin" "$APP/Contents/Resources/agent-plugin"
# The zsh integration (docs/spec/terminal.md): the tabs' zsh starts from this
# ZDOTDIR; TerminalShellIntegration.swift finds it here.
mkdir -p "$APP/Contents/Resources/shell-integration"
cp -R "$MACOS/features/terminal/shell-integration/zsh" "$APP/Contents/Resources/shell-integration/zsh"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/"
# The licenses of the memory engine's Rust crates, from its Cargo.lock (NOTICE
# points here); a crate outside about.toml's accepted licenses fails the package.
CARGO_ABOUT="${CARGO_ABOUT:-$HOME/.cargo/bin/cargo-about}"
[ -x "$CARGO_ABOUT" ] || { echo "cargo-about is missing: cargo install --locked cargo-about --features cli"; exit 1; }
(cd "$MEMORY" && PATH="$(dirname "$CARGO"):$PATH" "$CARGO_ABOUT" generate --fail -c about.toml about.hbs) > "$APP/Contents/Resources/THIRD-PARTY-RUST.txt"

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
