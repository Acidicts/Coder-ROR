FROM ghcr.io/acidicts/ruby-base-3.4.7

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
    libvips \
    postgresql-client \
    redis-tools \
    pipx \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# INSTALL NODE.JS & YARN (Required for Rails Assets Synchronization)
# Uses keyring files instead of the deprecated `apt-key add`
# ==============================================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /etc/apt/keyrings/yarn.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs yarn && \
    rm -rf /var/lib/apt/lists/*

# Global npm packages (installed BEFORE NPM_CONFIG_PREFIX is set, so they land
# in the system prefix and are on PATH for every user)
RUN npm install -g "opencode-ai"

ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_PATH=$GEM_HOME
ENV BUNDLE_BIN=$GEM_HOME/bin
ENV NPM_CONFIG_PREFIX=/home/vscode/.npm-global
ENV RUBY_HOME=/usr/local/rvm/rubies/ruby-3.4.7
ENV RVM_GEMS=/usr/local/rvm/gems/ruby-3.4.7
ENV PATH=$RUBY_HOME/bin:$RVM_GEMS/bin:$BUNDLE_BIN:/home/vscode/.npm-global/bin:/usr/local/rvm/bin:$PATH

# Configure pipx to install globally so the vscode user has execution rights
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
RUN pipx install wakatime

# Install Starship Prompt natively
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Download and install JetBrainsMono Nerd Font system-wide
RUN mkdir -p /usr/share/fonts/truetype/jetbrains-nf && \
    curl -fL -o /tmp/jb_mono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/jb_mono.zip -d /usr/share/fonts/truetype/jetbrains-nf/ && \
    rm -f /tmp/jb_mono.zip && \
    fc-cache -fv

# Install Ruby LSP and Bundler (no docs: much faster)
RUN gem install ruby-lsp --no-document && \
    gem install bundler -v '~> 2.7' --no-document

# ==============================================================================
# PRE-BAKE GEMS INTO THE IMAGE LAYER (Optimized for PostgreSQL)
# ==============================================================================
RUN cd /tmp && \
    rails new dummy_app --minimal --database=postgresql --skip-bundle && \
    cd dummy_app && \
    bundle install --jobs="$(nproc)" && \
    cd /tmp && \
    rm -rf dummy_app

# The gem directory must be writable by the runtime user (removes the slow
# `chown -R /usr/local/bundle` from every workspace start)
RUN chown -R vscode:vscode /usr/local/bundle

# Ensure relative ./bin directory is checked first for executables
ENV PATH="./bin:$PATH"

# Smoke test: validation
RUN rails --version && \
    ruby --version && \
    bundler --version && \
    starship --version && \
    wakatime --version && \
    node --version && \
    yarn --version

# ==============================================================================
# CODE-SERVER (baked in; the template module uses use_cached = true)
# The prefix MUST stay /tmp/code-server: the Coder module hardcodes that path.
# ==============================================================================
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server && \
    chown -R vscode:vscode /tmp/code-server

# Install extensions as the runtime user so they land in its home directory.
# Each step is non-fatal; the template has fallbacks for anything that fails here.
USER vscode
RUN CS=/tmp/code-server/bin/code-server; \
    for ext in \
      esbenp.prettier-vscode \
      yusifaliyevpro.vscicons \
      ritwickdey.LiveServer \
      WakaTime.vscode-wakatime \
      sst-dev.opencode \
      Shopify.ruby-lsp; do \
        "$CS" --install-extension "$ext" || echo "WARN: failed to install $ext"; \
    done; \
    curl -fL --retry 3 --connect-timeout 15 -o /tmp/commit-ai-0.1.0.vsix \
      https://github.com/Acidicts/Coder-ROR/releases/download/ai/commit-ai-0.1.0.vsix \
      && "$CS" --install-extension /tmp/commit-ai-0.1.0.vsix \
      || echo "WARN: custom commit-ai VSIX not baked; the template script will install it at start"; \
    rm -f /tmp/commit-ai-0.1.0.vsix

# Runtime user stays non-root
USER vscode
