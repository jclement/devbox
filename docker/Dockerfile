# Build stage for devbox-status
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY devbox-status/go.mod devbox-status/go.sum ./
RUN go mod download
COPY devbox-status/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -o devbox-status .

# Main image
FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set locale to avoid warnings
RUN apt-get update && apt-get install -y locales \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install base dependencies (minimal set needed for service scripts)
RUN apt-get update && apt -y upgrade && apt-get install -y \
    curl \
    wget \
    git \
    sudo \
    openssh-server \
    vim \
    zsh \
    tmux \
    ca-certificates \
    gnupg \
    gnupg-agent \
    pinentry-curses \
    lsb-release \
    xz-utils \
    build-essential \
    unzip \
    ripgrep \
    magic-wormhole \
    fzf \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Install s6-overlay for service management
ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
    && rm -f /tmp/s6-overlay*.tar.xz

# Install Helix editor (architecture-aware)
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then \
        HELIX_ARCH="x86_64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        HELIX_ARCH="aarch64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
    && wget https://github.com/helix-editor/helix/releases/download/24.07/helix-24.07-${HELIX_ARCH}-linux.tar.xz \
    && tar xf helix-24.07-${HELIX_ARCH}-linux.tar.xz \
    && mv helix-24.07-${HELIX_ARCH}-linux/hx /usr/local/bin/ \
    && rm -rf helix-24.07-${HELIX_ARCH}-linux helix-24.07-${HELIX_ARCH}-linux.tar.xz

# Install mise system-wide
RUN curl https://mise.run | sh && mv ~/.local/bin/mise /usr/local/bin/mise

# Install lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit lazygit.tar.gz

# Create devbox user (UID/GID 9999, will be modified at runtime)
RUN set -e; \
    EXISTING_GROUP=$(getent group 9999 | cut -d: -f1 || true); \
    if [ -n "$EXISTING_GROUP" ]; then \
        echo "GID 9999 exists as '$EXISTING_GROUP', reusing it"; \
        GROUP_NAME="$EXISTING_GROUP"; \
    else \
        groupadd -g 9999 devbox; \
        GROUP_NAME="devbox"; \
    fi; \
    useradd -m -u 9999 -g $GROUP_NAME -s /bin/zsh devbox || \
    (echo "UID 9999 exists, modifying existing user" && usermod -l devbox -d /home/devbox -g $GROUP_NAME -s /bin/zsh $(id -un 9999)); \
    echo "devbox ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devbox; \
    chmod 0440 /etc/sudoers.d/devbox

# Create workspace directory
RUN mkdir -p /workspace \
    && chown 9999:9999 /workspace

# Switch to devbox user
USER devbox
WORKDIR /home/devbox

# Copy dotfiles to /etc/dotfiles (will be copied to ~/ on first run)
COPY dotfiles /etc/dotfiles

# Switch back to root for service installation
USER root

# Copy service scripts to /opt/services (not in PATH - these are for s6-overlay)
COPY services /opt/services
RUN chmod +x /opt/services/*.sh

# Copy helper scripts to /opt/scripts and add to PATH (user-facing tools)
COPY scripts /opt/scripts
RUN chmod +x /opt/scripts/*
ENV PATH="/opt/scripts:${PATH}"

# Copy devbox-status binary from builder stage
COPY --from=builder /build/devbox-status /opt/devbox-status/devbox-status

# Create state directory for persistent system data
RUN mkdir -p /state/tailscale /state/ssh /state/postgres

# Install all services - each service script handles its own install logic
RUN for script in /opt/services/*.sh; do \
        name=$(basename $script .sh); \
        echo "Installing $name..."; \
        $script install || true; \
    done

# Caddyfile is now created by caddy install script

# Create s6-overlay service directories
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d

# Set up s6 services (all services in /opt/services/ are auto-configured)
# Initialization and secrets are handled in entrypoint.sh before s6 starts
RUN for service in /opt/services/*.sh; do \
        name=$(basename $service .sh); \
        mkdir -p /etc/s6-overlay/s6-rc.d/$name; \
        echo "longrun" > /etc/s6-overlay/s6-rc.d/$name/type; \
        printf '#!/command/with-contenv bash\nexec %s start\n' $service > /etc/s6-overlay/s6-rc.d/$name/run; \
        chmod +x /etc/s6-overlay/s6-rc.d/$name/run; \
        touch /etc/s6-overlay/s6-rc.d/user/contents.d/$name; \
    done

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports (though Tailscale will handle the actual serving)
EXPOSE 22 443 5432

# Use our entrypoint which calls /init
ENTRYPOINT ["/entrypoint.sh"]
