# ~/.zshrc

# Terminal colors
export TERM=xterm-256color
export COLORTERM=truecolor

# Enable vim mode
bindkey -v
export KEYTIMEOUT=1  # Reduce ESC delay to 0.1s

# Better vim mode cursor shapes (beam in insert, block in normal)
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'  # Beam cursor
  fi
}
zle -N zle-keymap-select
echo -ne '\e[5 q'  # Start with beam cursor

# Better history
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY          # Share history between sessions
setopt HIST_IGNORE_DUPS       # Don't record duplicate entries
setopt HIST_IGNORE_SPACE      # Don't record commands starting with space
setopt HIST_REDUCE_BLANKS     # Remove extra blanks from history

# Better completion
autoload -Uz compinit && compinit
setopt COMPLETE_IN_WORD       # Complete from both ends of word
setopt ALWAYS_TO_END          # Move cursor to end after completion
setopt AUTO_MENU              # Show completion menu on tab
setopt AUTO_LIST              # List choices on ambiguous completion
zstyle ':completion:*' menu select  # Arrow key navigation in completion menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # Case-insensitive completion

# Useful aliases
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias grep='grep --color=auto'
alias psql='psql -h localhost -U postgres'  # Use local postgres by default
alias redis-cli='valkey-cli'  # Valkey CLI (Redis-compatible)

# Install starship if not already installed
if ! command -v starship &> /dev/null; then
    echo "Starship not found. Installing..."
    curl -sS https://starship.rs/install.sh | sudo sh -s -- -y
fi

# Initialize starship prompt
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi

# Initialize mise
if command -v mise &> /dev/null; then
    eval "$(mise activate zsh)"
fi

# Source local customizations if they exist
if [[ -f ~/.zshrc_local ]]; then
    source ~/.zshrc_local
fi
