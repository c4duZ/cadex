#!/bin/bash
# Upstream ai-memory's own tests for the crates cadex-memory uses, at the commit
# pinned in server/Cargo.toml (`make memory-upstream-test`, docs/adr/0028-project-memory.md).
# Meant for the PC (Linux x86_64, 12 cores; the `pc` host of roda-no-pc): ~16 min,
# too slow for `make check` (measured 2026-11-15: 4,804 tests, 15 min 54 s).
# The Makefile sends this script over ssh with the commit as $1: mirroring the
# Cadex folder with roda-no-pc copied 4.8 GB of build folders and filled the
# PC's disk (2026-11-15). Run here without $1, it reads server/Cargo.toml.
# The checkout lives in ~/ai-memory-upstream and is reused.
set -euo pipefail
REV="${1:-}"
if [ -z "$REV" ]; then
    HERE="$(cd "$(dirname "$0")" && pwd)"
    REV=$(grep -m1 -o 'rev = "[0-9a-f]\{40\}"' "$HERE/server/Cargo.toml" | grep -o '[0-9a-f]\{40\}')
fi
[ -n "$REV" ] || { echo "no pinned ai-memory rev"; exit 2; }
export PATH="$HOME/.cargo/bin:$PATH"
command -v cargo >/dev/null || {
    echo "Rust is missing here; install it once with:"
    echo "  curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal"
    exit 2
}
SRC="$HOME/ai-memory-upstream"
[ -d "$SRC/.git" ] || git clone -q https://github.com/akitaonrails/ai-memory "$SRC"
git -C "$SRC" fetch -q origin "$REV" 2>/dev/null || git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --detach "$REV"
echo "ai-memory at $(git -C "$SRC" log -1 --format='%h %s')"
cd "$SRC"
# The test build is several GB; the PC's disk is shared with other projects
# (it filled up on 2026-11-15). Rebuilding costs ~2 min.
trap 'rm -rf "$SRC/target"' EXIT
time cargo test --locked --quiet \
    -p ai-memory-core -p ai-memory-store -p ai-memory-wiki -p ai-memory-consolidate \
    -p ai-memory-hooks -p ai-memory-mcp -p ai-memory-llm -p ai-memory-workstream
