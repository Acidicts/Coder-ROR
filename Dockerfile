# Start directly from the official Ruby 3.4.7 Debian-based image
FROM ruby:3.4.12-bookworm

# Configure environment variables for a non-interactive, UTF-8 environment
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# Replicate the default 'vscode' non-root user that Microsoft devcontainers expect
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    # Add sudo support for the non-root user
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install standard development utilities included in Microsoft Devcontainers
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    openssh-client \
    less \
    iproute2 \
    procps \
    gnupg2 \
    build-essential \
    autoconf \
    bison \
    gawk \
    libssl-dev \
    libreadline-dev \
    libyaml-dev \
    libgdbm-dev \
    libncurses5-dev \
    libffi-dev \
    libgmp-dev \
    libdb-dev \
    libsqlite3-dev \
    liblzma-dev \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    libtool \
    pkg-config \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Clean up/remove any broken or inherited Yarn apt sources if they exist
RUN rm -f /etc/apt/sources.list.d/yarn.list \
          /usr/share/keyrings/yarnkey.gpg \
          /etc/apt/sources.list.d/yarn.list.bak

# Install RVM (Ruby Version Manager) for easy switching between Ruby versions.
# This is a multi-user install under /usr/local/rvm.
ENV RVM_PATH=/usr/local/rvm \
    RVM_HOME=/usr/local/rvm \
    PATH=/usr/local/rvm/bin:$PATH \
    rvm_silence_path_mismatch_check_flag=1

ARG RVM_VERSION=1.29.12
ARG RVM_TARBALL_SHA256=856feaebb88ff84dbf916016ada01edb0e4eddd1a3038164ebc69434928cb554

RUN bash <<'EOF'
set -euxo pipefail
getent group rvm >/dev/null || groupadd -r rvm
curl -fsSL -o /tmp/rvm.tar.gz "https://github.com/rvm/rvm/archive/refs/tags/${RVM_VERSION}.tar.gz"
echo "${RVM_TARBALL_SHA256}  /tmp/rvm.tar.gz" | sha256sum -c -
tar -xzf /tmp/rvm.tar.gz -C /tmp
cd /tmp/rvm-${RVM_VERSION}
./install --path "$RVM_PATH"
rm -rf /tmp/rvm.tar.gz /tmp/rvm-${RVM_VERSION}
usermod -aG rvm "$USERNAME"
cat > /etc/profile.d/zz-ruby-bundle-path.sh <<'RUBY_BUNDLE_PATH'
if [ "${GEM_HOME:-}" = "/usr/local/bundle" ]; then
  case ":${PATH:-}:" in
    *:/usr/local/bundle/bin:*) ;;
    *) export PATH="${PATH:+$PATH:}/usr/local/bundle/bin" ;;
  esac
fi
RUBY_BUNDLE_PATH
cat > /etc/profile.d/rvm.sh <<'RVM_PROFILE'
# System-wide RVM initialization.
# Kept POSIX-sh compatible because /etc/profile sources /etc/profile.d/*.sh.
export rvm_path="/usr/local/rvm"
case ":${PATH:-}:" in
  *:"${rvm_path}/bin":*) ;;
  *) export PATH="${rvm_path}/bin${PATH:+:$PATH}" ;;
esac
if [ -s "${rvm_path}/scripts/rvm" ]; then
  . "${rvm_path}/scripts/rvm"
fi
RVM_PROFILE
cat >> /etc/bash.bashrc <<'BASHRC_RVM_SNIPPET'

if [[ -s "/etc/profile.d/rvm.sh" ]]; then
  source "/etc/profile.d/rvm.sh"
fi

if [[ -s "/etc/profile.d/zz-ruby-bundle-path.sh" ]]; then
  source "/etc/profile.d/zz-ruby-bundle-path.sh"
fi
BASHRC_RVM_SNIPPET
EOF

RUN bash -lc "rvm --version"

# Pre-install Rails and Bundler without extra documentation bloat
RUN gem install rails bundler --no-document

# Verify everything is on the PATH and installed correctly
RUN rails --version && ruby --version && bundler --version

# Set the default container user to the non-root vscode user
USER vscode

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
ENV RUBY_HOME=/usr/local/rvm/rubies/ruby-3.4.7
ENV RVM_GEMS=/usr/local/rvm/gems/ruby-3.4.7
ENV PATH=$RUBY_HOME/bin:$RVM_GEMS/bin:$BUNDLE_BIN:/home/coder/.npm-global/bin:/usr/local/rvm/bin:$PATH

RUN mkdir -p $GEM_HOME /home/coder/.npm-global && \
    chown -R coder:coder $GEM_HOME /home/coder/.npm-global

RUN mkdir -p /workspaces && chown coder:coder /workspaces

USER coder
RUN npm install -g yarn 
RUN npm install -g "opencode-ai"

# --- OPTION 2 IMPLEMENTATION ---
# Temporarily drop back to root to bypass the QEMU sudo bug
USER root
RUN gem install ruby-lsp && \
    gem install bundler -v '~> 2.7'

# Return to user coder context
USER coder
# -------------------------------

WORKDIR /workspaces

RUN mkdir -p /home/coder/.linuxbrew && \
    git clone --depth=1 https://github.com/Homebrew/brew /home/coder/.linuxbrew/Homebrew && \
    mkdir -p /home/coder/.linuxbrew/bin && \
    ln -sfn /home/coder/.linuxbrew/Homebrew/bin/brew /home/coder/.linuxbrew/bin/brew && \
    eval "$(/home/coder/.linuxbrew/bin/brew shellenv)" && \
    brew update && brew upgrade

RUN git clone --depth=1 https://github.com/hackclub/hcb.git /workspaces && \
    cd /workspaces && bundle install --jobs=4 --retry=3 && \
    yarn install --frozen-lockfile || yarn install

USER root

RUN chown -R coder:coder /usr/local/bundle 2>/dev/null || true
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
