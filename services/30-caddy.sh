#!/bin/bash
# Caddy Service
# Handles Caddy web server/reverse proxy

set -e

SERVICE_NAME="caddy"

case "${1:-start}" in
    install)
        echo "[caddy] Installing Caddy..."

        apt-get update
        apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update
        apt-get install -y caddy
        rm -rf /var/lib/apt/lists/*

        echo "[caddy] Caddy installed successfully"
        ;;

    start)
        echo "[caddy] Generating Caddyfile..."

        # Get SERVICE_ROOT from environment or /var/run/devbox
        if [ -z "$SERVICE_ROOT" ] && [ -f /var/run/devbox/service_root ]; then
            SERVICE_ROOT=$(cat /var/run/devbox/service_root)
        fi
        SERVICE_ROOT="${SERVICE_ROOT:-/devbox/}"
        # Ensure SERVICE_ROOT ends with /
        [[ "$SERVICE_ROOT" != */ ]] && SERVICE_ROOT="${SERVICE_ROOT}/"

        # Generate Caddyfile based on PASSWORD setting
        if [ -n "$PASSWORD" ]; then
            PASSWORD_HASH=$(caddy hash-password --plaintext "$PASSWORD")
            cat > /etc/caddy/Caddyfile <<EOF
# WARNING: This file is auto-generated on every startup. Do not edit manually.
# To customize, modify services/30-caddy.sh

:8443 {
    basicauth {
        ${USERNAME} $PASSWORD_HASH
    }

    handle_path ${SERVICE_ROOT}code/* {
        reverse_proxy localhost:8080
    }

    handle_path ${SERVICE_ROOT}db/* {
        reverse_proxy localhost:8081
    }

    handle_path ${SERVICE_ROOT}valkey/* {
        reverse_proxy localhost:8084
    }

    handle_path ${SERVICE_ROOT}mail/* {
        reverse_proxy localhost:8025
    }

    handle_path ${SERVICE_ROOT}files/* {
        reverse_proxy localhost:8083
    }

    handle ${SERVICE_ROOT}* {
        uri strip_prefix ${SERVICE_ROOT%/}
        reverse_proxy localhost:8082
    }

    handle /* {
        reverse_proxy localhost:{\$DEV_SERVICE_PORT:3000}
    }

    log {
        output stdout
        format console
    }
}
EOF
        else
            cat > /etc/caddy/Caddyfile <<EOF
# WARNING: This file is auto-generated on every startup. Do not edit manually.
# To customize, modify services/30-caddy.sh

:8443 {
    handle_path ${SERVICE_ROOT}code/* {
        reverse_proxy localhost:8080
    }

    handle_path ${SERVICE_ROOT}db/* {
        reverse_proxy localhost:8081
    }

    handle_path ${SERVICE_ROOT}valkey/* {
        reverse_proxy localhost:8084
    }

    handle_path ${SERVICE_ROOT}mail/* {
        reverse_proxy localhost:8025
    }

    handle_path ${SERVICE_ROOT}files/* {
        reverse_proxy localhost:8083
    }

    handle ${SERVICE_ROOT}* {
        uri strip_prefix ${SERVICE_ROOT%/}
        reverse_proxy localhost:8082
    }

    handle /* {
        reverse_proxy localhost:{\$DEV_SERVICE_PORT:3000}
    }

    log {
        output stdout
        format console
    }
}
EOF
        fi

        echo "[caddy] Starting Caddy..."
        exec /usr/bin/caddy run --config /etc/caddy/Caddyfile
        ;;

    stop)
        echo "[caddy] Stopping Caddy..."
        killall caddy || true
        ;;

    status)
        pgrep -x caddy >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
