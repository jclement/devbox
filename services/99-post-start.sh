#!/bin/bash
# Post-Start Hook Service
# Runs the post-start hook after all services have started

set -e

SERVICE_NAME="post-start"

case "${1:-start}" in
    install)
        # No installation needed for this service
        echo "[post-start] No installation required"
        ;;

    start)
        # Run post-start hook if it exists and is executable
        POST_START_HOOK="${POST_START_HOOK:-/opt/hooks/post_start.sh}"
        if [ -x "$POST_START_HOOK" ]; then
            echo "[post-start] Running post-start hook..."
            # Use with-contenv to ensure environment variables are available
            /command/with-contenv bash -c "$POST_START_HOOK" || true
        else
            echo "[post-start] No executable post-start hook found at $POST_START_HOOK"
        fi

        # This is a oneshot service - exit after running
        exit 0
        ;;

    stop)
        # Nothing to stop
        exit 0
        ;;

    status)
        echo "[post-start] Oneshot service - no persistent status"
        exit 0
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
