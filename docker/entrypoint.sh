#!/bin/bash
# DevBox Entrypoint
# Handles initialization and secrets before s6-overlay starts services

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}DevBox Entrypoint${NC}"

# folder for devbox configuration files
mkdir -p /var/run/devbox

# ============================================================================
# Set timezone
# ============================================================================
TZ="${TZ:-UTC}"
if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
    echo "$TZ" > /etc/timezone
    echo -e "${GREEN}Timezone set to: ${TZ}${NC}"
else
    echo -e "${YELLOW}Warning: Invalid timezone '$TZ', using UTC${NC}"
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    echo "UTC" > /etc/timezone
    TZ="UTC"
fi

# ============================================================================
# USER CONFIGURATION (dynamic mapping based on stored state)
# ============================================================================
TARGET_UID=${USER_UID:-1000}
TARGET_GID=${USER_GID:-1000}
TARGET_USERNAME=${USERNAME:-devbox}
TARGET_HOME="/home/${TARGET_USERNAME}"

# Read current state from /var/run/devbox (defaults to base image values if not set)
CURRENT_USERNAME=$(cat /var/run/devbox/user 2>/dev/null || echo "devbox")
CURRENT_UID=$(cat /var/run/devbox/uid 2>/dev/null || echo "9999")
CURRENT_GID=$(cat /var/run/devbox/gid 2>/dev/null || echo "9999")

echo -e "${GREEN}User configuration check:${NC}"
echo -e "  Current: ${CURRENT_USERNAME}:${CURRENT_UID}:${CURRENT_GID}"
echo -e "  Target:  ${TARGET_USERNAME}:${TARGET_UID}:${TARGET_GID}"

