FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies
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

# ==============================================================================
# PRE-BAKE GEMS INTO THE IMAGE LAYER
# ==============================================================================
# Generate a dummy app matching the exact '--minimal' specs Coder uses,
# run bundle install to download the cache into /usr/local/bundle, then erase it.
RUN cd /tmp && \
    rails new dummy_app --minimal --skip-bundle && \
    cd dummy_app && \
    bundle install && \
    cd /tmp && \
    rm -rf dummy_app
# ==============================================================================

# Smoke test — fails the build immediately if rails isn't on PATH
RUN rails --version && ruby --version && bundler --version

# Drop back down to the non-root user for runtime safety
USER vscode
