#!/bin/bash
# Redis Commander Service (Web UI for Valkey/Redis)
# Provides web-based management interface for Valkey

set -e

SERVICE_NAME="redis-commander"
REDIS_COMMANDER_PORT=8084

case "${1:-start}" in
    install)
        echo "[redis-commander] Installing Redis Commander..."

        # Redis Commander runs as a Docker container
        # Dependencies are handled by Docker

        echo "[redis-commander] Redis Commander setup complete"
        ;;

    start)
        echo "[redis-commander] Starting Redis Commander..."

        # Start Redis Commander in Docker
        docker run -d \
            --name redis-commander \
            --restart unless-stopped \
            -p 127.0.0.1:${REDIS_COMMANDER_PORT}:8081 \
            -e REDIS_HOSTS=local:localhost:6379 \
            --network host \
            ghcr.io/joeferner/redis-commander:latest

        echo "[redis-commander] Redis Commander started on port ${REDIS_COMMANDER_PORT}"
        ;;

    stop)
        echo "[redis-commander] Stopping Redis Commander..."
        docker stop redis-commander 2>/dev/null || true
        docker rm redis-commander 2>/dev/null || true
        ;;

    status)
        if docker ps --filter "name=redis-commander" --filter "status=running" | grep -q redis-commander; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
