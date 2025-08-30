FROM ubuntu:22.04

# Build argument for Neovim version (default to latest)
ARG NVIM_VERSION=latest

# Build args provided by buildx; default if plain docker build
ARG TARGETARCH

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Neovim (native architecture detection)
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64|x86_64) NVIM_SUFFIX=linux-x86_64 ;; \
        arm64|aarch64) NVIM_SUFFIX=linux-arm64 ;; \
        *) echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    if [ "${NVIM_VERSION:-latest}" = "latest" ]; then \
        BASE="https://github.com/neovim/neovim/releases/latest/download"; \
    else \
        BASE="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}"; \
    fi; \
    URL="${BASE}/nvim-${NVIM_SUFFIX}.tar.gz"; \
    echo "Downloading ${URL}"; \
    curl -fL -o /tmp/nvim.tgz "${URL}"; \
    tar -C /opt -xzf /tmp/nvim.tgz; \
    ln -s "/opt/nvim-${NVIM_SUFFIX}/bin/nvim" /usr/local/bin/nvim; \
    rm /tmp/nvim.tgz

# No need to install LSP manually - Mason will handle it

# Create working directory
WORKDIR /repro

# Copy reproduction files
COPY init.lua .
COPY sample.lua .

# Set up minimal Neovim config directory
RUN mkdir -p /root/.config/nvim

# Pre-install LSP servers with Mason to avoid runtime delays
RUN nvim --headless -u init.lua \
    "+MasonUpdate" \
    "+MasonInstall lua-language-server" \
    "+qall"

# Create entrypoint script
RUN echo '#!/bin/bash\n\
echo "=== Lensline Bug Reproduction Environment ==="\n\
echo "Files available:"\n\
ls -la\n\
echo ""\n\
echo "To reproduce the issue:"\n\
echo "1. nvim -u init.lua sample.lua"\n\
echo "2. Follow your bug reproduction steps"\n\
echo "3. Use :LenslineDebug to check debug logs"\n\
echo "4. Use :messages to see LSP debug output"\n\
echo ""\n\
echo "Starting bash shell..."\n\
exec bash\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]