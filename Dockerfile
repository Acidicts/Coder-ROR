# https://github.com/Acidicts/Ruby-3.4.7-Dockerfile
FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root for system-level adjustments
USER root

# 1. Clean out legacy/broken package lists
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# 2. Add NodeSource for Node.js v22 directly in the image layer
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

# 3. Install ALL system dependencies (Fixing gobject-introspection build error)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    pkg-config \
    nodejs \
    libpq-dev \
    libvips-dev \
    libglib2.0-dev \
    libgirepository1.0-dev \
    gobject-introspection \
    libpoppler-glib-dev \
    graphviz \
    postgresql \
    postgresql-contrib \
    libsodium-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 4. Install JavaScript Yarn package manager globally via npm
RUN npm install -g yarn

# 5. Create an explicit 'coder' user and set up sudo permissions
RUN id -u vscode >/dev/null 2>&1 && userdel -r vscode || true \
    && useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

# Configure global Bundler & System Paths explicitly (Fixes Yarn binary mapping)
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_PATH=$GEM_HOME
ENV BUNDLE_BIN=$GEM_HOME/bin
ENV PATH=$BUNDLE_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

# 6. Pull Gemfile state and build dependencies as root to write to global paths safely
RUN mkdir -p $GEM_HOME && chown -R coder:coder $GEM_HOME

RUN mkdir -p /tmp/gem-cache && cd /tmp/gem-cache && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/.ruby-version || true && \
    BUNDLER_VERSION=$(tail -n 2 Gemfile.lock | tr -d '[:space:]' | tr -d 'BUNDLEDWITH') && \
    gem install bundler -v "$BUNDLER_VERSION" --no-document && \
    BUNDLE_IGNORE_RUBY_VERSION=true bundle install --jobs=4 --retry=3 && \
    chown -R coder:coder $GEM_HOME && \
    rm -rf /tmp/gem-cache

# Drop privileges back down to standard workspace context for Coder
USER coder
WORKDIR /workspaces
