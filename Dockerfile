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

# 3. Install ALL system dependencies (including Node, Postgres, and native compilation extensions)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    pkg-config \
    nodejs \
    libpq-dev \
    libvips-dev \
    libglib2.0-dev \
    libpoppler-glib-dev \
    graphviz \
    postgresql \
    postgresql-contrib \
    libsodium-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 4. Install the correct JavaScript Yarn package manager globally via npm
RUN npm install -g yarn

# 5. Build core Ruby environment (Already using native Ruby 3.4.7 from your base image)
RUN gem install rails bundler --no-document

# Smoke test core toolchain
RUN rails --version && ruby --version && bundler --version && yarn --version

# 6. Pre-cache your application's Ruby dependencies into the image layer
RUN mkdir -p /tmp/gem-cache && cd /tmp/gem-cache && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/Gemfile.lock && \
    curl -sLO https://raw.githubusercontent.com/hackclub/hcb/main/.ruby-version || true && \
    BUNDLE_IGNORE_RUBY_VERSION=true bundle install --retry 3 && \
    rm -rf /tmp/gem-cache

# 7. Secure the Coder workspace user environment
RUN mkdir -p /home/coder && chown -R vscode:vscode /home/coder

# Intercept and neutralize downstream workspace 'mkdir /home/coder' privilege errors gracefully
RUN echo '#!/bin/sh\n\
for arg in "$@";\n\
do\n\
  if [ "$arg" = "/home/coder" ] || [ "$arg" = "-p" -a "$2" = "/home/coder" ];\n\
  then\n\
    exit 0\n\
  fi\n\
done\n\
exec /bin/mkdir "$@"' > /usr/local/bin/mkdir && \
chmod +x /usr/local/bin/mkdir

ENV HOME=/home/coder
ENV CODER_DATA=/home/coder

# Drop privileges back down to standard workspace context
USER vscode
WORKDIR /home/coder
