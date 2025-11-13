#!/bin/bash
# Tailscale Service
# VPN networking

set -e

SERVICE_NAME="tailscale"

case "${1:-start}" in
    install)
        echo "[tailscale] Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
        echo "[tailscale] Tailscale installed successfully"
        ;;

    start)
        # Check if Tailscale is configured
        if [ ! -f "/etc/secrets/ts_authkey" ]; then
            echo "[tailscale] Not configured (no auth key), exiting"
            exec sleep infinity
        fi

        TS_AUTHKEY=$(cat /etc/secrets/ts_authkey)

        echo "[tailscale] Starting Tailscale daemon..."
        mkdir -p /state/tailscale
        /usr/sbin/tailscaled --state=/state/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
        sleep 2

        # Determine hostname
        if [ -n "$TS_HOSTNAME" ]; then
            TS_HOST="${TS_HOSTNAME}"
        elif [ -n "$CONTAINER_NAME" ]; then
            TS_HOST="${CONTAINER_NAME}"
        else
            TS_HOST="${COMPOSE_PROJECT_NAME:-devbox}"
        fi

        echo "[tailscale] Connecting as ${TS_HOST}..."
        tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOST}" --accept-routes

        # Clear old serve config
        tailscale serve --tcp 22 off 2>/dev/null || true
        tailscale serve --tcp 5432 off 2>/dev/null || true
        tailscale serve --https 443 off 2>/dev/null || true

        # Wait for other services to be up
        sleep 3

        # Configure serve
        echo "[tailscale] Configuring serve..."
        tailscale serve --bg --tcp 22 tcp://localhost:22
        tailscale serve --bg --https 443 http://localhost:8443
        tailscale serve --bg --tcp 5432 tcp://localhost:5432

        echo "[tailscale] Ready"
        exec sleep infinity
        ;;

    stop)
        echo "[tailscale] Stopping Tailscale..."
        tailscale down || true
        killall tailscaled || true
        ;;

    status)
        pgrep -x tailscaled >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
