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

# 3. Install ALL system dependencies
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

# 4. Create an explicit 'coder' user and set up sudo permissions
RUN id -u vscode >/dev/null 2>&1 && userdel -r vscode || true \
    && useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

# 5. Setup Bundler & Global NPM Paths to be completely owned by user 'coder'
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_PATH=$GEM_HOME
ENV BUNDLE_BIN=$GEM_HOME/bin
ENV NPM_CONFIG_PREFIX=/home/coder/.npm-global

# Safely append paths without wiping out the base image's predefined paths
ENV PATH=$BUNDLE_BIN:/home/coder/.npm-global/bin:$PATH

RUN mkdir -p $GEM_HOME /home/coder/.npm-global && \
    chown -R coder:coder $GEM_HOME /home/coder/.npm-global

# Drop privileges down to standard workspace context
USER coder
WORKDIR /workspaces

# 6. Install Yarn into the coder-owned global space
RUN npm install -g yarn

# 7. Pull Gemfile state and build dependencies
USER root
RUN mkdir -p /tmp/gem-cache && cd /tmp/gem-cache && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/.ruby-version || true && \
    BUNDLER_VERSION=$(tail -n 2 Gemfile.lock | tr -d '[:space:]' | tr -d 'BUNDLEDWITH') && \
    gem install bundler -v "$BUNDLER_VERSION" --no-document && \
    BUNDLE_IGNORE_RUBY_VERSION=true bundle install --jobs=4 --retry=3 && \
    chown -R coder:coder $GEM_HOME && \
    rm -rf /tmp/gem-cache

RUN rvmsudo bundle install

RUN rvm install "ruby-3.4.7"

USER coder
