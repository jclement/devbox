#!/bin/bash
# Redis Commander Service (Web UI for Valkey/Redis)
# Provides web-based management interface for Valkey

set -e

SERVICE_NAME="redis-commander"
REDIS_COMMANDER_PORT=8084

case "${1:-start}" in
    install)
        echo "[redis-commander] Installing Redis Commander..."

        # Install Node.js and npm
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        rm -rf /var/lib/apt/lists/*

        # Install redis-commander globally via npm
        npm install -g redis-commander

        echo "[redis-commander] Redis Commander setup complete"
        ;;

    start)
        echo "[redis-commander] Starting Redis Commander..."

        # Wait for Valkey to be ready
        for i in {1..30}; do
            if redis-cli -h localhost -p 6379 ping >/dev/null 2>&1; then
                echo "[redis-commander] Valkey is ready"
                break
            fi
            echo "[redis-commander] Waiting for Valkey... ($i/30)"
            sleep 1
        done

        # Start Redis Commander in foreground (s6-overlay expects this)
        exec redis-commander \
            --redis-host localhost \
            --redis-port 6379 \
            --port ${REDIS_COMMANDER_PORT} \
            --address 127.0.0.1
        ;;

    stop)
        echo "[redis-commander] Stopping Redis Commander..."
        killall node || true
        ;;

    status)
        pgrep -f "redis-commander" >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
