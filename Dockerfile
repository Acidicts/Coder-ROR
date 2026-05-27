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
RUN gem update --system 2>/dev/null || true

WORKDIR /workspaces

RUN git clone --depth=1 https://github.com/hackclub/hcb.git /workspaces && \
    BUNDLER_VERSION=$(grep -A1 "BUNDLED WITH" /workspaces/Gemfile.lock | tail -1 | tr -d '[:space:]') && \
    if [ -n "$BUNDLER_VERSION" ]; then gem install bundler -v "$BUNDLER_VERSION" --no-document; fi && \
    cd /workspaces && bundle install --jobs=4 --retry=3 && \
    yarn install --frozen-lockfile || yarn install

USER root

RUN PG_VER=$(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $1}') && \
    PG_CLUSTER=$(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $2}') && \
    if [ -n "$PG_VER" ]; then \
      echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/$PG_VER/main/pg_hba.conf && \
      echo "host all all ::1/128 trust" >> /etc/postgresql/$PG_VER/main/pg_hba.conf && \
      pg_ctlcluster $PG_VER $PG_CLUSTER start && \
      su - postgres -c "createuser -s coder" 2>/dev/null || true && \
      pg_ctlcluster $PG_VER $PG_CLUSTER stop || true; \
    fi

USER coder
WORKDIR /workspaces
