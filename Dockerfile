FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies
# Note: We removed 'yarn' from apt-get to avoid the 'cmdtest' package collision
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    pkg-config \
    nodejs \
    npm \
    libglib2.0-dev \
    libgirepository1.0-dev \
    gobject-introspection \
    libpoppler-glib-dev \
    libsodium-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the correct JavaScript Yarn package manager globally via npm
RUN npm install -g yarn

# Install Rails and Bundler with no docs to keep image lean
RUN gem install rails bundler --no-document

# Smoke test — fails the build immediately if core tools aren't on PATH properly
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
# Create /home/coder and grant ownership to the vscode user
RUN mkdir -p /home/coder && chown -R vscode:vscode /home/coder

# (Optional) Remove the mkdir hijack block entirely if it isn't strictly 
# required by internal hardcoded dependencies elsewhere in your base image.

# --- THE HIJACK: Intercept 'mkdir' errors for /home/coder ---
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
WORKDIR /home/coder
