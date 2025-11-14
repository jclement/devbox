# DevBox - Docker Compose Edition

A complete, portable development environment in a single container. Clone, configure, and code - anywhere.

## Vision

Imagine you want to start a new project or work on an existing one. You:

1. Copy `docker-compose.yml` and `.env.example` to your project folder
2. Rename `.env.example` to `.env` and customize (or use defaults)
3. Run `docker compose up -d`
4. SSH into your personal dev environment on your Tailscale network
5. Clone your repo and start coding

Your devbox appears on your Tailnet with:
- SSH access (with your keys and commit signing)
- VS Code in the browser (code-server)
- PostgreSQL with web interface (pgweb)
- Email testing (MailHog)
- File browser for workspace management
- Your development service at the root path

Everything is configured, everything works, and you can access it from anywhere on your Tailnet.

## What's Inside

### Development Tools
- **mise** - Universal version manager (Node, Python, Ruby, Go, etc.)
- **git**, **lazygit** - Version control with SSH signing
- **vim**, **helix** - Terminal editors
- **code-server** - VS Code in your browser
- **ripgrep**, **fzf** - Fast searching tools

### Shell & Prompt
- **zsh** - Powerful shell with vim mode (default)
- **starship** - Beautiful cross-shell prompt with git integration
  - Displays container/hostname for easy identification
  - Git branch and status indicators
  - Clean, minimal design

### Database & Services
- **PostgreSQL 16** - Production-ready database with persistent storage
- **pgweb** - Web-based PostgreSQL admin interface
- **MailHog** - SMTP testing server with web UI

### Networking & Access
- **Caddy** - Modern reverse proxy with automatic HTTPS
- **Tailscale** - Zero-config VPN for secure remote access
- **SSH Server** - Secure remote access with persistent host keys
- **File Browser** - Web-based file management for workspace

### Helper Scripts
- **snapshot** - Save database state to timestamped file
- **restore** - Restore database from snapshot
- **toggle_public** - Enable/disable Tailscale Funnel for public access

## Quick Start

### 1. Setup

```bash
# Copy configuration template
cp .env.example .env

# Edit .env with your details
# At minimum, set:
#   - USER_UID and USER_GID (run: id -u && id -g)
#   - USERNAME (your username)
#   - CONTAINER_NAME (used as hostname, e.g., "dev-myproject")
#   - For Tailscale: TS_AUTHKEY and TS_SUFFIX (e.g., "your-tailnet.ts.net")
vim .env

# Create SSH directory and add your public key
mkdir -p ssh
cat ~/.ssh/id_ed25519.pub >> ssh/authorized_keys
```

### 2. Start

```bash
# Build and start in detached mode
docker compose up --build -d

# View logs
docker compose logs -f

# Check status
docker compose ps
```

### 3. Access

**Tailscale Mode:**
```bash
# SSH into your devbox
ssh yourusername@devbox.your-tailnet.ts.net

# Access services (admin tools require auth if PASSWORD is set)
https://devbox.your-tailnet.ts.net/              # Your dev service
https://devbox.your-tailnet.ts.net/devbox/code/  # VS Code
https://devbox.your-tailnet.ts.net/devbox/db/    # PostgreSQL admin
https://devbox.your-tailnet.ts.net/devbox/mail/  # Email testing
https://devbox.your-tailnet.ts.net/devbox/files/ # File browser
https://devbox.your-tailnet.ts.net/devbox/       # Status dashboard

# Connect to PostgreSQL
psql -h devbox.your-tailnet.ts.net -U postgres -d devdb
```

**Local Mode (TS_AUTHKEY not set):**
```bash
# SSH (default port 2200)
ssh -p 2200 yourusername@localhost

# Access services (default port 8400)
http://localhost:8400/              # Your dev service
http://localhost:8400/devbox/code/  # VS Code
http://localhost:8400/devbox/db/    # PostgreSQL admin
http://localhost:8400/devbox/mail/  # Email testing
http://localhost:8400/devbox/files/ # File browser

# Connect to PostgreSQL (default port 5400)
psql -h localhost -p 5400 -U postgres -d devdb
```

