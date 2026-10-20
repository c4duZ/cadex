#!/bin/sh
# Runs a Windows program in the test VM over ssh (docs/plans/9-windows-core.md,
# phase A): copies it to %USERPROFILE%\cadex-tests and runs it there, so the
# tests' .zig-cache\tmp folders land in that folder too.
#
#   tools/windows-vm.sh <file.exe> [args...]       runs it, output here
#   tools/windows-vm.sh --gui <file.exe>           opens it on the VM's desktop
#
# A program started by ssh lives in a session nobody sees, so --gui asks
# the Task Scheduler to start it in the signed-in user's session.
# CADEX_VM is the ssh host of the VM (default: cadex-vm, set in ~/.ssh/config).
set -eu
vm="${CADEX_VM:-cadex-vm}"
gui=0
if [ "${1:-}" = "--gui" ]; then
	gui=1
	shift
fi
exe="$1"
shift
name=$(basename "$exe")
ssh "$vm" "if not exist cadex-tests mkdir cadex-tests"
# A running copy keeps the file locked.
ssh "$vm" "taskkill /im $name /f >nul 2>&1 & exit 0"
scp -q "$exe" "$vm:cadex-tests/$name"
if [ "$gui" = 1 ]; then
	ssh "$vm" "schtasks /create /tn CadexRun /tr \"%USERPROFILE%\\cadex-tests\\$name\" /sc once /st 00:00 /it /f >nul && schtasks /run /tn CadexRun >nul"
else
	ssh "$vm" "cd cadex-tests && $name $*"
fi
