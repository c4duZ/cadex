.PHONY: check manifests core core-test macos-test app run relink package windows-core windows-core-test

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
		&& swift build --product EditorTests && swift build --product MarkdownTests \
		&& swift build --product MediaPreviewTests && swift build --product PreviewTests \
		&& swift build --product SourceControlTests \
		&& swift build --product GitHistoryTests && swift build --product SpacesTests
	@cd apps/macos && .build/debug/TerminalTests && .build/debug/CommandPaletteTests && .build/debug/ShortcutsTests \
		&& .build/debug/TabsTests && .build/debug/StatusBarTests && .build/debug/IconsTests \
		&& .build/debug/ThemesTests && .build/debug/SettingsTests \
		&& .build/debug/ExplorerTests && .build/debug/SearchTests && .build/debug/EditorTests && .build/debug/MarkdownTests && .build/debug/MediaPreviewTests && .build/debug/PreviewTests && .build/debug/SourceControlTests && .build/debug/GitHistoryTests \
		&& .build/debug/SpacesTests

# Debug build of the app; `make run` opens it.
app: core relink
	@cd apps/macos && swift build

run: app
	@cd apps/macos && swift run Cadex

# dist/Cadex.app, universal and signed ad hoc (apps/macos/packaging/build.sh).
package:
	@apps/macos/packaging/build.sh

# libcadex.a for Windows 11, x64 and arm64, cross-compiled from this Mac
# (docs/plans/9-windows-core.md). Each lands in core/zig-out/windows-<arch>.
windows-core:
	@cd core && for arch in x86_64 aarch64; do \
		zig build -Doptimize=ReleaseFast -Dtarget=$$arch-windows.win11_zn-gnu --prefix zig-out/windows-$$arch || exit 1; \
	done

# The core tests on Windows 11 arm64, run in the UTM VM over ssh
# (tools/windows-vm.sh; CADEX_VM names the ssh host).
windows-core-test:
	@cd core && zig build test-bin -Dtarget=aarch64-windows.win11_zn-gnu
	@tools/windows-vm.sh core/zig-out/bin/cadex-core-tests.exe
