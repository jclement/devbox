#!/bin/bash
# Redis Commander Service (Web UI for Valkey/Redis)
# Provides web-based management interface for Valkey

set -e

SERVICE_NAME="redis-commander"
REDIS_COMMANDER_PORT=8084
REDIS_COMMANDER_PID="/var/run/redis-commander.pid"
REDIS_COMMANDER_LOG="/var/log/redis-commander.log"

case "${1:-start}" in
    install)
        echo "[redis-commander] Installing Redis Commander..."

        # Install redis-commander globally via npm
        npm install -g redis-commander

        echo "[redis-commander] Redis Commander setup complete"
        ;;

    start)
        echo "[redis-commander] Starting Redis Commander..."

        # Check if already running
        if [ -f "$REDIS_COMMANDER_PID" ] && kill -0 $(cat "$REDIS_COMMANDER_PID") 2>/dev/null; then
            echo "[redis-commander] Redis Commander is already running"
            exit 0
        fi

        # Start Redis Commander as a background process
        nohup redis-commander \
            --redis-host localhost \
            --redis-port 6379 \
            --port ${REDIS_COMMANDER_PORT} \
            --address 127.0.0.1 \
            > "$REDIS_COMMANDER_LOG" 2>&1 &

        echo $! > "$REDIS_COMMANDER_PID"

        echo "[redis-commander] Redis Commander started on port ${REDIS_COMMANDER_PORT}"
        ;;

    stop)
        echo "[redis-commander] Stopping Redis Commander..."

        if [ -f "$REDIS_COMMANDER_PID" ]; then
            PID=$(cat "$REDIS_COMMANDER_PID")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID"
                rm -f "$REDIS_COMMANDER_PID"
                echo "[redis-commander] Redis Commander stopped"
            else
                rm -f "$REDIS_COMMANDER_PID"
                echo "[redis-commander] Redis Commander was not running"
            fi
        else
            # Try to find and kill by process name
            pkill -f "redis-commander" 2>/dev/null || true
            echo "[redis-commander] Redis Commander stopped"
        fi
        ;;

    status)
        if [ -f "$REDIS_COMMANDER_PID" ] && kill -0 $(cat "$REDIS_COMMANDER_PID") 2>/dev/null; then
            echo "running"
        else
            # Check if process is running even without PID file
            if pgrep -f "redis-commander" > /dev/null; then
                echo "running"
            else
                echo "stopped"
            fi
        fi
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
