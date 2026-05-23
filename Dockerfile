FROM ghcr.io/acidicts/ruby-base-3.4.7

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies
# Added flags to prevent broken/expired third-party keys from crashing the build
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rails and Bundler with no docs to keep image lean
RUN gem install rails bundler --no-document

# Smoke test — fails the build immediately if rails isn't on PATH
RUN rails --version && ruby --version && bundler --version

# Switch to the default non-root user the devcontainers base image provides
USER vscode
