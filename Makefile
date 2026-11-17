.PHONY: check manifests core core-test memory memory-test memory-upstream-test memory-eval macos-test app run relink package perf windows-core windows-core-test windows-app windows-run windows-app-test windows-package

# Run before handing work over: manifests, core tests, the memory engine's
# tests, app tests, and the Windows build (it cannot run here, but it must keep
# compiling).
check: manifests core-test memory-test macos-test windows-app

manifests:
	@python3 tools/check_manifests.py
	@python3 -I tools/icons/windows_icons.py --check
	@python3 -I tools/check_command_parity.py
	@python3 -I tools/check_design_tokens.py
	@python3 -I tools/design/build_tokens.py --check
	@python3 -I tools/check_design_literals.py --self-test
	@python3 -I tools/check_design_literals.py
	@python3 -I tools/check_leftovers.py --self-test
	@python3 -I tools/check_leftovers.py
	@python3 -I tools/icons/windows_file_icons.py --check
	@# Warns (never fails) when the installed claude has words cadex claude does not know.
	@python3 -I core/features/agent-tools/claude_args_check.py

# libcadex.a + cadex.h in core/zig-out, which the macOS app links.
core:
	@cd core && zig build -Doptimize=ReleaseFast

core-test:
	@cd core && zig build test

# The memory engine, cadex-memory (core/features/memory, docs/adr/0028-project-memory.md):
# Rust, upstream crates pinned by commit in its Cargo.toml and Cargo.lock.
CARGO ?= $(HOME)/.cargo/bin/cargo
MEMORY = core/features/memory/server

# Release, both architectures (the package joins them with lipo).
memory:
	@cd $(MEMORY) && $(CARGO) build --release --locked --target aarch64-apple-darwin \
		&& $(CARGO) build --release --locked --target x86_64-apple-darwin

# Cadex's own crate and the end-to-end check of the engine, in seconds. The
# upstream crates' suite (16 min on 12 cores) is memory-upstream-test.
memory-test:
	@cd $(MEMORY) && $(CARGO) test --locked --quiet

# Upstream's tests for the crates the engine uses, on the PC (the `pc` ssh host
# of roda-no-pc, Linux x86_64), at the pinned commit; run at every upstream
# update. The script goes by ssh with only the commit: no copy of this folder.
MEMORY_REV = $(shell grep -m1 -o 'rev = "[0-9a-f]\{40\}"' $(MEMORY)/Cargo.toml | grep -o '[0-9a-f]\{40\}')
# The search measured (plan 22 phase D): the ADRs and specs as pages, 30
# questions, text only against hybrid; needs the release engine and the model
# folder (MODELS=<dir with all-MiniLM-L6-v2/>). Not in check: it downloads nothing
# but takes the 87 MB model from the caller.
memory-eval:
	@python3 tools/memory_eval.py $(MEMORY)/target/aarch64-apple-darwin/release/cadex-memory $(MODELS)

memory-upstream-test:
	@ssh $${RODA_NO_PC_HOST:-pc} 'bash -s' -- $(MEMORY_REV) < core/features/memory/upstream_test.sh

# swift build does not notice a new libcadex.a: drop the linked binaries so
# they link again (tests ran against an old core, 2026-10-19).
relink:
	@cd apps/macos && rm -f .build/debug/Cadex .build/debug/*Tests

macos-test: core relink
	@cd apps/macos && swift build --product TerminalTests && swift build --product CommandPaletteTests \
		&& swift build --product ShortcutsTests && swift build --product TabsTests \
		&& swift build --product StatusBarTests && swift build --product SidebarTests && swift build --product InspectorTests && swift build --product CustomizeTests && swift build --product AgentsTests && swift build --product SSHTests && swift build --product MachinesTests && swift build --product OrchestrationTests && swift build --product IconsTests \
		&& swift build --product ThemesTests && swift build --product SettingsTests \
		&& swift build --product ExplorerTests && swift build --product SearchTests \
		&& swift build --product EditorTests && swift build --product MarkdownTests \
		&& swift build --product MediaPreviewTests && swift build --product PreviewTests \
		&& swift build --product SourceControlTests \
		&& swift build --product GitHistoryTests && swift build --product SpacesTests \
		&& swift build --product MenusTests && swift build --product PowerTests && swift build --product StringsTests \
		&& swift build --product UpdatesTests && swift build --product UILooksTests && swift build --product StateGlyphTests \
		&& swift build --product TempImagesTests && swift build --product SessionKitTests && swift build --product TextIndexTests && swift build --product AgentToolsTests && swift build --product WorktreesTests \
		&& swift build --product ComputerUseTests && swift build --product ReviewTests && swift build --product MemoryTests
	@cd apps/macos && .build/debug/TerminalTests && .build/debug/CommandPaletteTests && .build/debug/ShortcutsTests \
		&& .build/debug/TabsTests && .build/debug/StatusBarTests && .build/debug/SidebarTests && .build/debug/InspectorTests && .build/debug/CustomizeTests && .build/debug/AgentsTests && .build/debug/SSHTests && .build/debug/MachinesTests && .build/debug/OrchestrationTests && .build/debug/IconsTests \
		&& .build/debug/ThemesTests && .build/debug/SettingsTests \
		&& .build/debug/ExplorerTests && .build/debug/SearchTests && .build/debug/EditorTests && .build/debug/MarkdownTests && .build/debug/MediaPreviewTests && .build/debug/PreviewTests && .build/debug/SourceControlTests && .build/debug/GitHistoryTests \
		&& .build/debug/SpacesTests && .build/debug/MenusTests && .build/debug/PowerTests && .build/debug/StringsTests && .build/debug/UpdatesTests && .build/debug/UILooksTests && .build/debug/StateGlyphTests && .build/debug/TempImagesTests && .build/debug/SessionKitTests && .build/debug/TextIndexTests && .build/debug/AgentToolsTests && .build/debug/WorktreesTests \
		&& .build/debug/ComputerUseTests && .build/debug/ReviewTests && .build/debug/MemoryTests

# Debug build of the app; `make run` opens it.
app: core relink
	@cd $(MEMORY) && $(CARGO) build --locked --quiet && target/debug/cadex-memory export-plugin target/memory-plugin
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
