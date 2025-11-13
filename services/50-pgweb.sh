#!/bin/bash
# PgWeb Service
# PostgreSQL web interface

set -e

SERVICE_NAME="pgweb"

case "${1:-start}" in
    install)
        echo "[pgweb] Installing pgweb..."
        wget https://github.com/sosedoff/pgweb/releases/download/v0.15.0/pgweb_linux_amd64.zip
        unzip pgweb_linux_amd64.zip
        mv pgweb_linux_amd64 /usr/local/bin/pgweb
        chmod +x /usr/local/bin/pgweb
        rm pgweb_linux_amd64.zip
        echo "[pgweb] pgweb installed successfully"
        ;;

    start)
        echo "[pgweb] Starting pgweb..."

        # Wait for PostgreSQL to be ready
        for i in {1..30}; do
            if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
                echo "[pgweb] PostgreSQL is ready"
                break
            fi
            echo "[pgweb] Waiting for PostgreSQL... ($i/30)"
            sleep 1
        done

        exec /usr/local/bin/pgweb --bind=127.0.0.1 --listen=8081 --host=localhost --user=postgres --pass=${POSTGRES_PASSWORD:-postgres} --db=${POSTGRES_DB:-devdb} --lock-session
        ;;

    stop)
        echo "[pgweb] Stopping pgweb..."
        killall pgweb || true
        ;;

    status)
        pgrep -x pgweb >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
