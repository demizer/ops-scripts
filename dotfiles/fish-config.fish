# INSPIRATION
# https://github.com/craftzdog/dotfiles-public (inkdrop dev)

set fish_greeting ""

# aliases
alias ls "ls -p -G"
alias la "ls -A"
alias ll "ls -l"
alias lla "ll -A"
# alias g git
command -qv nvim && alias vim nvim

set -Ux EDITOR nvim

fish_add_path ~/bin
fish_add_path ~/dotfiles/bin
fish_add_path ~/.local/bin
fish_add_path ~/.cargo/bin
fish_add_path ~/src/lua/lua-language-server/bin

set -Ux GOPATH $HOME

switch (uname)
  case Darwin
    # Do nothing
  case Linux
    source (dirname (status --current-filename))/config-linux.fish
  case '*'
    # Do nothing
end

# shell history sync
atuin init fish | source

# opam configuration
# source /home/$user/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# Created by `userpath` on 2024-05-05 17:08:24
#fish_add_path /home/jesusa/.local/share/hatch/pythons/3.10/python/bin

# Created by `userpath` on 2024-05-03 21:59:32
#fish_add_path /home/jesusa/.local/share/hatch/pythons/3.11/python/bin

# Created by `userpath` on 2024-05-05 17:37:27
#fish_add_path /home/jesusa/.local/share/hatch/pythons/3.12/python/bin