## Configuration

All configuration is done via `.env` file. See `.env.example` for full options and examples.

Key settings:

```bash
# User Configuration (REQUIRED - match your host user)
USER_UID=1000              # Run: id -u
USER_GID=1000              # Run: id -g
USERNAME=yourname

# Container
CONTAINER_NAME=devbox      # Used as Tailscale hostname
IMAGE_NAME=ghcr.io/jclement/devbox:latest

# Tailscale (for remote access)
TS_AUTHKEY=tskey-auth-...  # Get from https://login.tailscale.com/admin/settings/keys
TS_SUFFIX=your.ts.net      # Your tailnet domain

# Local Mode (when TS_AUTHKEY not set)
SSH_PORT=2200
CADDY_PORT=8400
POSTGRES_PORT=5400

# Security (optional but recommended for public access)
PASSWORD=                  # HTTP Basic Auth for /devbox/* admin tools

# Database
POSTGRES_DB=devdb
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# Your Dev Service
DEV_SERVICE_PORT=3000      # Port your app listens on

# VS Code (code-server) Configuration
VSCODE_DEFAULT_EXTENSIONS=vscodevim.vim;Anthropic.claude-code;github.copilot
VSCODE_DEFAULT_THEME=Default Dark+
```

### VS Code (code-server) Customization

On first startup, code-server automatically installs configured extensions and applies theme settings. This only happens once - subsequent starts preserve your customizations.

**Customize extensions:**
```bash
# In .env
VSCODE_DEFAULT_EXTENSIONS=vscodevim.vim;ms-python.python;dbaeumer.vscode-eslint

# Or disable automatic installation
VSCODE_DEFAULT_EXTENSIONS=
```

**Customize theme:**
```bash
# In .env
VSCODE_DEFAULT_THEME=Default Dark+         # Dark theme (default)
VSCODE_DEFAULT_THEME=Default Light+        # Light theme
VSCODE_DEFAULT_THEME=Monokai              # Other installed theme
```

**How it works:**
- Extensions and theme are configured on first run only
- Settings persist in `./data/home/.local/share/code-server/` (if home directory is mounted)
- Manual changes via VS Code UI are preserved
- Delete the `.configured` marker file to reset configuration

**Finding extension IDs:**
Visit https://open-vsx.org/ and search for extensions. The ID format is `publisher.extension-name`.

## Exposing Services Publicly

DevBox provides three ways to expose your dev service to the public internet:

### Option 1: Tailscale Funnel (Recommended)

Tailscale Funnel exposes your service through Tailscale's infrastructure with automatic HTTPS.

```bash
# Inside the container
toggle_public

# Follow the prompts to enable public access
# Your service will be available at: https://devbox.your-tailnet.ts.net
```

