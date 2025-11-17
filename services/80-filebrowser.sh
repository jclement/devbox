#!/bin/bash
# FileBrowser Service
# Web-based file manager

set -e

SERVICE_NAME="filebrowser"

case "${1:-start}" in
    install)
        echo "[filebrowser] Installing FileBrowser..."
        curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
        echo "[filebrowser] FileBrowser installed successfully"
        ;;

    start)
        echo "[filebrowser] Starting file browser..."
        exec su - ${USERNAME} -c "/usr/local/bin/filebrowser --address 127.0.0.1 --port 8083 --root /workspace --noauth --baseurl ${SERVICE_ROOT}files"
        ;;

    stop)
        echo "[filebrowser] Stopping file browser..."
        killall filebrowser || true
        ;;

    status)
        pgrep -x filebrowser >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
