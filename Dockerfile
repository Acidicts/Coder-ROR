FROM ghcr.io/acidicts/ruby-base-3.4.9

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies, database libraries, fontconfig, unzip & pipx
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
    # --- REQUIRED FOR POPPLER / GOBJECT NATIVE GEMS ---
    libgirepository1.0-dev \
    libpoppler-glib-dev \
    poppler-utils \
    # --------------------------------------------------
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# INSTALL NODE.JS & YARN (Required for Rails Assets Synchronization)
# ==============================================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
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

# Install Rails, Bundler (matching HCB's lockfile), and Ruby LSP
RUN gem install rails ruby-lsp --no-document && \
    gem install bundler -v 2.5.22 --no-document

# ==============================================================================
# PRE-BAKE GEMS INTO A FIXED, KNOWN BUNDLE PATH
#
# FIX: Previously, bundle install ran without an explicit path, so gems landed
# in an ambiguous location. At runtime the startup script then set `system true`
# and nuked .bundle/config, causing bundler to be unable to find the pre-baked
# gems and falling back to a full reinstall.
#
# We now pin BUNDLE_PATH to /usr/local/bundle at build time AND export it as an
# ENV so all subsequent bundler invocations (both in the image and at runtime)
# resolve gems from the exact same location.
# ==============================================================================
ENV BUNDLE_PATH=/usr/local/bundle
ENV BUNDLE_BIN=/usr/local/bundle/bin
ENV GEM_HOME=/usr/local/bundle

RUN mkdir /tmp/hcb && cd /tmp/hcb && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    echo "3.4.9" > .ruby-version && \
    # Unfreeze so we can install; the real repo will re-evaluate at runtime
    bundle config set --local frozen false && \
    bundle config set --local path "${BUNDLE_PATH}" && \
    bundle install --jobs=4 --retry=3 && \
    # Make the bundle path world-readable so the vscode user can use it
    chmod -R 755 "${BUNDLE_PATH}" && \
    cd /tmp && \
    rm -rf /tmp/hcb
# ==============================================================================

# Symlink ruby-lsp into /usr/local/bin so it is always on PATH
RUN ln -sf "${BUNDLE_BIN}/ruby-lsp" /usr/local/bin/ruby-lsp || true

# Ensure relative ./bin directory is checked first for executables, and that
# the pre-baked bundle bin is always on the system PATH.
ENV PATH="${BUNDLE_BIN}:./bin:/usr/local/bin:$PATH"

# Install opencode CLI
RUN curl -fsSL https://opencode.ai/install | bash

# Smoke test — verify all key tools are present
RUN rails --version && \
    ruby --version && \
    bundler --version && \
    starship --version && \
    wakatime --version && \
    node --version && \
    yarn --version

# Drop back down to the non-root user for runtime safety
USER vscode
