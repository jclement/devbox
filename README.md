# DevBox - Docker Compose Edition

A complete, portable development environment in a single container. Clone, configure, and code - anywhere.

## Vision

Imagine you want to start a new project or work on an existing one. You:

1. Copy `docker-compose.yml` and `.env-sample` to your project folder
2. Rename `.env-sample` to `.env` and customize (or use defaults)
3. Run `docker-compose up -d`
4. SSH into your personal dev environment on your Tailscale network
5. Clone your repo and start coding

Your devbox appears on your Tailnet with:
- SSH access (with your keys and agent forwarding)
- VS Code in the browser (code-server)
- PostgreSQL with web interface (pgweb)
- Email testing (MailHog)
- Your development service at the root path

Everything is configured, everything works, and you can access it from anywhere on your Tailnet.

## What's Inside

### Development Tools
- **mise** - Universal version manager (Node, Python, Ruby, Go, etc.)
- **Claude Code** - AI-powered coding assistant
- **cloudflared** - Cloudflare tunnel client
- **Tailscale** - Zero-config VPN for secure remote access
- **git**, **lazygit** - Version control
- **vim**, **helix** - Terminal editors
- **code-server** - VS Code in your browser

### Shell & Prompt
- **fish** - Friendly interactive shell (default)
- **bash** - Available as fallback
- **starship** - Beautiful cross-shell prompt with git integration

### Database & Services
- **PostgreSQL 16** - Production-ready database
- **pgweb** - Web-based PostgreSQL admin interface
- **MailHog** - SMTP testing server with web UI

### Networking
- **Caddy** - Modern reverse proxy with automatic HTTPS
- **SSH Server** - Secure remote access
- Automatic service routing and TLS termination

## Quick Start

### 1. Setup

```bash
# Copy configuration template
cp .env-sample .env

# Edit .env with your details
# At minimum, set:
#   - USER_UID and USER_GID (run: id -u && id -g)
#   - USERNAME (your username)
#   - TS_AUTHKEY (from https://login.tailscale.com/admin/settings/keys)
#   - TS_HOSTNAME (e.g., "devbox" or "dev-myproject")
vim .env
```

### 2. Start

```bash
# Build and start in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

### 3. Access

**Tailscale Mode:**
```bash
# SSH into your devbox
ssh yourusername@your-hostname

# Access services
https://your-hostname/              # Your dev service
https://your-hostname/code/         # VS Code
https://your-hostname/db/           # PostgreSQL admin
https://your-hostname/mail/         # Email testing

# Connect to PostgreSQL
psql -h your-hostname -U postgres -d devdb
```

**Local Mode (TS_AUTHKEY not set):**
```bash
# SSH (port = 2200 + PORT_OFFSET)
ssh -p 2200 yourusername@localhost

# Access services (port = 8400 + PORT_OFFSET)
http://localhost:8400/              # Your dev service
http://localhost:8400/code/         # VS Code
http://localhost:8400/db/           # PostgreSQL admin
http://localhost:8400/mail/         # Email testing

# Connect to PostgreSQL (port = 5400 + PORT_OFFSET)
psql -h localhost -p 5400 -U postgres -d devdb
```

## Configuration Modes

### Tailscale Mode (Recommended for Remote Access)

Perfect for accessing your devbox from anywhere:

```bash
# In .env
TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxxxxx
TS_HOSTNAME=dev-myproject
TS_FULL_HOSTNAME=dev-myproject.your-tailnet.ts.net
```

**Benefits:**
- Secure access from anywhere on your Tailnet
- Automatic TLS certificates
- No port forwarding needed
- No exposed ports on host

**Requirements:**
- Tailscale account and auth key
- `privileged: true` in docker-compose.yml
- May not work on macOS Docker Desktop (use Local mode)

### Local Mode (Port Forwarding)

Perfect for local development:

```bash
# In .env
TS_AUTHKEY=            # Leave empty
PORT_OFFSET=0          # Use 0-99 for multiple instances
```

**Benefits:**
- Works on all platforms including macOS
- Simple setup - no external dependencies
- Multiple instances on same host (use different offsets)

**Port Calculation:**
- SSH: 2200 + PORT_OFFSET
- Web: 8400 + PORT_OFFSET
- PostgreSQL: 5400 + PORT_OFFSET

## Workspace Persistence

Your code lives in a Docker named volume called `{CONTAINER_NAME}-workspace`:

```bash
# View your workspace
docker-compose exec devbox ls -la /workspace

