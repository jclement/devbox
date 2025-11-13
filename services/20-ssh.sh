#!/bin/bash
# SSH Service
# Handles OpenSSH server

set -e

SERVICE_NAME="ssh"

case "${1:-start}" in
    install)
        echo "[ssh] Installing SSH server..."

        # SSH is installed from base packages
        # Configure SSH defaults
        mkdir -p /var/run/sshd
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

        echo "[ssh] SSH server configured successfully"
        ;;

    start)
        echo "[ssh] Starting SSH server..."

        # Persist SSH host keys in /state/ssh
        mkdir -p /state/ssh

        # If host keys exist in /state, restore them
        if [ -f /state/ssh/ssh_host_rsa_key ]; then
            echo "[ssh] Restoring SSH host keys from /state/ssh"
            cp -a /state/ssh/ssh_host_* /etc/ssh/
        else
            # Generate keys if they don't exist
            echo "[ssh] Generating SSH host keys..."
            ssh-keygen -A
            # Save them to /state for persistence
            echo "[ssh] Saving SSH host keys to /state/ssh"
            cp -a /etc/ssh/ssh_host_* /state/ssh/
        fi

        exec /usr/sbin/sshd -D -e
        ;;

    stop)
        echo "[ssh] Stopping SSH server..."
        killall sshd || true
        ;;

    status)
        pgrep -x sshd >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
