FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies, database libraries, fontconfig, unzip & pipx
# Note: Added gnupg here so we can safely add external repository keys
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    gnupg \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    fontconfig \
    unzip \
    libpq-dev \
    postgresql-client \
    redis-tools \
    pipx \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# INSTALL NODE.JS & YARN (Required for Rails Assets Synchronization)
# ==============================================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs yarn && \
    rm -rf /var/lib/apt/lists/*
# ==============================================================================

# Configure pipx to install globally so the vscode user has execution rights
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
RUN pipx install wakatime

# Install Starship Prompt natively
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Download and install JetBrainsMono Nerd Font system-wide
RUN mkdir -p /usr/share/fonts/truetype/jetbrains-nf && \
    curl -L -o /tmp/jb_mono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/jb_mono.zip -d /usr/share/fonts/truetype/jetbrains-nf/ && \
    rm -f /tmp/jb_mono.zip && \
    fc-cache -fv

# Install Rails, Bundler, and Ruby LSP with no docs to keep image lean
RUN gem install rails bundler ruby-lsp --no-document

# ==============================================================================
# PRE-BAKE GEMS INTO THE IMAGE LAYER (Optimized for PostgreSQL)
# ==============================================================================
RUN cd /tmp && \
    rails new dummy_app --minimal --database=postgresql --skip-bundle && \
    cd dummy_app && \
    bundle install && \
    cd /tmp && \
    rm -rf dummy_app
# ==============================================================================

# Ensure relative ./bin directory is checked first for executables
ENV PATH="./bin:$PATH"

# Install opencode CLI
RUN curl -fsSL https://opencode.ai/install | bash

# Smoke test — added node, yarn, and wakatime validation
RUN rails --version && \
    ruby --version && \
    bundler --version && \
    starship --version && \
    wakatime --version && \
    node --version && \
    yarn --version

# Drop back down to the non-root user for runtime safety
USER vscode