# Check if any changes are needed
NEEDS_UPDATE=false
if [ "$CURRENT_GID" != "$TARGET_GID" ] || [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_USERNAME" != "$TARGET_USERNAME" ]; then
    NEEDS_UPDATE=true
fi

if [ "$NEEDS_UPDATE" = true ]; then
    echo -e "${YELLOW}Updating user configuration...${NC}"

    # Update GID if needed
    if [ "$CURRENT_GID" != "$TARGET_GID" ]; then
        echo -e "  Updating GID: $CURRENT_GID -> $TARGET_GID"
        groupmod -g $TARGET_GID $CURRENT_USERNAME 2>/dev/null || true
    fi

    # Update UID if needed
    if [ "$CURRENT_UID" != "$TARGET_UID" ]; then
        echo -e "  Updating UID: $CURRENT_UID -> $TARGET_UID"
        usermod -u $TARGET_UID $CURRENT_USERNAME
    fi

    # Rename user if needed
    if [ "$CURRENT_USERNAME" != "$TARGET_USERNAME" ]; then
        echo -e "  Renaming user: $CURRENT_USERNAME -> $TARGET_USERNAME"
        usermod -l $TARGET_USERNAME $CURRENT_USERNAME
        groupmod -n $TARGET_USERNAME $CURRENT_USERNAME 2>/dev/null || true
        usermod -d /home/$TARGET_USERNAME -m $TARGET_USERNAME 2>/dev/null || true
    fi

    echo -e "${GREEN}User configuration updated${NC}"
else
    echo -e "${GREEN}User configuration unchanged${NC}"
fi

# ============================================================================
# USER CONFIGURATION (dynamic mapping based on stored state)
# ============================================================================
echo "$TARGET_USERNAME" > /var/run/devbox/user
echo "$TARGET_UID" > /var/run/devbox/uid
echo "$TARGET_GID" > /var/run/devbox/gid
echo "$TARGET_HOME" > /var/run/devbox/home
echo "${POSTGRES_USER:-postgres}" > /var/run/devbox/postgres_user
echo "${POSTGRES_DB:-devdb}" > /var/run/devbox/postgres_db
echo "${SERVICE_ROOT:-/devbox/}" > /var/run/devbox/service_root
echo "${MISE_ENV:-}" > /var/run/devbox/mise_env
chmod 644 /var/run/devbox/*

# ============================================================================
# COMPUTE WEBROOT URL
# ============================================================================
# Determine the base URL for accessing web services
# Can be overridden via WEBROOT environment variable (useful for Cloudflare tunnels)
if [ -z "$WEBROOT" ]; then
    if [ -n "$TS_AUTHKEY" ]; then
        # Tailscale mode - use HTTPS
        TS_HOSTNAME_VALUE="${TS_HOSTNAME:-${CONTAINER_NAME}}"
        if [ -n "$TS_SUFFIX" ]; then
            WEBROOT="https://${TS_HOSTNAME_VALUE}.${TS_SUFFIX}"
        else
            WEBROOT="https://${TS_HOSTNAME_VALUE}"
        fi
    else
        # Local mode - use HTTP with Caddy port
        WEBROOT="http://localhost:${CADDY_PORT}"
    fi
fi

# Write WEBROOT to /var/run/devbox for system-wide access
echo "$WEBROOT" > /var/run/devbox/webroot
chmod 644 /var/run/devbox/webroot

echo -e "${GREEN}WEBROOT: ${WEBROOT}${NC}"

# ============================================================================
# SECRETS - Write to /etc/secrets and remove from environment
# ============================================================================
echo -e "${BLUE}Setting up secrets...${NC}"
mkdir -p /etc/secrets
chmod 700 /etc/secrets

if [ -n "$TS_AUTHKEY" ]; then
    echo "[entrypoint] Creating Tailscale auth key file"
    echo "$TS_AUTHKEY" > /etc/secrets/ts_authkey
    chmod 600 /etc/secrets/ts_authkey
    unset TS_AUTHKEY
fi

if [ -n "$CF_TUNNEL_TOKEN" ]; then
    echo "[entrypoint] Creating Cloudflare tunnel token file"
    echo "$CF_TUNNEL_TOKEN" > /etc/secrets/cf_tunnel_token
    chmod 600 /etc/secrets/cf_tunnel_token
    unset CF_TUNNEL_TOKEN
fi


# Ensure sudo permissions (always update)
echo "${TARGET_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USERNAME}
chmod 0440 /etc/sudoers.d/${TARGET_USERNAME}

# ============================================================================
# FIRST-TIME INITIALIZATION (use marker in /state which persists)
# ============================================================================
if [ ! -f "/state/devbox-initialized" ]; then
    echo -e "${YELLOW}=== First-Time Setup ===${NC}"

    # Fix ownership
    chown -R $TARGET_UID:$TARGET_GID /home/$TARGET_USERNAME /workspace /snapshots 2>/dev/null || true

    # Git config (copy from host if available)
    [ -f "${TARGET_HOME}/.gitconfig-host" ] && cp "${TARGET_HOME}/.gitconfig-host" "${TARGET_HOME}/.gitconfig"

    # Copy dotfiles (first time only - won't overwrite existing files)
    if [ -d "/etc/dotfiles" ]; then
        echo -e "${GREEN}Copying dotfiles from /etc/dotfiles${NC}"
        cp -rn /etc/dotfiles/. ${TARGET_HOME}/ 2>/dev/null || true
        # Fix ownership of copied files (skip .ssh bind mount and read-only mounts)
        find ${TARGET_HOME} -path ${TARGET_HOME}/.ssh -prune -o -type f -writable -exec chown ${TARGET_USERNAME}:${TARGET_USERNAME} {} + 2>/dev/null || true
        find ${TARGET_HOME} -path ${TARGET_HOME}/.ssh -prune -o -type d -writable -exec chown ${TARGET_USERNAME}:${TARGET_USERNAME} {} + 2>/dev/null || true
    fi

    # Configure git SSH signing if ed25519 key exists
    if [ -f "${TARGET_HOME}/.ssh/id_ed25519.pub" ]; then
        echo -e "${GREEN}Configuring git SSH signing${NC}"
        su - ${TARGET_USERNAME} -s /bin/zsh -c "git config --global gpg.format ssh" 2>/dev/null || true
        su - ${TARGET_USERNAME} -s /bin/zsh -c "git config --global user.signingkey '${TARGET_HOME}/.ssh/id_ed25519.pub'" 2>/dev/null || true
        su - ${TARGET_USERNAME} -s /bin/zsh -c "git config --global commit.gpgsign true" 2>/dev/null || true
    fi

    # Mark as initialized (in /state which persists)
    echo "Initialized on $(date)" > /state/devbox-initialized
    echo -e "${GREEN}First-time initialization complete${NC}"
else
    echo -e "${GREEN}Already initialized, skipping setup${NC}"
fi

# ============================================================================
# ALWAYS RUN (every startup)
# ============================================================================

# SSH configuration - needs to run every time to handle PASSWORD changes
sed -i "s|#AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys|" /etc/ssh/sshd_config

if [ -n "$PASSWORD" ]; then
    echo "${TARGET_USERNAME}:${PASSWORD}" | chpasswd
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
else
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
fi

# Ensure dotfiles exist (cp -n only copies files that don't exist, won't overwrite user changes)
if [ -d "/etc/dotfiles" ]; then
    cp -rn /etc/dotfiles/. ${TARGET_HOME}/ 2>/dev/null || true
    # Fix ownership of files we created (skip .ssh bind mount and read-only mounts)
    find ${TARGET_HOME} -path ${TARGET_HOME}/.ssh -prune -o -type f -writable -exec chown ${TARGET_USERNAME}:${TARGET_USERNAME} {} + 2>/dev/null || true
    find ${TARGET_HOME} -path ${TARGET_HOME}/.ssh -prune -o -type d -writable -exec chown ${TARGET_USERNAME}:${TARGET_USERNAME} {} + 2>/dev/null || true
fi

# Ensure workspace/snapshots ownership
chown ${TARGET_USERNAME}:${TARGET_USERNAME} /workspace /snapshots 2>/dev/null || true

# Install additional APT packages if specified
if [ -n "$APT_PACKAGES" ]; then
    echo -e "${GREEN}Installing additional APT packages: ${APT_PACKAGES}${NC}"
    apt-get update > /dev/null 2>&1
    apt-get install -y $APT_PACKAGES || echo -e "${YELLOW}Warning: Failed to install some packages${NC}"
    rm -rf /var/lib/apt/lists/*
fi

# Install mise global tools if specified
if [ -n "$MISE_GLOBAL_TOOLS" ]; then
    echo -e "${GREEN}Installing mise global tools: ${MISE_GLOBAL_TOOLS}${NC}"
    for tool in $MISE_GLOBAL_TOOLS; do
        echo -e "${BLUE}Installing ${tool}...${NC}"
        su - ${TARGET_USERNAME} -c "mise use -g ${tool}" || echo -e "${YELLOW}Warning: Failed to install ${tool}${NC}"
    done
fi

# Run pre-start hook if it exists and is executable
PRE_START_HOOK="${PRE_START_HOOK:-/opt/hooks/pre_start.sh}"
if [ -x "$PRE_START_HOOK" ]; then
    echo -e "${GREEN}Running pre-start hook${NC}"
    "$PRE_START_HOOK" || true
fi

echo -e "${GREEN}Entrypoint complete, starting s6-overlay${NC}"

# Start s6-overlay
exec /init
