# syntax=docker/dockerfile:1.7
# Codespaces mobile-first: Debian 13, Node LTS 26, Python 3.15 via uv.
FROM node:26-trixie-slim AS node-dist
FROM ghcr.io/astral-sh/uv:latest AS uv-dist
FROM mcr.microsoft.com/devcontainers/base:2-trixie

ARG USERNAME=vscode
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CLOUDSDK_SKIP_PY_COMPILATION=1 \
    CLOUDSDK_PYTHON=/usr/bin/python3 \
    UV_NO_PROGRESS=1 \
    PATH=/home/vscode/.local/bin:/usr/local/bin:${PATH}

# Copy official binaries instead of installing Node through nvm on every shell start.
COPY --from=node-dist /usr/local/ /usr/local/
COPY --from=uv-dist /uv /uvx /usr/local/bin/

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      zsh nano micro vim git gh curl wget gawk ca-certificates gnupg \
      less man-db manpages procps psmisc lsof tree unzip zip \
      make build-essential pkg-config golang-go docker.io python3 \
      jq sqlite3 fzf ripgrep fd-find bat eza zoxide \
      shellcheck openssh-client rsync; \
    rm -rf /var/lib/apt/lists/*

# Official Google Cloud CLI apt repository, using a scoped signing key.
RUN set -eux; \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; \
    printf '%s\n' \
      'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main' \
      > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-cloud-cli kubectl; \
    rm -rf /var/lib/apt/lists/*

# Tailscale client for private SSH/SFTP connectivity. Authentication is
# deliberately manual; no auth keys, synced settings or daemon are started.
RUN set -eux; \
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg; \
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
      -o /etc/apt/sources.list.d/tailscale.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends tailscale; \
    rm -rf /var/lib/apt/lists/*; \
    tailscale version

# Wrangler is globally available for convenience. In each project, prefer
# the pinned local version: pnpm add -D wrangler && pnpm exec wrangler ...
RUN set -eux; \
    npm install --global --no-audit --no-fund \
      wrangler@latest pnpm@latest prettier@latest typescript@latest tsx@latest; \
    npm cache clean --force

# nvm is installed for optional per-project Node versions; system Node stays default.
ENV NVM_DIR=/home/vscode/.nvm
RUN set -eux; \
    mkdir -p "$NVM_DIR"; \
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o /tmp/install-nvm.sh; \
    chown -R "$USERNAME:$USERNAME" "$NVM_DIR"; \
    su "$USERNAME" -s /bin/bash -c 'PROFILE=/dev/null bash /tmp/install-nvm.sh'; \
    rm -f /tmp/install-nvm.sh

# Native Zinit prompt: the base image may contain OMZ, but it is never sourced.
RUN set -eux; \
    mkdir -p "/home/${USERNAME}/.local/share/zinit"; \
    git clone --quiet --depth=1 https://github.com/zdharma-continuum/zinit.git \
      "/home/${USERNAME}/.local/share/zinit/zinit.git"; \
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.local/share/zinit"; \
    chsh -s /usr/bin/zsh "$USERNAME"

COPY zsh/rod-zinit.zshrc /tmp/rod-zinit.zshrc
COPY zsh/rod-prompt-neon.zsh /tmp/rod-prompt-neon.zsh
COPY zsh/rod-prompt-neon.config.zsh /tmp/rod-prompt-neon.config.zsh
COPY nano/nanorc /tmp/rod-nanorc
COPY scripts/doctor.sh /usr/local/bin/mobile-doctor

RUN set -eux; \
    mkdir -p "/home/${USERNAME}/.config/zsh"; \
    printf '%s\\n' '[[ -r "$HOME/.config/zsh/rod-zinit.zshrc" ]] && source "$HOME/.config/zsh/rod-zinit.zshrc"' > "/home/${USERNAME}/.zshrc"; \
    install -o "$USERNAME" -g "$USERNAME" -m 0644 /tmp/rod-zinit.zshrc "/home/${USERNAME}/.config/zsh/rod-zinit.zshrc"; \
    install -o "$USERNAME" -g "$USERNAME" -m 0644 /tmp/rod-prompt-neon.zsh "/home/${USERNAME}/.config/zsh/rod-prompt.zsh"; \
    install -o "$USERNAME" -g "$USERNAME" -m 0644 /tmp/rod-prompt-neon.config.zsh "/home/${USERNAME}/.config/zsh/rod-prompt-neon.config.zsh"; \
    chown "$USERNAME:$USERNAME" "/home/${USERNAME}/.zshrc"; \
    install -o "$USERNAME" -g "$USERNAME" -m 0644 \
      /tmp/rod-nanorc "/home/${USERNAME}/.nanorc"; \
    chmod 0755 /usr/local/bin/mobile-doctor; \
    rm -f /tmp/rod-zshrc /tmp/rod-mobile.zsh-theme /tmp/rod-nanorc; \
    zsh -n "/home/${USERNAME}/.zshrc"; \
    zsh -n "/home/${USERNAME}/.oh-my-zsh/custom/themes/rod-mobile.zsh-theme"

USER ${USERNAME}
WORKDIR /workspaces

# uv manages a user-scoped Python; system Python remains for the gcloud CLI.
RUN uv python install 3.15 --default \
    && uv tool install ruff \
    && uv tool install pygments \
    && python --version \
    && uv --version \
    && node --version \
    && pnpm --version

SHELL ["/usr/bin/zsh", "-c"]