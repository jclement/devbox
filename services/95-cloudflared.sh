#!/bin/bash
# Cloudflare Tunnel Service
# Expose services via Cloudflare tunnel

set -e

SERVICE_NAME="cloudflared"

case "${1:-start}" in
    install)
        echo "[cloudflared] Installing Cloudflared..."
        ARCH=$(dpkg --print-architecture)
        curl -L --output cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
        dpkg -i cloudflared.deb
        rm cloudflared.deb
        echo "[cloudflared] Cloudflared installed successfully"
        ;;

    start)
        # Check if Cloudflare Tunnel is configured
        if [ ! -f "/etc/secrets/cf_tunnel_token" ]; then
            echo "[cloudflared] Not configured (no tunnel token), exiting"
            exec sleep infinity
        fi

        CF_TUNNEL_TOKEN=$(cat /etc/secrets/cf_tunnel_token)

        echo "[cloudflared] Starting Cloudflare Tunnel..."
        exec /usr/bin/cloudflared tunnel run --token ${CF_TUNNEL_TOKEN}
        ;;

    stop)
        echo "[cloudflared] Stopping Cloudflare Tunnel..."
        killall cloudflared || true
        ;;

    status)
        pgrep -x cloudflared >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
