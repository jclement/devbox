#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting DevBox container...${NC}"

# Load .devbox configuration if it exists in workspace
if [ -f "/workspace/.devbox" ]; then
    echo -e "${GREEN}Loading configuration from /workspace/.devbox...${NC}"
    set -a
    source /workspace/.devbox
    set +a
fi

# Adapt user UID/GID to match host user at runtime
# This allows the same image to work for any user
TARGET_UID=${USER_UID:-9999}
TARGET_GID=${USER_GID:-9999}
TARGET_USERNAME=${USERNAME:-devbox}

echo -e "${GREEN}Configuring user environment...${NC}"
echo -e "  Target user: ${TARGET_USERNAME}"
echo -e "  Target UID:  ${TARGET_UID}"
echo -e "  Target GID:  ${TARGET_GID}"

# Change devbox user's UID/GID if needed
CURRENT_UID=$(id -u devbox)
CURRENT_GID=$(id -g devbox)

if [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_GID" != "$TARGET_GID" ] || [ "devbox" != "$TARGET_USERNAME" ]; then
    echo -e "${YELLOW}Adapting user to match host...${NC}"

    # Change GID if needed
    if [ "$CURRENT_GID" != "$TARGET_GID" ]; then
        # Check if target GID already exists
        EXISTING_GROUP=$(getent group $TARGET_GID | cut -d: -f1 || true)
        if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "devbox" ]; then
            echo -e "  GID ${TARGET_GID} exists as '${EXISTING_GROUP}', adding devbox to it"
            groupdel devbox 2>/dev/null || true
            usermod -g $TARGET_GID devbox
        else
            echo -e "  Changing GID: ${CURRENT_GID} → ${TARGET_GID}"
            groupmod -g $TARGET_GID devbox
        fi
    fi

    # Change UID if needed
    if [ "$CURRENT_UID" != "$TARGET_UID" ]; then
        echo -e "  Changing UID: ${CURRENT_UID} → ${TARGET_UID}"
        usermod -u $TARGET_UID devbox
    fi

    # Change username if needed
    if [ "devbox" != "$TARGET_USERNAME" ]; then
        echo -e "  Renaming user: devbox → ${TARGET_USERNAME}"
        usermod -l $TARGET_USERNAME devbox
        groupmod -n $TARGET_USERNAME devbox 2>/dev/null || true
        usermod -d /home/$TARGET_USERNAME -m $TARGET_USERNAME 2>/dev/null || true
    fi

    # Ensure fish is the default shell
    chsh -s /usr/bin/fish $TARGET_USERNAME 2>/dev/null || true

    # Ensure user has passwordless sudo
    echo "${TARGET_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USERNAME}
    chmod 0440 /etc/sudoers.d/${TARGET_USERNAME}

    # Fix ownership of home directory and workspace
    echo -e "  Updating ownership of /home/${TARGET_USERNAME} and /workspace"
    chown -R $TARGET_UID:$TARGET_GID /home/$TARGET_USERNAME 2>/dev/null || true
    chown -R $TARGET_UID:$TARGET_GID /workspace 2>/dev/null || true

    echo -e "${GREEN}User adaptation complete${NC}"
fi

# Set variables for rest of script
USERNAME=$TARGET_USERNAME
USER_HOME="/home/${USERNAME}"
export USERNAME USER_HOME
export CONTAINER_NAME DEV_SERVICE_PORT

# SSH keys are mounted directly - no agent forwarding needed

# Set up snapshots directory with proper permissions
echo -e "${GREEN}Setting up snapshots directory...${NC}"
mkdir -p /snapshots
chown ${USERNAME}:${USERNAME} /snapshots
chmod 755 /snapshots
echo -e "${GREEN}Snapshots directory ready at /snapshots${NC}"

# Configure and initialize PostgreSQL
echo -e "${GREEN}Configuring PostgreSQL...${NC}"

# Since we're running ephemeral (no persistent volume), always recreate the cluster
echo -e "${GREEN}Initializing fresh PostgreSQL database cluster...${NC}"
# Remove any existing cluster
pg_dropcluster --stop 16 main 2>/dev/null || true
# Create new cluster
pg_createcluster 16 main
echo -e "${GREEN}PostgreSQL cluster created${NC}"

