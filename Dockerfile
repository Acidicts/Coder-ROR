FROM ghcr.io/acidicts/ruby-base-3.4.7

# Remove the broken Yarn apt source that ships in the base image.
# Its GPG key (FF7CB566...) is expired/missing, causing apt-get update to
# hard-fail with exit code 100 before we can install anything.
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies in a single layer to keep image size down
RUN apt-get update && apt-get install -y --no-install-recommends \
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
