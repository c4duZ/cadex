# Cadex's zsh integration (docs/spec/terminal.md, plan 22 phase C). The
# terminal starts zsh with ZDOTDIR set to this folder (core shell_env.zig)
# because a tab's PATH cannot carry Cadex's `claude`: the login shell's
# path_helper and the owner's .zshrc reorder it (2026-11-15). This file
# gives the owner's ZDOTDIR back, defines `claude`, and reads the owner's
# own .zshenv; zsh then reads .zprofile, .zshrc and .zlogin from the
# owner's folder as always. It never prints and never fails the start.

# The owner's ZDOTDIR, or none (zsh then reads $HOME); nested shells see
# the owner's setup only.
if [[ -n "${CADEX_USER_ZDOTDIR+set}" ]]; then
  ZDOTDIR="$CADEX_USER_ZDOTDIR"
  builtin unset CADEX_USER_ZDOTDIR
else
  builtin unset ZDOTDIR
fi

# The typed `claude` gets the session kit through `cadex claude`, which
# runs the real one unchanged when it should not (print mode, subcommands,
# no app). Defined before the owner's files: an alias or function of the
# owner's named claude wins.
claude() {
  if [[ -n "$CADEX_TOOLS" && -x "$CADEX_TOOLS" ]]; then
    "$CADEX_TOOLS" claude "$@"
  else
    command claude "$@"
  fi
}

# The owner's .zshenv, read as zsh would have read it.
if [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
  builtin source "${ZDOTDIR:-$HOME}/.zshenv"
fi