# Configure PostgreSQL authentication
# Allow local peer authentication and network connections with password
cat > /etc/postgresql/16/main/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             0.0.0.0/0               md5
EOF

# Ensure PostgreSQL is configured to listen on all interfaces
if ! grep -q "^listen_addresses = '\*'" /etc/postgresql/16/main/postgresql.conf; then
    echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf
fi

# Start PostgreSQL temporarily to configure (using pg_ctlcluster - the Debian way)
echo -e "${GREEN}Starting PostgreSQL to configure...${NC}"
pg_ctlcluster 16 main start
sleep 2

# Set postgres password
echo -e "${GREEN}Setting PostgreSQL password...${NC}"
su - postgres -c "psql -c \"ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD:-postgres}';\""

# Create database if it doesn't exist
echo -e "${GREEN}Creating database ${POSTGRES_DB:-devdb}...${NC}"
su - postgres -c "psql -lqt | cut -d \\| -f 1 | grep -qw ${POSTGRES_DB:-devdb} || psql -c \"CREATE DATABASE ${POSTGRES_DB:-devdb};\""

# Load seed file if specified, otherwise try latest snapshot
if [ -n "$DB_SEED_FILE" ] && [ -f "/workspace/$DB_SEED_FILE" ]; then
    echo -e "${GREEN}Loading database seed file: ${DB_SEED_FILE}${NC}"
    if su - postgres -c "psql -d ${POSTGRES_DB:-devdb} -f /workspace/$DB_SEED_FILE"; then
        echo -e "${GREEN}Database seed loaded successfully${NC}"
    else
        echo -e "${RED}Failed to load database seed file${NC}"
    fi
