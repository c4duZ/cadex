.PHONY: check manifests core-test macos-test

# Run before handing work over: manifests, core tests, app tests.
check: manifests core-test macos-test

manifests:
	@python3 tools/check_manifests.py

# The core and the app have no code yet; each target starts running its tests
# as soon as the build file exists, so nobody has to remember to wire it up.
core-test:
	@if [ -f core/build.zig ]; then cd core && zig build test; \
	else echo "core: sem código ainda"; fi

macos-test:
	@if [ -f apps/macos/Package.swift ]; then cd apps/macos && swift test; \
	else echo "apps/macos: sem código ainda"; fi