# Backup your workspace
docker run --rm -v devbox-workspace:/workspace -v $(pwd):/backup \
  ubuntu tar czf /backup/workspace-backup.tar.gz -C /workspace .

# Restore workspace
docker run --rm -v devbox-workspace:/workspace -v $(pwd):/backup \
  ubuntu tar xzf /backup/workspace-backup.tar.gz -C /workspace
```

## Database Management

### Snapshots

Save your database state to the host:

```bash
# Inside the container
snapshot                           # Creates timestamped snapshot in .snapshots/
snapshot mydata                    # Creates .snapshots/mydata.sql

# Restore from snapshot
restore mydata                     # Restores from .snapshots/mydata.sql
restore                            # Shows available snapshots
```

Snapshots are stored in `.snapshots/` (configurable via `SNAPSHOTS_DIR`) and persist on your host.

### Seed on Startup

```bash
# In .env
DB_SEED_FILE=database/seed.sql

# File should be in /workspace/database/seed.sql
# Will load automatically on first database initialization
```

## Lifecycle Hooks

Customize container startup with optional hooks:

```bash
# In .env

# Run before services start (e.g., file setup)
PRE_STARTUP_CMD="cp .env.example .env"

# Load SQL file on first database creation
DB_SEED_FILE="database/seed.sql"

# Run after services are ready (e.g., install dependencies)
POST_STARTUP_CMD="npm install && npm run dev"
```

## Development Workflow

### Initial Setup

```bash
# 1. Copy files to your project
cp /path/to/devbox/simple/{docker-compose.yml,.env-sample} .

# 2. Configure
cp .env-sample .env
vim .env

# 3. Start
docker-compose up -d

# 4. SSH in
ssh -p 2200 yourusername@localhost   # Local mode
# or
ssh yourusername@your-hostname        # Tailscale mode

# 5. Clone your project
cd /workspace
git clone https://github.com/yourusername/your-project.git
cd your-project

# 6. Your tools are ready!
mise use node@20        # Install Node 20
npm install             # Install dependencies
npm run dev             # Start your app
```

### Daily Usage

```bash
# Start
docker-compose up -d

# SSH in and work
ssh -p 2200 yourusername@localhost
cd /workspace/your-project
git pull
npm run dev

# Stop when done
docker-compose stop

# Or fully remove
docker-compose down
```

## SSH Agent Forwarding

Your SSH and GPG agents are automatically forwarded from the host:

**Linux:**
- Works out of the box via socket mounting

**macOS Docker Desktop:**
```bash
# On host, run this bridge (in another terminal):
socat TCP-LISTEN:52222,reuseaddr,fork UNIX-CLIENT:$SSH_AUTH_SOCK

# In .env
SSH_SOCAT_PORT=52222
```

Inside the container, your keys work seamlessly:
```bash
# Git operations use your SSH key
git clone git@github.com:user/repo.git

# Commits are signed with your SSH key
git commit -m "Signed automatically"

# SSH to other servers
ssh production-server
```

## Multiple Instances

Run multiple devboxes on the same host:

```bash
# Project 1: Frontend
# .env
CONTAINER_NAME=frontend-dev
PORT_OFFSET=0           # SSH: 2200, Web: 8400, PG: 5400

# Project 2: Backend
# .env
CONTAINER_NAME=backend-dev
PORT_OFFSET=10          # SSH: 2210, Web: 8410, PG: 5410

# Start both
docker-compose up -d
```

Or use Tailscale mode with unique hostnames:
```bash
# Project 1
TS_HOSTNAME=dev-frontend