**How it works:**
- Uses Tailscale's built-in funnel feature
- Automatic HTTPS with valid certificates
- Only exposes your dev service (port ${DEV_SERVICE_PORT})
- Admin tools (/devbox/*) remain private on your Tailnet
- Single y/N confirmation to enable

**Requirements:**
- Active Tailscale connection
- Funnel must be enabled for your Tailnet

**To disable:**
```bash
toggle_public  # Run again and confirm to disable
```

### Option 2: Cloudflare Tunnel

Cloudflare Tunnel routes traffic through Cloudflare's global network.

```bash
# Get tunnel token from: https://one.dash.cloudflare.com/

# In .env
CF_TUNNEL_TOKEN=your-cloudflare-tunnel-token

# Restart container
docker compose restart
```

**How it works:**
- Creates encrypted tunnel to Cloudflare
- Routes traffic to your dev service
- Automatic HTTPS with Cloudflare certificates
- DDoS protection and CDN benefits

**Requirements:**
- Cloudflare account
- Domain managed by Cloudflare (or Cloudflare tunnel subdomain)

### Option 3: Direct Port Forwarding (Local Only)

Use when working locally without Tailscale.

```bash
# In .env
TS_AUTHKEY=           # Leave empty
CADDY_PORT=8400       # Accessible at http://localhost:8400
```

**Not suitable for public access** - requires manual port forwarding/ngrok/etc.

### Security Considerations

When exposing services publicly:

1. **Set a PASSWORD** in .env to require authentication for admin tools
2. **Use Tailscale Funnel** for controlled public access
3. **Monitor access** through service logs: `docker compose logs -f`
4. **Admin tools** (/devbox/*) automatically protected by PASSWORD if set
5. **Keep credentials secure** - use strong passwords, don't commit .env to git

## Adding Custom Services

DevBox uses a simple service script pattern that makes it easy to add your own services.

### Service Script Structure

Services live in `services/` directory and follow this template:

```bash
#!/bin/bash
# services/XX-servicename.sh

set -e

SERVICE_NAME="servicename"

case "${1:-start}" in
    install)
        # Install dependencies and configure (runs during Docker build)
        echo "[$SERVICE_NAME] Installing..."
        apt-get update
        apt-get install -y your-package
        rm -rf /var/lib/apt/lists/*
        echo "[$SERVICE_NAME] Installed successfully"
        ;;

    start)
        # Start the service (runs as supervised process via s6-overlay)
        echo "[$SERVICE_NAME] Starting..."
        exec /usr/bin/your-service
        ;;

    stop)
        # Stop the service
        echo "[$SERVICE_NAME] Stopping..."
        killall your-service || true
        ;;

    status)
        # Check if running
        pgrep -x your-service >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
```

### Naming Convention

Files are named `XX-servicename.sh` where XX determines start order:

- `00-09`: Reserved for initialization (handled in entrypoint.sh)
- `10-19`: Core infrastructure (database, ssh)
- `20-39`: Supporting services (caddy, monitoring)
- `40-89`: Application services (code-server, pgweb, mailhog, filebrowser)
- `90-99`: External connectivity (tailscale, cloudflared)

### Adding a Service

1. **Create the service script** in `services/`:
   ```bash
   vim services/50-myservice.sh
   chmod +x services/50-myservice.sh
   ```

2. **The Dockerfile automatically**:
   - Copies scripts to `/opt/services/` (not in PATH)
   - Runs `install` command during build
   - Creates s6-overlay service configuration
   - Service starts automatically on container boot

3. **Rebuild the container**:
   ```bash
   docker compose build
   docker compose up -d
   ```

### Adding State Persistence

If your service needs persistent state:

1. **Create state directory** in Dockerfile:
   ```dockerfile
   RUN mkdir -p /state/yourservice
   ```

2. **Use persistent storage** in your service script:
   ```bash
   start)
       # Link to persistent storage
       if [ ! -L "/var/lib/yourservice" ]; then
           mkdir -p /state/yourservice/data
           rm -rf /var/lib/yourservice
           ln -sf /state/yourservice/data /var/lib/yourservice
           chown yourservice:yourservice /var/lib/yourservice
       fi

       exec /usr/bin/yourservice
       ;;
   ```

3. **State persists** in `./data/state:/state` bind mount (shared across all services)

### Example: Adding Redis

```bash
# services/15-redis.sh
#!/bin/bash
set -e

SERVICE_NAME="redis"

case "${1:-start}" in
    install)
        echo "[$SERVICE_NAME] Installing Redis..."
        apt-get update
        apt-get install -y redis-server
        rm -rf /var/lib/apt/lists/*
        echo "[$SERVICE_NAME] Redis installed successfully"
        ;;

    start)
        echo "[$SERVICE_NAME] Starting Redis..."

        # Persist Redis data in /state
        if [ ! -L "/var/lib/redis" ]; then
            mkdir -p /state/redis/data
            rm -rf /var/lib/redis
            ln -sf /state/redis/data /var/lib/redis
            chown redis:redis /var/lib/redis
        fi

        exec su - redis -s /bin/sh -c '/usr/bin/redis-server --daemonize no'
        ;;

    stop)
        echo "[$SERVICE_NAME] Stopping Redis..."
        killall redis-server || true
        ;;

    status)
        pgrep -x redis-server >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
```

### Adding Service to Caddy Proxy

To expose your service through Caddy, edit `services/30-caddy.sh`:

```bash
# In the Caddyfile generation section, add a new handle block:
handle_path /devbox/redis/* {
    reverse_proxy localhost:6379
}
```

Then access at: `https://devbox.your-tailnet.ts.net/devbox/redis/`

## Workspace Persistence

Your code lives in `./data/workspace` on the host, bind-mounted to `/workspace` in the container.

```bash
# View your workspace
docker compose exec devbox ls -la /workspace

# Everything persists across container restarts
docker compose down
docker compose up -d
```

## Database Management

### Snapshots

Save your database state to timestamped files:

```bash
# Inside the container
snapshot                           # Creates .snapshots/YYYY-MM-DD-HHMMSS.sql
snapshot mydata                    # Creates .snapshots/mydata.sql

# Restore from snapshot
restore mydata                     # Restores from .snapshots/mydata.sql
restore                            # Shows available snapshots
```

Snapshots are stored in `./data/snapshots/` and persist on your host.

### Seed on Startup

```bash
# In .env
DB_SEED_FILE=database/seed.sql

# Place file at ./data/workspace/database/seed.sql
# Will load automatically on first database initialization
```

### Default Database

The container automatically connects to `devdb` when you run `psql` with no arguments, using environment variables:
- `PGHOST=localhost`
- `PGUSER=postgres`
- `PGDATABASE=devdb`

## Lifecycle Hooks

Customize container startup with optional hooks:

```bash
# In .env

# Run before services start (e.g., file setup)
PRE_STARTUP_CMD="cp .env.example .env"

# Load SQL file on first database creation
DB_SEED_FILE="database/seed.sql"
```

## SSH Configuration

### SSH Keys

The `./ssh` directory is bind-mounted to `~/.ssh` inside the container:

```bash
# Required: Add your public key for SSH access
cat ~/.ssh/id_ed25519.pub >> ssh/authorized_keys

# Optional: Add private key for git operations
cp ~/.ssh/id_ed25519 ssh/
cp ~/.ssh/id_ed25519.pub ssh/
```

**Git Commit Signing:** If `ssh/id_ed25519.pub` exists, commits are automatically signed.

### SSH Host Keys

SSH host keys are automatically:
- Generated on first startup
- Saved to `./data/state/ssh/`
- Restored on subsequent starts
- No more "host key changed" warnings!

## Development Workflow

### Initial Setup

```bash
# 1. Copy files to your project
cp /path/to/devbox/{docker-compose.yml,.env.example} .

# 2. Configure
cp .env.example .env
vim .env  # Set USER_UID, USER_GID, USERNAME, TS_AUTHKEY, etc.

# 3. Setup SSH
mkdir -p ssh
cat ~/.ssh/id_ed25519.pub >> ssh/authorized_keys

# 4. Start
docker compose up --build -d

# 5. SSH in
ssh yourusername@devbox.your-tailnet.ts.net

# 6. Clone your project
cd /workspace
git clone git@github.com:yourusername/your-project.git
cd your-project

# 7. Your tools are ready!
mise use node@20        # Install Node 20
npm install             # Install dependencies
npm run dev             # Start your app (accessible at root path)
```

### Daily Usage

```bash
# Start
docker compose up -d

# SSH in and work
ssh yourusername@devbox.your-tailnet.ts.net
cd /workspace/your-project
git pull
npm run dev

# Stop when done
docker compose stop

# Or fully remove
docker compose down
```

## Multiple Instances

Run multiple devboxes on the same host:

### Using Tailscale (Recommended)

```bash
# Project 1: Frontend (.env)
CONTAINER_NAME=dev-frontend
TS_AUTHKEY=tskey-auth-xxxxx
TS_SUFFIX=your.ts.net
# Accessible at: dev-frontend.your.ts.net

# Project 2: Backend (.env)
CONTAINER_NAME=dev-backend
TS_AUTHKEY=tskey-auth-yyyyy
TS_SUFFIX=your.ts.net
# Accessible at: dev-backend.your.ts.net
```

### Using Local Ports

```bash
# Project 1: Frontend (.env)
CONTAINER_NAME=frontend-dev
SSH_PORT=2200
CADDY_PORT=8400
POSTGRES_PORT=5400

# Project 2: Backend (.env)
CONTAINER_NAME=backend-dev
SSH_PORT=2210
CADDY_PORT=8410
POSTGRES_PORT=5410
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Tailscale (if enabled) or Host Ports              │
│  Entry point with TLS                              │
└─────────────┬───────────────────────────────────────┘
              │
    ┌─────────┴──────────┬──────────────┬──────────┐
    │                    │              │          │
 :22 (SSH)         :443 (HTTPS)    :5432 (PG)     │
    │              or :8443 (HTTP)      │          │
    │                    │              │          │
    v                    v              v          │
┌─────────┐      ┌─────────────┐  ┌──────────┐    │
│   SSH   │      │    Caddy    │  │PostgreSQL│    │
│ Server  │      │   (proxy)   │  │    16    │    │
└─────────┘      └──────┬──────┘  └──────────┘    │
                        │                          │
          ┌─────────────┼──────────────┬──────────┘
          │             │              │
          v             v              v
    ┌──────────┐  ┌─────────┐  ┌─────────────┐
    │   Your   │  │  code-  │  │  pgweb      │
    │   App    │  │ server  │  │  mailhog    │
    │  :3000   │  │  :8080  │  │  filebrowser│
    └──────────┘  └─────────┘  │  status     │
                                └─────────────┘

Persistent Storage:
./data/workspace → /workspace
./data/state     → /state (postgres, ssh keys, tailscale)
./data/snapshots → /snapshots
./ssh            → ~/.ssh
```

## Troubleshooting

### Container won't start

```bash
# View logs
docker compose logs

# Check all services
docker compose ps
```

### Can't SSH in

```bash
# Verify your public key is in ssh/authorized_keys
cat ssh/authorized_keys

# Test SSH with verbose output
ssh -vvv -p 2200 yourusername@localhost

# Check SSH service
docker compose exec devbox pgrep sshd
```

### Tailscale issues

```bash
# Check Tailscale status
docker compose exec devbox sudo tailscale status

# Verify authkey is valid (generate new key if expired)
# https://login.tailscale.com/admin/settings/keys

# Check logs
docker compose logs | grep tailscale
```

### Permission issues

```bash
# Verify UID/GID match your host user
id -u    # Put this in USER_UID
id -g    # Put this in USER_GID

# Check ownership in container
docker compose exec devbox ls -la /workspace
```

### PostgreSQL issues

```bash
# Check PostgreSQL logs
docker compose logs | grep postgres

# Connect manually
docker compose exec devbox psql -U postgres -d devdb

# Database is in ./data/state/postgres - persists across restarts
```

## Repository

- **GitHub:** github.com/jclement/devbox
- **Container Registry:** `docker pull ghcr.io/jclement/devbox:latest`

Pre-built multi-architecture images (amd64, arm64) are automatically built and published to GitHub Container Registry.

## License

MIT

## Contributing

Issues and PRs welcome at github.com/jclement/devbox
