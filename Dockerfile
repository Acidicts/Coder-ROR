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

USER coder
RUN npm install -g yarn

WORKDIR /workspaces
RUN git clone --depth=1 https://github.com/hackclub/hcb.git /workspaces

RUN BUNDLER_VERSION=$(grep -A1 "BUNDLED WITH" /workspaces/Gemfile.lock | tail -1 | tr -d '[:space:]') && \
    gem install bundler -v "$BUNDLER_VERSION" --no-document

RUN bundle install --jobs=4 --retry=3

RUN yarn install --frozen-lockfile || yarn install

USER root

RUN PG_VER=$(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $1}') && \
    echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/$PG_VER/main/pg_hba.conf && \
    echo "host all all ::1/128 trust" >> /etc/postgresql/$PG_VER/main/pg_hba.conf

RUN PG_VER=$(pg_lsclusters -h | head -1 | awk '{print $1}') && \
    PG_CLUSTER=$(pg_lsclusters -h | head -1 | awk '{print $2}') && \
    pg_ctlcluster $PG_VER $PG_CLUSTER start && \
    su - postgres -c "createuser -s coder" 2>/dev/null; \
    pg_ctlcluster $PG_VER $PG_CLUSTER stop || true

RUN cd /workspaces && \
    cp .env.development.example .env.development && \
    ruby -r securerandom -e '
      text = File.read(".env.development")
      text.gsub!("@db:", "@127.0.0.1:")
      text.gsub!("postgres:postgres@", "coder@")
      text.gsub!("redis://redis", "redis://127.0.0.1")
      lines = text.lines.map do |line|
        key = line.split("=", 2).first
        case key
        when "LOCKBOX" then "LOCKBOX=#{SecureRandom.hex(32)}\n"
        when "HASHID_SALT" then "HASHID_SALT=#{SecureRandom.hex(16)}\n"
        when "ACTIVE_RECORD__ENCRYPTION__DETERMINISTIC_KEY" then "ACTIVE_RECORD__ENCRYPTION__DETERMINISTIC_KEY=#{SecureRandom.hex(16)}\n"
        when "ACTIVE_RECORD__ENCRYPTION__KEY_DERIVATION_SALT" then "ACTIVE_RECORD__ENCRYPTION__KEY_DERIVATION_SALT=#{SecureRandom.hex(16)}\n"
        when "ACTIVE_RECORD__ENCRYPTION__PRIMARY_KEY" then "ACTIVE_RECORD__ENCRYPTION__PRIMARY_KEY=#{SecureRandom.hex(16)}\n"
        else line
        end
      end
      lines << "SECRET_KEY_BASE=#{SecureRandom.hex(64)}\n"
      lines << "RAILS_ENV=development\n"
      File.write(".env.development", lines.join)
    ' && \
    chown coder:coder .env.development

RUN PG_VER=$(pg_lsclusters -h | head -1 | awk '{print $1}') && \
    PG_CLUSTER=$(pg_lsclusters -h | head -1 | awk '{print $2}') && \
    pg_ctlcluster $PG_VER $PG_CLUSTER start && \
    cd /workspaces && \
    rails db:create 2>/dev/null; \
    rails db:schema:load 2>/dev/null; \
    pg_ctlcluster $PG_VER $PG_CLUSTER stop || true

USER coder
WORKDIR /workspaces