# Project 2
TS_HOSTNAME=dev-backend
```

## mise Integration

mise is pre-installed and auto-activated in both fish and bash shells:

```bash
# Install tools from .mise.toml or .tool-versions
mise use node@20 python@3.11 ruby@3.2

# Tools are automatically installed on container start if config exists
# Create a .mise.toml in /workspace and restart

# Manual install
mise install

# List installed tools
mise list
```

## Advanced Usage

### Custom Service Port

If your app runs on a non-standard port:

```bash
# In .env
DEV_SERVICE_PORT=8080

# Your app at http://localhost:8400/ will proxy to container:8080
```

### Build from Source

```bash
# Build custom image
docker-compose build

# Use specific tag
IMAGE_NAME=myusername/devbox:custom docker-compose build
```

### Persistent Tailscale State

By default, Tailscale state is ephemeral. To persist it:

```yaml
# In docker-compose.yml, change:
volumes:
  - /var/lib/tailscale

# To:
volumes:
  - tailscale-state:/var/lib/tailscale
```

## Troubleshooting

### Container won't start

```bash
# View logs
docker-compose logs

# Check specific service
docker-compose exec devbox supervisorctl status
```

### Can't SSH in

```bash
# Verify your public key is in ~/.ssh/*.pub on host
ls -la ~/.ssh/*.pub

# Check SSH service
docker-compose exec devbox supervisorctl status ssh

# Test connection
ssh -vvv -p 2200 yourusername@localhost
```

### Tailscale issues

```bash
# Check Tailscale status
docker-compose exec devbox tailscale status

# Verify authkey is valid
# Generate new key at: https://login.tailscale.com/admin/settings/keys

# macOS Docker Desktop: Tailscale may not work due to networking
# Solution: Use Local mode instead
```

### Permission issues

```bash
# Verify UID/GID match
id -u    # Put this in USER_UID
id -g    # Put this in USER_GID

# Check ownership
docker-compose exec devbox ls -la /workspace
```

### PostgreSQL won't start

```bash
# Check logs
docker-compose exec devbox supervisorctl tail postgresql

# Database is ephemeral - just recreate container
docker-compose down
docker-compose up -d
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
│   SSH   │      │    Caddy    │  │ PostgreSQL│   │
│ Server  │      │   (proxy)   │  │    16     │    │
└─────────┘      └──────┬──────┘  └──────────┘    │
                        │                          │
          ┌─────────────┼─────────────┐           │
          │             │             │           │
          v             v             v           v
    ┌──────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
    │   Your   │  │  code-  │  │  pgweb  │  │MailHog  │
    │   App    │  │ server  │  │         │  │         │
    │  :3000   │  │  :8080  │  │  :8081  │  │  :8025  │
    └──────────┘  └─────────┘  └─────────┘  └─────────┘
```

## Comparison with Original

| Feature | Original (./start_devbox) | Docker Compose |
|---------|--------------------------|----------------|
| **Setup** | Interactive wizard | Edit .env file |
| **Configuration** | .devbox file per project | .env + docker-compose.yml |
| **Portability** | Requires scripts | Just 2 files |
| **Multiple instances** | Manual container naming | Built-in with compose |
| **Environment vars** | Shell script | Native .env support |
| **Service management** | Docker CLI | docker-compose commands |
| **Best for** | Quick local setup | Production, teams, CI/CD |

## Repository

This is designed to be published to:
- **GitHub:** github.com/jclement/devbox
- **Docker Hub:** docker pull jclement/devbox:latest

## Future Enhancements

- [ ] Pre-built multi-arch images (amd64, arm64)
- [ ] GitHub Actions for automated builds
- [ ] Additional database options (MySQL, Redis)
- [ ] Language-specific variants (node-devbox, python-devbox, etc.)
- [ ] Kubernetes/Helm deployment option
- [ ] devcontainer.json support for VS Code Remote Containers

## License

MIT

## Contributing

Issues and PRs welcome at github.com/jclement/devbox
