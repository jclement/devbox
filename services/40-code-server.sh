#!/bin/bash
# Code-Server Service
# Handles VS Code in the browser

set -e

SERVICE_NAME="code-server"

case "${1:-start}" in
    install)
        echo "[code-server] Installing code-server..."
        curl -fsSL https://code-server.dev/install.sh | sh
        echo "[code-server] code-server installed successfully"
        ;;

    start)
        echo "[code-server] Starting code-server..."
        exec su - ${USERNAME} -c "/usr/bin/code-server --bind-addr 127.0.0.1:8080 /workspace"
        ;;

    stop)
        echo "[code-server] Stopping code-server..."
        killall node || true
        ;;

    status)
        pgrep -f code-server >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
