#!/bin/bash
# Valkey Service (Redis-compatible)
# Handles Valkey in-memory data store

set -e

SERVICE_NAME="valkey"

case "${1:-start}" in
    install)
        echo "[valkey] Installing Valkey..."

        # Install Valkey (Redis-compatible) and redis-cli
        apt-get update
        apt-get install -y valkey
        rm -rf /var/lib/apt/lists/*

        echo "[valkey] Valkey installed successfully"
        ;;

    start)
        echo "[valkey] Starting Valkey..."

        # Create valkey user if it doesn't exist
        if ! id valkey >/dev/null 2>&1; then
            useradd -r -s /bin/false -d /var/lib/valkey valkey
        fi

        # Configure Valkey to bind to localhost only (Tailscale forwards if needed)
        mkdir -p /etc/valkey
        cat > /etc/valkey/valkey.conf <<EOF
# Valkey configuration (auto-generated)
bind 127.0.0.1 ::1
port 6379
daemonize no
supervised systemd
dir /var/lib/valkey
logfile ""
EOF

        # Create data directory
        mkdir -p /var/lib/valkey
        chown valkey:valkey /var/lib/valkey

        # Start Valkey
        exec su - valkey -s /bin/sh -c "valkey-server /etc/valkey/valkey.conf"
        ;;

    stop)
        echo "[valkey] Stopping Valkey..."
        killall valkey-server || true
        ;;

    status)
        pgrep -x valkey-server >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
