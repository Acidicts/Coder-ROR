FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies (including complete gobject-introspection & compiler specs)
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    pkg-config \
    libglib2.0-dev \
    libgirepository1.0-dev \
    gobject-introspection \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rails and Bundler with no docs to keep image lean
RUN gem install rails bundler --no-document

# Smoke test — fails the build immediately if rails isn't on PATH
RUN rails --version && ruby --version && bundler --version

# --- OPTIMIZATION: Cache Gemfile gems into the image layer ---
# Download Gemfile, lockfile, and .ruby-version from the hackclub/hcb repo to build the gem cache
RUN mkdir -p /tmp/gem-cache && cd /tmp/gem-cache && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/.ruby-version || true && \
    BUNDLE_IGNORE_RUBY_VERSION=true bundle install --retry 3 && \
    rm -rf /tmp/gem-cache
# --------------------------------------------------------------

# Drop back down to the non-root user for runtime safety
USER vscode
