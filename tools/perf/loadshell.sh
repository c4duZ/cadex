#!/bin/zsh
# The "shell" of a perf scenario (tools/perf/run.py passes it as $SHELL):
# runs the load named in $CADEX_LOAD for $CADEX_LOAD_SECONDS, then a zsh
# with no startup files, so each scenario starts the same way.
run_for() { "$@" & local p=$!; sleep $DUR; kill $p 2>/dev/null; wait $p 2>/dev/null; }
DUR=${CADEX_LOAD_SECONDS:-20}
case "$CADEX_LOAD" in
  flood) run_for yes "Cadex load test: a line of plain text that keeps coming 0123456789" ;;
  color) run_for perl -e 'while(1){for $i (0..255){print "\e[38;5;${i}m\e[48;5;".(255-$i)."m".("█▓▒░ é 😀 中文 " x 6)."\e[0m\n"}}' ;;
  tui)   run_for perl -e '$|=1; while(1){print "\e[H\e[2J"; for $r (1..60){printf "\e[%d;1H\e[3%dm%s", $r, $r%8, join("", map {chr(65+int(rand(26)))} 1..200)} select(undef,undef,undef,0.005)}' ;;
  *) ;;
esac
exec /bin/zsh -f -i
