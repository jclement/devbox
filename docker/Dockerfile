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

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    sudo \
    openssh-server \
    vim \
    ca-certificates \
    gnupg \
    gnupg-agent \
    pinentry-curses \
    scdaemon \
    lsb-release \
    supervisor \
    build-essential \
    unzip \
    fzf \
    fish \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Install starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Install PostgreSQL 16
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get install -y postgresql-16 postgresql-contrib-16 \
    && rm -rf /var/lib/apt/lists/*

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

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install cloudflared (architecture-aware)
RUN ARCH=$(dpkg --print-architecture) \
    && curl -L --output cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb" \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb

# Install Caddy
RUN apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# Install mise system-wide
RUN curl https://mise.run | sh && mv ~/.local/bin/mise /usr/local/bin/mise

# Install pgweb (PostgreSQL web interface)
RUN wget https://github.com/sosedoff/pgweb/releases/download/v0.15.0/pgweb_linux_amd64.zip \
    && unzip pgweb_linux_amd64.zip \
    && mv pgweb_linux_amd64 /usr/local/bin/pgweb \
    && chmod +x /usr/local/bin/pgweb \
    && rm pgweb_linux_amd64.zip

# Install MailHog
RUN wget https://github.com/mailhog/MailHog/releases/download/v1.0.1/MailHog_linux_amd64 \
    && mv MailHog_linux_amd64 /usr/local/bin/mailhog \
    && chmod +x /usr/local/bin/mailhog

# Install lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit lazygit.tar.gz

# Install filebrowser (web file manager)
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Install Go (needed to build devbox-status)
RUN wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz \
    && rm go1.21.6.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Install Node.js LTS (using NodeSource repository)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Configure SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Create devbox user with fixed UID/GID (will be changed at runtime)
# Using 9999:9999 as placeholder - unlikely to conflict, entrypoint will adjust to match host user
RUN set -e; \
    # Handle potential GID conflict gracefully
    EXISTING_GROUP=$(getent group 9999 | cut -d: -f1 || true); \
    if [ -n "$EXISTING_GROUP" ]; then \
        echo "GID 9999 exists as '$EXISTING_GROUP', reusing it"; \
        GROUP_NAME="$EXISTING_GROUP"; \
    else \
        groupadd -g 9999 devbox; \
        GROUP_NAME="devbox"; \
    fi; \
    # Create user with fish as default shell
    useradd -m -u 9999 -g $GROUP_NAME -s /usr/bin/fish devbox || \
    (echo "UID 9999 exists, modifying existing user" && usermod -l devbox -d /home/devbox -g $GROUP_NAME -s /usr/bin/fish $(id -un 9999)); \
    # Add sudo privileges
    echo "devbox ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devbox; \
    chmod 0440 /etc/sudoers.d/devbox

# Create workspace directory
RUN mkdir -p /workspace \
    && chown 9999:9999 /workspace

# Switch to devbox user
USER devbox
WORKDIR /home/devbox

# Configure fish shell with mise and starship
RUN mkdir -p /home/devbox/.config/fish \
    && echo 'if status is-interactive' >> /home/devbox/.config/fish/config.fish \
    && echo '    # mise activation' >> /home/devbox/.config/fish/config.fish \
    && echo '    /usr/local/bin/mise activate fish | source' >> /home/devbox/.config/fish/config.fish \
    && echo '    # starship prompt' >> /home/devbox/.config/fish/config.fish \
    && echo '    starship init fish | source' >> /home/devbox/.config/fish/config.fish \
    && echo 'end' >> /home/devbox/.config/fish/config.fish

# Configure bash with mise and starship (for fallback)
RUN echo 'eval "$(/usr/local/bin/mise activate bash)"' >> /home/devbox/.bashrc \
    && echo 'eval "$(starship init bash)"' >> /home/devbox/.bashrc

# Note: code-server config is generated dynamically in entrypoint.sh

# Switch back to root for entrypoint
USER root

# Copy configuration files
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/supervisord.conf /etc/supervisor/conf.d/devbox.conf
COPY docker/Caddyfile.template /etc/caddy/Caddyfile.template
COPY docker/Caddyfile.template /etc/caddy/Caddyfile
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy helper scripts
COPY scripts/snapshot /usr/local/bin/snapshot
COPY scripts/restore /usr/local/bin/restore
COPY scripts/toggle_public /usr/local/bin/toggle_public
RUN chmod +x /usr/local/bin/snapshot /usr/local/bin/restore /usr/local/bin/toggle_public

# Build and install DevBox status service
COPY devbox-status /tmp/devbox-status
RUN cd /tmp/devbox-status \
    && /usr/local/go/bin/go mod download \
    && CGO_ENABLED=0 /usr/local/go/bin/go build -o /usr/local/bin/devbox-status \
    && chmod +x /usr/local/bin/devbox-status \
    && rm -rf /tmp/devbox-status

# Configure PostgreSQL
RUN mkdir -p /var/run/postgresql && chown postgres:postgres /var/run/postgresql

# Expose ports (though Tailscale will handle the actual serving)
EXPOSE 22 443 5432

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
