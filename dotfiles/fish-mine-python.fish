# set -Ux PYTHON_KEYRING_BACKEND keyring.backends.null.Keyring
# set -Ux PYENV_ROOT $HOME/.pyenv

# fish_add_path $PYENV_ROOT/shims
# fish_add_path $PYENV_ROOT/bin

# source (pyenv init - | psub)
# source (pyenv virtualenv-init - | psub)

# status is-login; and pyenv init --path | source
# status is-interactive; and pyenv init - | source
# status is-interactive; and pyenv virtualenv-init - | source

# Autosource virtualenv; Workaround for nvim
# function nvimvenv
#   if test -e "$VIRTUAL_ENV"; and test -f "$VIRTUAL_ENV/bin/activate.fish"
#     source "$VIRTUAL_ENV/bin/activate.fish"
#     command nvim $argv # Run nvim program, ignore functions, builtins and aliases
#     deactivate # Must deactivate on exit, otherwise venv will still be sourced which may cause undesirable effects on your terminal.
#   else
#     command nvim $argv # Run nvim program, ignore functions, builtins and aliases
#   end
# end;
#
#
# alias nvim=nvimvenv
