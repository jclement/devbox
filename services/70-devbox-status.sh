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

        # Get SERVICE_ROOT from environment or /var/run/devbox
        if [ -z "$SERVICE_ROOT" ] && [ -f /var/run/devbox/service_root ]; then
            export SERVICE_ROOT=$(cat /var/run/devbox/service_root)
        fi

        # Get other env vars from /var/run/devbox if not set
        if [ -z "$POSTGRES_USER" ] && [ -f /var/run/devbox/postgres_user ]; then
            export POSTGRES_USER=$(cat /var/run/devbox/postgres_user)
        fi
        if [ -z "$POSTGRES_DB" ] && [ -f /var/run/devbox/postgres_db ]; then
            export POSTGRES_DB=$(cat /var/run/devbox/postgres_db)
        fi

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
