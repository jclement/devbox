# ~/.zshenv

# Add ~/.local/bin to PATH
export PATH="$HOME/.local/bin:/opt/scripts:$PATH"
export PROJECT_ROOT="/workspace"

# Webroot URL (computed at container startup)
if [ -f /var/run/devbox/webroot ]; then
    export WEBROOT=$(cat /var/run/devbox/webroot)
fi

# Mise environment (read from runtime config)
if [ -f /var/run/devbox/mise_env ]; then
    MISE_ENV_VALUE=$(cat /var/run/devbox/mise_env)
    if [ -n "$MISE_ENV_VALUE" ]; then
        export MISE_ENV="$MISE_ENV_VALUE"
    fi
fi

# PostgreSQL defaults (read from runtime config)
export PGHOST=localhost
if [ -f /var/run/devbox/postgres_user ]; then
    export PGUSER=$(cat /var/run/devbox/postgres_user)
else
    export PGUSER=postgres
fi
if [ -f /var/run/devbox/postgres_db ]; then
    export PGDATABASE=$(cat /var/run/devbox/postgres_db)
else
    export PGDATABASE=devdb
fi

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
