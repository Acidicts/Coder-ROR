FROM ghcr.io/acidicts/ruby-base-3.4.7

USER root

RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential pkg-config nodejs \
    libpq-dev libvips-dev libglib2.0-dev libgirepository1.0-dev \
    gobject-introspection libpoppler-glib-dev graphviz \
    postgresql postgresql-contrib redis-server \
    libsodium-dev libssl-dev libreadline-dev zlib1g-dev sudo \
    tesseract-ocr libtesseract-dev libleptonica-dev \
    libjemalloc2 poppler-utils \
    && rm -rf /var/lib/apt/lists/*

RUN id -u vscode >/dev/null 2>&1 && userdel -r vscode || true \
    && useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_PATH=$GEM_HOME
ENV BUNDLE_BIN=$GEM_HOME/bin
ENV NPM_CONFIG_PREFIX=/home/coder/.npm-global
ENV PATH=$BUNDLE_BIN:/home/coder/.npm-global/bin:$PATH

RUN mkdir -p $GEM_HOME /home/coder/.npm-global && \
    chown -R coder:coder $GEM_HOME /home/coder/.npm-global

RUN mkdir -p /workspaces && chown coder:coder /workspaces

USER coder
RUN npm install -g yarn 
RUN npm install -g "opencode-ai"

# --- OPTION 2 IMPLEMENTATION ---
# Temporarily drop back to root to bypass the QEMU sudo bug
USER root
RUN chown -R coder:coder /usr/local/rvm/gems/ruby-3.4.7 && \
    gem install ruby-lsp --install-dir /usr/local/rvm/gems/ruby-3.4.7 && \
    gem install bundler -v '~> 2.7' --install-dir /usr/local/rvm/gems/ruby-3.4.7

# Return to user coder context
USER coder
# -------------------------------

WORKDIR /workspaces

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

RUN git clone --depth=1 https://github.com/hackclub/hcb.git /workspaces && \
    cd /workspaces && bundle install --jobs=4 --retry=3 && \
    yarn install --frozen-lockfile || yarn install

USER root

RUN chown -R coder:coder /usr/local/rvm/rubies 2>/dev/null; \
    chown -R coder:coder /usr/local/rvm/gems 2>/dev/null || true
ENV BUNDLE_USER_CACHE=/usr/local/bundle/cache

RUN find /etc/postgresql -name pg_hba.conf -type f -exec sh -c 'sed -i "s|^host.*127.0.0.1/32.*scram-sha-256|host    all             all             127.0.0.1/32    trust|" "$1"; sed -i "s|^host.*::1/128.*scram-sha-256|host    all             all             ::1/128                 trust|" "$1"' _ {} \; 2>/dev/null; \
    PG_VER=$(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $1}') && \
    PG_CLUSTER=$(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $2}') && \
    if [ -n "$PG_VER" ] && [ -n "$PG_CLUSTER" ]; then \
      pg_ctlcluster $PG_VER $PG_CLUSTER start && \
      su - postgres -c "createuser -s coder" 2>/dev/null || true && \
      pg_ctlcluster $PG_VER $PG_CLUSTER stop || true; \
    fi

USER coder
RUN echo 'export GEM_HOME=/usr/local/bundle' >> ~/.bashrc && \
    echo 'export BUNDLE_PATH=$GEM_HOME' >> ~/.bashrc && \
    echo 'export BUNDLE_USER_CACHE=$GEM_HOME/cache' >> ~/.bashrc

WORKDIR /workspaces
