.PHONY: check manifests core core-test macos-test app run relink

# Run before handing work over: manifests, core tests, app tests.
check: manifests core-test macos-test

manifests:
	@python3 tools/check_manifests.py

# libcadex.a + cadex.h in core/zig-out, which the macOS app links.
core:
	@cd core && zig build -Doptimize=ReleaseFast

core-test:
	@cd core && zig build test

# swift build does not notice a new libcadex.a: drop the linked binaries so
# they link again (tests ran against an old core, 2026-10-19).
relink:
	@cd apps/macos && rm -f .build/debug/Cadex .build/debug/*Tests

macos-test: core relink
	@cd apps/macos && swift build --product TerminalTests && swift build --product CommandPaletteTests \
		&& swift build --product ShortcutsTests && swift build --product TabsTests \
		&& swift build --product StatusBarTests && swift build --product IconsTests \
		&& swift build --product ThemesTests && swift build --product SettingsTests \
		&& swift build --product ExplorerTests && swift build --product SearchTests \
		&& swift build --product EditorTests
	@cd apps/macos && .build/debug/TerminalTests && .build/debug/CommandPaletteTests && .build/debug/ShortcutsTests \
		&& .build/debug/TabsTests && .build/debug/StatusBarTests && .build/debug/IconsTests \
		&& .build/debug/ThemesTests && .build/debug/SettingsTests \
		&& .build/debug/ExplorerTests && .build/debug/SearchTests && .build/debug/EditorTests

# Debug build of the app; `make run` opens it.
app: core relink
	@cd apps/macos && swift build

run: app
	@cd apps/macos && swift run Cadex
