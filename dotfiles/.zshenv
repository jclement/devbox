# ~/.zshenv

# Add ~/.local/bin to PATH
export PATH="$HOME/.local/bin:/opt/scripts:$PATH"
export PROJECT_ROOT="/workspace"

# Webroot URL (computed at container startup)
if [ -f /var/run/devbox/webroot ]; then
    export WEBROOT=$(cat /var/run/devbox/webroot)
fi

# PostgreSQL defaults
export PGHOST=localhost
export PGUSER=postgres
export PGDATABASE=devdb  # Default database when running psql

# Install mise if not already installed
if ! command -v mise &> /dev/null; then
    echo "mise not found. Installing..."
    curl https://mise.run | sh
fi

# Initialize mise
if command -v mise &> /dev/null; then
    eval "$(mise activate zsh)"
fi

# Source local customizations if they exist
if [[ -f ~/.zshenv_local ]]; then
    source ~/.zshenv_local
fi
