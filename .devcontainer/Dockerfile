FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install iptables for optional firewall support
RUN apt-get update \
    && apt-get install -y --no-install-recommends iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code via native installer
RUN curl -fsSL https://claude.ai/install.sh | bash

# Copy firewall script
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh
