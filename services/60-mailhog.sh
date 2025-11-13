#!/bin/bash
# MailHog Service  
# Email testing SMTP server

set -e

SERVICE_NAME="mailhog"

case "${1:-start}" in
    install)
        echo "[mailhog] Installing MailHog..."
        wget https://github.com/mailhog/MailHog/releases/download/v1.0.1/MailHog_linux_amd64
        mv MailHog_linux_amd64 /usr/local/bin/mailhog
        chmod +x /usr/local/bin/mailhog
        echo "[mailhog] MailHog installed successfully"
        ;;

    start)
        echo "[mailhog] Starting MailHog..."
        exec /usr/local/bin/mailhog -smtp-bind-addr 127.0.0.1:1025 -ui-bind-addr 127.0.0.1:8025 -api-bind-addr 127.0.0.1:8026
        ;;

    stop)
        echo "[mailhog] Stopping MailHog..."
        killall mailhog || true
        ;;

    status)
        pgrep -x mailhog >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
