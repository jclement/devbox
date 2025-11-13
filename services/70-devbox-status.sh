#!/bin/bash
# DevBox Status Service
# Web dashboard for container status

set -e

SERVICE_NAME="devbox-status"

case "${1:-start}" in
    install)
        echo "[devbox-status] Pre-built binary already installed"
        # Binary is copied directly into the image during build
        ;;

    start)
        echo "[devbox-status] Starting status dashboard..."
        exec /opt/devbox-status/devbox-status
        ;;

    stop)
        echo "[devbox-status] Stopping status dashboard..."
        killall devbox-status || true
        ;;

    status)
        pgrep -x devbox-status >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