elif [ -d "/snapshots" ] && [ -n "$(ls -A /snapshots/*.sql 2>/dev/null)" ]; then
    LATEST_SNAPSHOT=$(ls -t /snapshots/*.sql 2>/dev/null | head -1)
    echo -e "${YELLOW}No seed file specified, restoring from latest snapshot: $(basename $LATEST_SNAPSHOT)${NC}"
    if su - postgres -c "psql -d ${POSTGRES_DB:-devdb} -f $LATEST_SNAPSHOT"; then
        echo -e "${GREEN}Database restored from snapshot successfully${NC}"
    else
        echo -e "${RED}Failed to restore from snapshot${NC}"
    fi
else
    echo -e "${YELLOW}No seed file or snapshots found, starting with empty database${NC}"
fi

# Stop PostgreSQL (supervisord will start it)
echo -e "${GREEN}Stopping PostgreSQL (supervisord will manage it)...${NC}"
pg_ctlcluster 16 main stop
sleep 1

# Set up .pgpass for user
echo -e "${GREEN}Configuring PostgreSQL client for user...${NC}"
PGPASS_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
echo "localhost:5432:*:postgres:${PGPASS_PASSWORD}" > ${USER_HOME}/.pgpass
echo "*:5432:*:postgres:${PGPASS_PASSWORD}" >> ${USER_HOME}/.pgpass
echo "127.0.0.1:5432:*:postgres:${PGPASS_PASSWORD}" >> ${USER_HOME}/.pgpass
echo "::1:5432:*:postgres:${PGPASS_PASSWORD}" >> ${USER_HOME}/.pgpass
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.pgpass
chmod 600 ${USER_HOME}/.pgpass

# Set up .psqlrc for default connection and nice formatting
cat > ${USER_HOME}/.psqlrc <<EOF
-- Nice formatting and display
\x auto
\pset null '¤'
\timing on

-- Prompt showing database and user
\set PROMPT1 '%n@%/%R%# '
\set PROMPT2 '%n@%/%R%# '
EOF
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.psqlrc
chmod 644 ${USER_HOME}/.psqlrc

echo -e "${GREEN}PostgreSQL client configured for user ${USERNAME}${NC}"

# Set up SSH directory for user
echo -e "${GREEN}Setting up SSH keys...${NC}"
mkdir -p ${USER_HOME}/.ssh
chmod 700 ${USER_HOME}/.ssh
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.ssh

# Verify SSH key pair is mounted (keys are mounted directly into .ssh)
if [ -f "${USER_HOME}/.ssh/id_devbox" ] && [ -f "${USER_HOME}/.ssh/id_devbox.pub" ]; then
    echo -e "${GREEN}SSH key pair (id_devbox) mounted successfully${NC}"

    # Set up authorized_keys for SSH server (to allow SSH into this devbox)
    mkdir -p /etc/ssh/authorized_keys
    cp "${USER_HOME}/.ssh/id_devbox.pub" /etc/ssh/authorized_keys/${USERNAME}
    chmod 755 /etc/ssh/authorized_keys
    chmod 644 /etc/ssh/authorized_keys/${USERNAME}

    # Configure SSH to use the authorized_keys file
    sed -i "s|#AuthorizedKeysFile.*|AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys|" /etc/ssh/sshd_config

    echo -e "${GREEN}SSH server configured to accept key-based authentication${NC}"
else
    echo -e "${YELLOW}Warning: SSH key not found at ~/.ssh/id_devbox${NC}"
    echo -e "${YELLOW}SSH authentication may not work. Check SSH_KEY in .env${NC}"
fi

# Create writable known_hosts (will be populated as user connects to servers)
touch ${USER_HOME}/.ssh/known_hosts
chmod 644 ${USER_HOME}/.ssh/known_hosts
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.ssh/known_hosts

# Configure SSH password authentication
if [ -n "$PASSWORD" ]; then
    echo -e "${GREEN}Configuring SSH with password authentication...${NC}"
    # Set user password
    echo "${USERNAME}:${PASSWORD}" | chpasswd
    # Enable password authentication
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    echo -e "${GREEN}SSH password authentication enabled${NC}"
else
    echo -e "${YELLOW}No password set, disabling SSH password authentication...${NC}"
    # Disable password authentication (key-based only)
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    echo -e "${YELLOW}SSH key authentication only${NC}"
fi

# Configure Git
echo -e "${GREEN}Configuring Git...${NC}"

# Copy .gitconfig from host if available
if [ -f "${USER_HOME}/.gitconfig-host" ]; then
    cp "${USER_HOME}/.gitconfig-host" "${USER_HOME}/.gitconfig"
    echo -e "${GREEN}Copied Git config from host${NC}"
fi

# Configure Git to use SSH signing with id_devbox key
if [ -f "${USER_HOME}/.ssh/id_devbox.pub" ]; then
    echo -e "${GREEN}Configuring SSH commit signing with id_devbox key${NC}"
    su - ${USERNAME} -s /bin/bash -c "git config --global gpg.format ssh"
    su - ${USERNAME} -s /bin/bash -c "git config --global user.signingkey '${USER_HOME}/.ssh/id_devbox.pub'"
    su - ${USERNAME} -s /bin/bash -c "git config --global commit.gpgsign true"
    echo -e "${GREEN}Git configured for SSH commit signing${NC}"
else
    echo -e "${YELLOW}No SSH key found, commit signing not configured${NC}"
fi

# Ensure correct ownership
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.gitconfig 2>/dev/null || true

# Configure fish and bash for the runtime user
echo -e "${GREEN}Configuring shell for ${USERNAME}...${NC}"

# Ensure fish config exists
mkdir -p ${USER_HOME}/.config/fish
cat > ${USER_HOME}/.config/fish/config.fish <<EOF
# Terminal colors
set -gx TERM xterm-256color
set -gx COLORTERM truecolor

# PostgreSQL defaults (used by psql when no args provided)
set -gx PGHOST localhost
set -gx PGUSER postgres
set -gx PGDATABASE ${POSTGRES_DB:-devdb}

# Auto sudo for apt commands
alias apt="sudo apt"
alias apt-get="sudo apt-get"

if status is-interactive
    # mise activation (system-wide installation)
    /usr/local/bin/mise activate fish | source
    # starship prompt
    starship init fish | source
end
EOF

# Configure bash (fallback)
if [ -f "${USER_HOME}/.bashrc" ]; then
    grep -q "TERM=" ${USER_HOME}/.bashrc || echo 'export TERM=xterm-256color' >> ${USER_HOME}/.bashrc
    grep -q "COLORTERM=" ${USER_HOME}/.bashrc || echo 'export COLORTERM=truecolor' >> ${USER_HOME}/.bashrc
    grep -q "PGHOST=" ${USER_HOME}/.bashrc || echo 'export PGHOST=localhost' >> ${USER_HOME}/.bashrc
    grep -q "PGUSER=" ${USER_HOME}/.bashrc || echo 'export PGUSER=postgres' >> ${USER_HOME}/.bashrc
    grep -q "PGDATABASE=" ${USER_HOME}/.bashrc || echo "export PGDATABASE=${POSTGRES_DB:-devdb}" >> ${USER_HOME}/.bashrc
    grep -q "mise activate" ${USER_HOME}/.bashrc || echo 'eval "$(/usr/local/bin/mise activate bash)"' >> ${USER_HOME}/.bashrc
    grep -q "starship init" ${USER_HOME}/.bashrc || echo 'eval "$(starship init bash)"' >> ${USER_HOME}/.bashrc
    grep -q "alias apt=" ${USER_HOME}/.bashrc || echo 'alias apt="sudo apt"' >> ${USER_HOME}/.bashrc
    grep -q "alias apt-get=" ${USER_HOME}/.bashrc || echo 'alias apt-get="sudo apt-get"' >> ${USER_HOME}/.bashrc
fi

# Configure code-server
echo -e "${GREEN}Configuring code-server...${NC}"
mkdir -p ${USER_HOME}/.config/code-server
mkdir -p ${USER_HOME}/.config/mise
# Always use no auth - Caddy handles authentication if PASSWORD is set
cat > ${USER_HOME}/.config/code-server/config.yaml <<EOF
bind-addr: 127.0.0.1:8080
auth: none
cert: false
EOF
if [ -n "$PASSWORD" ]; then
    echo -e "${GREEN}code-server configured (authentication handled by Caddy)${NC}"
else
    echo -e "${GREEN}code-server configured (no authentication)${NC}"
fi

# Fix ownership for .config directory and subdirectories (avoid read-only mounts)
chown ${USERNAME}:${USERNAME} ${USER_HOME}/.config 2>/dev/null || true
chown -R ${USERNAME}:${USERNAME} ${USER_HOME}/.config/fish 2>/dev/null || true
chown -R ${USERNAME}:${USERNAME} ${USER_HOME}/.config/code-server 2>/dev/null || true
chown -R ${USERNAME}:${USERNAME} ${USER_HOME}/.config/mise 2>/dev/null || true

# Bootstrap mise from /workspace if config exists
echo -e "${GREEN}Checking for mise configuration in /workspace...${NC}"
if [ -f "/workspace/.mise.toml" ] || [ -f "/workspace/.tool-versions" ]; then
    echo -e "${GREEN}Found mise configuration, bootstrapping...${NC}"
    cd /workspace
    su - ${USERNAME} -c "cd /workspace && eval \"\$(/usr/local/bin/mise activate bash)\" && /usr/local/bin/mise trust && /usr/local/bin/mise install"
    echo -e "${GREEN}mise bootstrapped successfully${NC}"
else
    echo -e "${YELLOW}No mise configuration found in /workspace${NC}"
fi

# Execute pre-startup command if defined
if [ -n "$PRE_STARTUP_CMD" ]; then
    echo -e "${GREEN}Executing pre-startup command...${NC}"
    cd /workspace
    if su - ${USERNAME} -c "cd /workspace && $PRE_STARTUP_CMD"; then
        echo -e "${GREEN}Pre-startup command completed successfully${NC}"
    else
        echo -e "${RED}Pre-startup command failed${NC}"
    fi
fi

# Start Tailscale if TS_AUTHKEY is provided
if [ -n "$TS_AUTHKEY" ]; then
    echo -e "${GREEN}Starting Tailscale daemon...${NC}"
    tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

    # Wait for tailscaled to start
    sleep 2

    # Check if hostname is set
    if [ -z "$TS_HOSTNAME" ]; then
        echo -e "${RED}Error: TS_HOSTNAME environment variable is required when using Tailscale${NC}"
        exit 1
    fi

    # Authenticate with Tailscale
    echo -e "${GREEN}Connecting to Tailscale...${NC}"
    tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME}" --accept-routes

    # Wait for Tailscale to be fully connected
    sleep 3

    # Serve SSH over Tailscale on port 22
    echo -e "${GREEN}Configuring Tailscale to serve SSH on port 22...${NC}"
    tailscale serve --bg tcp:22 tcp://localhost:22

    # Serve Caddy over Tailscale on port 443 with HTTPS
    echo -e "${GREEN}Configuring Tailscale to serve web services on port 443...${NC}"
    tailscale serve --bg https:443 http://localhost:8443

    # Serve PostgreSQL over Tailscale on port 5432
    echo -e "${GREEN}Configuring Tailscale to serve PostgreSQL on port 5432...${NC}"
    tailscale serve --bg tcp:5432 tcp://localhost:5432
else
    echo -e "${YELLOW}Tailscale not configured (TS_AUTHKEY not set)${NC}"
    echo -e "${YELLOW}Running in local-only mode with port forwarding${NC}"
fi

# Generate Caddyfile with optional authentication
echo -e "${GREEN}Generating Caddyfile...${NC}"
if [ -n "$PASSWORD" ]; then
    echo -e "${YELLOW}Password authentication enabled${NC}"
    # Generate bcrypt hash for the password
    PASSWORD_HASH=$(caddy hash-password --plaintext "$PASSWORD")

    cat > /etc/caddy/Caddyfile <<EOF
:8443 {
    # Basic authentication for all routes
    basicauth {
        ${USERNAME:-devbox} $PASSWORD_HASH
    }

    # code-server at /devbox/code/
    handle_path /devbox/code/* {
        reverse_proxy localhost:8080
    }

    # pgweb (PostgreSQL web interface) at /devbox/db/
    handle_path /devbox/db/* {
        reverse_proxy localhost:8081
    }

    # MailHog web UI at /devbox/mail/
    handle_path /devbox/mail/* {
        reverse_proxy localhost:8025
    }

    # File Browser at /devbox/files/
    handle_path /devbox/files/* {
        reverse_proxy localhost:8083
    }

    # DevBox status page at /devbox/ (must come after specific /devbox/* routes)
    handle /devbox* {
        uri strip_prefix /devbox
        reverse_proxy localhost:8082
    }

    # Main development service (everything else goes to user's app)
    handle /* {
        reverse_proxy localhost:{\$DEV_SERVICE_PORT:3000}
    }

    # Enable logging
    log {
        output stdout
        format console
    }
}
EOF
else
    echo -e "${YELLOW}No password set, access is unrestricted${NC}"
    # Use the original Caddyfile without auth
    cp /etc/caddy/Caddyfile.template /etc/caddy/Caddyfile 2>/dev/null || true
fi

# Start supervisord in the background
echo -e "${GREEN}Starting services via supervisord...${NC}"
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &

# Wait a bit for services to start
sleep 5

# Execute post-startup command if defined
if [ -n "$POST_STARTUP_CMD" ]; then
    echo -e "${GREEN}Executing post-startup command...${NC}"
    cd /workspace
    if su - ${USERNAME} -c "cd /workspace && $POST_STARTUP_CMD"; then
        echo -e "${GREEN}Post-startup command completed successfully${NC}"
    else
        echo -e "${RED}Post-startup command failed (continuing anyway)${NC}"
    fi
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            DevBox Ready - Happy Coding!                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -n "$TS_AUTHKEY" ]; then
    # Tailscale mode - secure remote access
    echo -e "${GREEN}📡 Networking Mode: ${NC}${YELLOW}Tailscale (Remote Access)${NC}"
    echo ""
    echo -e "${GREEN}🔐 SSH Access:${NC}"
    echo -e "   ${BLUE}ssh ${USERNAME}@${TS_HOSTNAME}${NC}"
    echo ""
    echo -e "${GREEN}🌐 Web Services:${NC} ${YELLOW}https://${TS_HOSTNAME}${NC}"
    echo -e "   ${BLUE}├─${NC} Main App:     ${YELLOW}https://${TS_HOSTNAME}/${NC}"
    echo -e "   ${BLUE}├─${NC} VS Code:      ${YELLOW}https://${TS_HOSTNAME}/devbox/code/${NC}"
    echo -e "   ${BLUE}├─${NC} PostgreSQL:   ${YELLOW}https://${TS_HOSTNAME}/devbox/db/${NC}"
    echo -e "   ${BLUE}├─${NC} MailHog:      ${YELLOW}https://${TS_HOSTNAME}/devbox/mail/${NC}"
    echo -e "   ${BLUE}├─${NC} Files:        ${YELLOW}https://${TS_HOSTNAME}/devbox/files/${NC}"
    echo -e "   ${BLUE}├─${NC} Logs:         ${YELLOW}https://${TS_HOSTNAME}/devbox/logs/${NC}"
    echo -e "   ${BLUE}└─${NC} Status:       ${YELLOW}https://${TS_HOSTNAME}/devbox/${NC}"
    echo ""
    echo -e "${GREEN}🗄️  Database:${NC}"
    echo -e "   ${BLUE}psql -h ${TS_HOSTNAME} -U postgres -d ${POSTGRES_DB:-devdb}${NC}"
    echo ""
else
    # Local mode - port forwarding
    # Detect actual exposed ports from Docker environment or use defaults
    # Docker Compose passes these as env vars
    ACTUAL_SSH_PORT="${SSH_PORT:-2200}"
    ACTUAL_CADDY_PORT="${CADDY_PORT:-8400}"
    ACTUAL_POSTGRES_PORT="${POSTGRES_PORT:-5400}"

    # Try to detect from Docker if running in compose
    if command -v docker &> /dev/null && [ -n "$CONTAINER_NAME" ]; then
        DETECTED_SSH=$(docker port "$CONTAINER_NAME" 22 2>/dev/null | grep -o '[0-9]*$' | head -1)
        DETECTED_CADDY=$(docker port "$CONTAINER_NAME" 8443 2>/dev/null | grep -o '[0-9]*$' | head -1)
        DETECTED_POSTGRES=$(docker port "$CONTAINER_NAME" 5432 2>/dev/null | grep -o '[0-9]*$' | head -1)

        [ -n "$DETECTED_SSH" ] && ACTUAL_SSH_PORT="$DETECTED_SSH"
        [ -n "$DETECTED_CADDY" ] && ACTUAL_CADDY_PORT="$DETECTED_CADDY"
        [ -n "$DETECTED_POSTGRES" ] && ACTUAL_POSTGRES_PORT="$DETECTED_POSTGRES"
    fi

    echo -e "${GREEN}🏠 Networking Mode: ${NC}${YELLOW}Local (Port Forwarding)${NC}"
    echo ""
    echo -e "${GREEN}🔐 SSH Access:${NC}"
    echo -e "   ${BLUE}ssh -p ${ACTUAL_SSH_PORT} ${USERNAME}@localhost${NC}"
    echo ""
    echo -e "${GREEN}🌐 Web Services:${NC} ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}${NC}"
    echo -e "   ${BLUE}├─${NC} Main App:     ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/${NC}"
    echo -e "   ${BLUE}├─${NC} VS Code:      ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/code/${NC}"
    echo -e "   ${BLUE}├─${NC} PostgreSQL:   ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/db/${NC}"
    echo -e "   ${BLUE}├─${NC} MailHog:      ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/mail/${NC}"
    echo -e "   ${BLUE}├─${NC} Files:        ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/files/${NC}"
    echo -e "   ${BLUE}├─${NC} Logs:         ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/logs/${NC}"
    echo -e "   ${BLUE}└─${NC} Status:       ${YELLOW}http://localhost:${ACTUAL_CADDY_PORT}/devbox/${NC}"
    echo ""
    echo -e "${GREEN}🗄️  Database:${NC}"
    echo -e "   ${BLUE}psql -h localhost -p ${ACTUAL_POSTGRES_PORT} -U postgres -d ${POSTGRES_DB:-devdb}${NC}"
    echo ""
    echo -e "${GREEN}📦 Exposed Ports:${NC}"
    echo -e "   ${BLUE}SSH:${NC}        ${ACTUAL_SSH_PORT}"
    echo -e "   ${BLUE}Web:${NC}        ${ACTUAL_CADDY_PORT}"
    echo -e "   ${BLUE}PostgreSQL:${NC} ${ACTUAL_POSTGRES_PORT}"
    echo ""
fi

echo -e "${GREEN}📧 SMTP Server:${NC} ${BLUE}localhost:1025${NC} (for apps inside container)"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

# Execute the CMD or provided command
exec "$@"
