#!/bin/sh
# Runs a Windows program in the test VM over ssh (docs/plans/9-windows-core.md,
# phase A): copies it to %USERPROFILE%\cadex-tests and runs it there, so the
# tests' .zig-cache\tmp folders land in that folder too.
#
#   tools/windows-vm.sh <file.exe> [args...]
#
# CADEX_VM is the ssh host of the VM (default: cadex-vm, set in ~/.ssh/config).
set -eu
vm="${CADEX_VM:-cadex-vm}"
exe="$1"
shift
name=$(basename "$exe")
ssh "$vm" "if not exist cadex-tests mkdir cadex-tests"
scp -q "$exe" "$vm:cadex-tests/$name"
ssh "$vm" "cd cadex-tests && $name $*"
