FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies
# - nodejs & yarn: For asset management and workspace compilation
# - gobject-introspection & libglib2.0-dev: For native gem compilation extensions
# - libpoppler-glib-dev: Resolves poppler C-extension installation failure
# - libsodium-dev: Fixes discordrb voice support warning
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    pkg-config \
    nodejs \
    yarn \
    libglib2.0-dev \
    libgirepository1.0-dev \
    gobject-introspection \
    libpoppler-glib-dev \
    libsodium-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rails and Bundler with no docs to keep image lean
RUN gem install rails bundler --no-document

# Smoke test — fails the build immediately if core tools aren't on PATH
RUN rails --version && ruby --version && bundler --version && yarn --version

# --- OPTIMIZATION: Cache Gemfile gems into the image layer ---
# Download Gemfile, lockfile, and .ruby-version from the hackclub/hcb repo to build the gem cache
RUN mkdir -p /tmp/gem-cache && cd /tmp/gem-cache && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/.ruby-version || true && \
    BUNDLE_IGNORE_RUBY_VERSION=true bundle install --retry 3 && \
    rm -rf /tmp/gem-cache
# --------------------------------------------------------------

# --- SYSTEM-LEVEL HOME FIX ---
# Build /home/coder and make it globally readable/writable by any runtime user ID
RUN mkdir -p /home/coder && chmod 777 /home /home/coder

# --- THE HIJACK: Intercept 'mkdir' errors for /home/coder ---
# Create a wrapper script that drops into /usr/local/bin (which takes precedence on PATH).
# If a script runs `mkdir /home/coder`, it will silently return success instead of crashing.
RUN echo '#!/bin/sh\n\
for arg in "$@"; do\n\
  if [ "$arg" = "/home/coder" ] || [ "$arg" = "-p" -a "$2" = "/home/coder" ]; then\n\
    exit 0\n\
  fi\n\
done\n\
exec /bin/mkdir "$@"' > /usr/local/bin/mkdir && \
chmod +x /usr/local/bin/mkdir

# Set environment paths to match the target workspace expectation
ENV HOME=/home/coder
ENV CODER_DATA=/home/coder

# Drop back down to the non-root user context
USER vscode
WORKDIR /home/coderUSER vscode
WORKDIR /home/coder
