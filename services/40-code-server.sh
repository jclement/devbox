#!/bin/bash
# Code-Server Service
# Handles VS Code in the browser

set -e

SERVICE_NAME="code-server"

case "${1:-start}" in
    install)
        echo "[code-server] Installing code-server..."
        curl -fsSL https://code-server.dev/install.sh | sh
        echo "[code-server] code-server installed successfully"
        ;;

    start)
        echo "[code-server] Starting code-server..."

        # Configure default extensions and settings if not already done
        TARGET_USERNAME=${USERNAME:-devbox}
        USER_HOME="/home/${TARGET_USERNAME}"
        CONFIG_DIR="${USER_HOME}/.local/share/code-server"

        if [ ! -f "${CONFIG_DIR}/.configured" ]; then
            echo "[code-server] First run - configuring defaults..."

            # Install default extensions from environment variable
            if [ -n "${VSCODE_DEFAULT_EXTENSIONS:-}" ]; then
                echo "[code-server] Installing default extensions..."
                IFS=';' read -ra EXTENSIONS <<< "${VSCODE_DEFAULT_EXTENSIONS}"
                for ext in "${EXTENSIONS[@]}"; do
                    if [ -n "$ext" ]; then
                        echo "[code-server]   Installing $ext..."
                        # Use --force for github extensions that might need it
                        if [[ "$ext" == github.* ]]; then
                            su - ${TARGET_USERNAME} -c "code-server --install-extension $ext --force" || true
                        else
                            su - ${TARGET_USERNAME} -c "code-server --install-extension $ext" || true
                        fi
                    fi
                done
            fi

            # Configure default settings
            echo "[code-server] Configuring default settings..."
            mkdir -p ${CONFIG_DIR}/User

            # Use theme from environment variable
            THEME="${VSCODE_DEFAULT_THEME:-Default Dark+}"
            cat > ${CONFIG_DIR}/User/settings.json << EOF
{
    "workbench.colorTheme": "${THEME}",
    "workbench.startupEditor": "none",
    "telemetry.telemetryLevel": "off"
}
EOF

            chown -R ${TARGET_USERNAME}:${TARGET_USERNAME} ${CONFIG_DIR}

            # Mark as configured
            touch ${CONFIG_DIR}/.configured
            chown ${TARGET_USERNAME}:${TARGET_USERNAME} ${CONFIG_DIR}/.configured

            echo "[code-server] Configuration complete"
        else
            echo "[code-server] Using existing configuration"
        fi

        exec su - ${USERNAME} -c "/usr/bin/code-server --bind-addr 127.0.0.1:8080 /workspace"
        ;;

    stop)
        echo "[code-server] Stopping code-server..."
        killall node || true
        ;;

    status)
        pgrep -f code-server >/dev/null && echo "running" || echo "stopped"
        ;;

    *)
        echo "Usage: $0 {install|start|stop|status}"
        exit 1
        ;;
esac
