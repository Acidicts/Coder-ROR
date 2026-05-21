FROM mcr.microsoft.com/devcontainers/ruby:3

# Install system dependencies in a single layer to keep image size down
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rails and common gems with no docs to keep image lean
RUN gem install rails --no-document \
    && gem install bundler --no-document

# Smoke test — fails the build immediately if rails isn't on PATH
RUN rails --version && ruby --version && bundler --version

# Switch to the default non-root user the devcontainers base image provides
USER vscode
