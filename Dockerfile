FROM ghcr.io/acidicts/ruby-base-3.4.7

# Elevate privileges to root so apt-get has permission to run
USER root

# Remove known broken Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install system dependencies + fontconfig & unzip for NerdFont handling
RUN apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    fontconfig \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Starship Prompt natively
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

RUN sudo chown 666 /

# Download and install JetBrainsMono Nerd Font system-wide
RUN mkdir -p /usr/share/fonts/truetype/jetbrains-nf && \
    curl -L -o /tmp/jb_mono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/jb_mono.zip -d /usr/share/fonts/truetype/jetbrains-nf/ && \
    rm -f /tmp/jb_mono.zip && \
    fc-cache -fv

# Install Rails and Bundler with no docs to keep image lean
RUN gem install rails bundler --no-document

# ==============================================================================
# PRE-BAKE GEMS INTO THE IMAGE LAYER
# ==============================================================================
RUN cd /tmp && \
    rails new dummy_app --minimal --skip-bundle && \
    cd dummy_app && \
    bundle install && \
    cd /tmp && \
    rm -rf dummy_app
# ==============================================================================

# Ensure relative ./bin directory is checked first for executables
ENV PATH="./bin:$PATH"

RUN apt-get update && \
    apt-get install -y --no-install-recommends pipx && \
    rm -rf /var/lib/apt/lists/* && \
    pipx ensurepath && \
    pipx install wakatime

RUN curl -fsSL https://opencode.ai/install | bash

# Smoke test — fails the build immediately if tools aren't functional
RUN rails --version && ruby --version && bundler --version && starship --version

# Drop back down to the non-root user for runtime safety
USER vscode
