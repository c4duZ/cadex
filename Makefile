.PHONY: check manifests core core-test macos-test app run

# Run before handing work over: manifests, core tests, app tests.
check: manifests core-test macos-test

manifests:
	@python3 tools/check_manifests.py

# libcadex.a + cadex.h in core/zig-out, which the macOS app links.
core:
	@cd core && zig build -Doptimize=ReleaseFast

core-test:
	@cd core && zig build test

macos-test: core
	@cd apps/macos && swift build --product TerminalTests && swift build --product CommandPaletteTests \
		&& swift build --product ShortcutsTests && swift build --product TabsTests \
		&& swift build --product StatusBarTests && swift build --product IconsTests \
		&& swift build --product ThemesTests && swift build --product SettingsTests \
		&& swift build --product ExplorerTests
	@cd apps/macos && .build/debug/TerminalTests && .build/debug/CommandPaletteTests && .build/debug/ShortcutsTests \
		&& .build/debug/TabsTests && .build/debug/StatusBarTests && .build/debug/IconsTests \
		&& .build/debug/ThemesTests && .build/debug/SettingsTests \
		&& .build/debug/ExplorerTests

# Debug build of the app; `make run` opens it.
app: core
	@cd apps/macos && swift build

run: app
	@cd apps/macos && swift run Cadex
