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

# The command each prompt runs, for the tab's name and the pane's header (plan 29's review
# against the mockups): OSC 133 C with the line URL-encoded byte by byte when it starts, and D
# with the exit code when the prompt comes back. Only in an interactive shell; registered with
# add-zsh-hook, so the owner's own hooks run as before.
if [[ -o interactive ]]; then
  _cadex_command_start() {
    builtin emulate -L zsh -o extended_glob -o no_multibyte
    local line=$1 encoded=""
    encoded=${line//(#m)[^A-Za-z0-9._~\/-]/%${(l:2::0:)$(( [##16] #MATCH ))}}
    builtin print -rn -- $'\e]133;C;cmdline_url='"$encoded"$'\a'
    _cadex_command_running=1
  }
  _cadex_command_end() {
    local code=$?
    [[ -n $_cadex_command_running ]] || return 0
    builtin print -rn -- $'\e]133;D;'"$code"$'\a'
    _cadex_command_running=
  }
  # Where the prompt ends and the typing starts (OSC 133 B), so ⌘A, the triple click and Delete
  # take just what is typed (2026-11-18). Kept last among the precmd hooks: a theme that builds
  # its prompt in its own hook would drop the mark.
  _cadex_prompt_end() {
    precmd_functions=(${precmd_functions:#_cadex_prompt_end} _cadex_prompt_end)
    [[ $PS1 == *$'\e]133;B\a'* ]] || PS1+=$'%{\e]133;B\a%}'
  }
  builtin autoload -Uz add-zsh-hook
  add-zsh-hook preexec _cadex_command_start
  add-zsh-hook precmd _cadex_command_end
  add-zsh-hook precmd _cadex_prompt_end
fi
