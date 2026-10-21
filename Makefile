.PHONY: check manifests core core-test macos-test app run relink package perf windows-core windows-core-test windows-app windows-run windows-app-test windows-package

# Run before handing work over: manifests, core tests, app tests, and the
# Windows build (it cannot run here, but it must keep compiling).
check: manifests core-test macos-test windows-app

manifests:
	@python3 tools/check_manifests.py
	@python3 -I tools/icons/windows_icons.py --check
	@python3 -I tools/check_command_parity.py
	@python3 -I tools/icons/windows_file_icons.py --check

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
		&& swift build --product StatusBarTests && swift build --product SidebarTests && swift build --product CustomizeTests && swift build --product AgentsTests && swift build --product IconsTests \
		&& swift build --product ThemesTests && swift build --product SettingsTests \
		&& swift build --product ExplorerTests && swift build --product SearchTests \
		&& swift build --product EditorTests && swift build --product MarkdownTests \
		&& swift build --product MediaPreviewTests && swift build --product PreviewTests \
		&& swift build --product SourceControlTests \
		&& swift build --product GitHistoryTests && swift build --product SpacesTests \
		&& swift build --product MenusTests && swift build --product PowerTests && swift build --product StringsTests \
		&& swift build --product UpdatesTests && swift build --product UILooksTests \
		&& swift build --product TempImagesTests
	@cd apps/macos && .build/debug/TerminalTests && .build/debug/CommandPaletteTests && .build/debug/ShortcutsTests \
		&& .build/debug/TabsTests && .build/debug/StatusBarTests && .build/debug/SidebarTests && .build/debug/CustomizeTests && .build/debug/AgentsTests && .build/debug/IconsTests \
		&& .build/debug/ThemesTests && .build/debug/SettingsTests \
		&& .build/debug/ExplorerTests && .build/debug/SearchTests && .build/debug/EditorTests && .build/debug/MarkdownTests && .build/debug/MediaPreviewTests && .build/debug/PreviewTests && .build/debug/SourceControlTests && .build/debug/GitHistoryTests \
		&& .build/debug/SpacesTests && .build/debug/MenusTests && .build/debug/PowerTests && .build/debug/StringsTests && .build/debug/UpdatesTests && .build/debug/UILooksTests && .build/debug/TempImagesTests

# Debug build of the app; `make run` opens it.
app: core relink
	@cd apps/macos && swift build

run: app
	@cd apps/macos && swift run Cadex

# The weight budget: the release app and the core's indexes through the
# situations that once made Cadex heavy; fails over a limit (tools/perf/run.py).
perf: package
	@python3 tools/perf/run.py

# dist/Cadex.app, universal and signed ad hoc (apps/macos/packaging/build.sh).
package:
	@apps/macos/packaging/build.sh

# libcadex.a for Windows 11, x64 and arm64, cross-compiled from this Mac
# (docs/plans/9-windows-core.md). Each lands in core/zig-out/windows-<arch>.
windows-core:
	@cd core && for arch in x86_64 aarch64; do \
		zig build -Doptimize=ReleaseFast -Dtarget=$$arch-windows.win11_zn-gnu --prefix zig-out/windows-$$arch || exit 1; \
	done

# The machine the Windows tests run on: the owner's PC, x64 (2026-10-20);
# WINDOWS_ARCH=aarch64 for an ARM one.
WINDOWS_ARCH ?= x86_64

# The core tests on that Windows, run over ssh (tools/windows-vm.sh;
# CADEX_VM names the ssh host).
windows-core-test:
	@cd core && zig build test-bin -Dtarget=$(WINDOWS_ARCH)-windows.win11_zn-gnu
	@tools/windows-vm.sh core/zig-out/bin/cadex-core-tests.exe

# Cadex.exe for Windows 11, x64 and arm64, in apps/windows/zig-out/<arch>
# (docs/plans/10-windows-terminal.md).
windows-app: windows-core
	@cd apps/windows && for arch in x86_64 aarch64; do \
		zig build -Dtarget=$$arch-windows.win11_zn-gnu --prefix zig-out/$$arch || exit 1; \
	done
	@cd apps/windows && zig build test-bin -Dtarget=$(WINDOWS_ARCH)-windows.win11_zn-gnu --prefix zig-out/$(WINDOWS_ARCH)

# Opens the build on the test machine's desktop.
windows-run: windows-app
	@tools/windows-vm.sh --gui apps/windows/zig-out/$(WINDOWS_ARCH)/bin/Cadex.exe

# The app's tests (one exe per module) on the test machine.
windows-app-test: windows-app
	@for t in apps/windows/zig-out/$(WINDOWS_ARCH)/bin/cadex-*-tests.exe; do tools/windows-vm.sh $$t || exit 1; done

# The Windows zips, their checksums and install.ps1 in dist/
# (apps/windows/packaging/CLAUDE.md).
windows-package:
	@apps/windows/packaging/build.sh
