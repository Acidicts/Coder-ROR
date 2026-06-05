# Metroid-Mania Dev

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "coder" {}
provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repo" {
  default      = "https://github.com/Acidicts/Metroid-Mania.git"
  description  = "Select a repository to automatically clone or start fresh with a blank workspace."
  display_name = "Repository"
  mutable      = true
  name         = "repo"
  option {
    name        = "Metroid-Mania (Default)"
    icon        = "/emojis/1f1f7.png"
    description = "Clone the Metroid-Mania repository"
    value       = "https://github.com/Acidicts/Metroid-Mania.git"
  }
  option {
    name        = "Blank Workspace"
    icon        = "/emojis/1f192.png"
    description = "Start fresh without cloning any repository"
    value       = "blank"
  }
  option {
    name        = "Custom"
    icon        = "/emojis/1f5c3.png"
    description = "Specify a custom repo URL below"
    value       = "custom"
  }
  order = 1
}

data "coder_parameter" "custom_repo_url" {
  default      = ""
  description  = "Optionally enter a custom repository URL."
  display_name = "Repository URL (custom)"
  name         = "custom_repo_url"
  mutable      = true
  order        = 2
}

data "coder_parameter" "fallback_image" {
  default      = "ghcr.io/acidicts/ruby-rails-base:latest"
  description  = "The workspace base image."
  display_name = "Workspace Image"
  mutable      = true
  name         = "fallback_image"
  order        = 3
}

data "coder_parameter" "wakatime_api_key" {
  default      = "a5741784-7a46-400a-9104-3b9f898c48ea"
  description  = "Enter your WakaTime/Hackatime API Key to enable automatic time tracking."
  display_name = "WakaTime API Key"
  name         = "wakatime_api_key"
  mutable      = true
  type         = "string"
  order        = 4

  styling = jsonencode({
    mask_input = true
  })
}

data "coder_parameter" "wakatime_api_url" {
  default      = "https://hackatime.hackclub.com/api/hackatime/v1"
  description  = "Enter your WakaTime/Hackatime API URL to enable automatic time tracking."
  display_name = "WakaTime API URL"
  name         = "wakatime_api_url"
  mutable      = true
  type         = "string"
  order        = 5
}

locals {
  container_name   = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  workspace_image  = data.coder_parameter.fallback_image.value
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email

  repo_url              = data.coder_parameter.repo.value == "custom" ? data.coder_parameter.custom_repo_url.value : (data.coder_parameter.repo.value == "blank" ? "" : data.coder_parameter.repo.value)
  repo_name             = local.repo_url != "" ? element(split("/", local.repo_url), length(split("/", local.repo_url)) - 1) : ""
  repo_folder_cleaned   = replace(local.repo_name, ".git", "")
  active_folder_name    = local.repo_folder_cleaned != "" ? local.repo_folder_cleaned : lower(data.coder_workspace.me.name)
  workspace_folder      = "/workspaces/${local.active_folder_name}"
  workspace_branch_name = lower(replace(replace(replace(data.coder_workspace.me.name, "/([a-z])([A-Z])/", "$${1}_$${2}"), "/\\s+|-/", "_"), "/_+/", "_"))
}

resource "docker_image" "workspace_image" {
  name         = local.workspace_image
  keep_locally = true
}

resource "docker_volume" "workspaces" {
  name = "coder-${data.coder_workspace.me.id}"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count = 1
  start = data.coder_workspace.me.start_count > 0 ? true : false

  image    = docker_image.workspace_image.name
  name     = local.container_name
  hostname = data.coder_workspace.me.name

  entrypoint = ["/bin/bash", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  privileged = true
  tty        = true
  stdin_open = true
  shm_size   = 2048

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/workspaces"
    volume_name    = docker_volume.workspaces.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash

    # ANSI Color Palette
    BLUE="\033[1m\033[38;5;39m"
    CYAN="\033[1m\033[38;5;51m"
    GREEN="\033[38;5;76m"
    RED="\033[38;5;196m"
    YELLOW="\033[38;5;220m"
    RESET="\033[0m"
    BOLD="\033[1m"

    clear
    echo -e "$${BLUE}=======================================================$${RESET}"
    echo -e "   $${CYAN}⚡ METROID-MANIA DEVELOPMENT ENVIRONMENT ⚡$${RESET}"
    echo -e "$${BLUE}=======================================================$${RESET}"
    echo -e "   $${GREEN}✓$${RESET} Coder Connection Protocol Established Natively."
    echo -e "$${BLUE}-------------------------------------------------------$${RESET}"
    echo -e "$${BOLD}$${CYAN}Starting background systems provisioning...$${RESET}\n"

    # Temporary directory for tracking async background pid logs
    LOG_DIR="/tmp/coder_async_logs"
    mkdir -p "$LOG_DIR"

    # Background executor wrapper
    dispatch_task() {
      local task_id="$1"
      local step_name="$2"
      local cmd="$3"

      echo -e "  $${YELLOW}⚙$${RESET} Starting: $${step_name}..."

      # Execute work in background, catching errors and execution details
      (
        local start_time=$SECONDS
        eval "$cmd" > "$LOG_DIR/$task_id.log" 2>&1
        local exit_code=$?
        local elapsed=$(( SECONDS - start_time ))

        if [ $exit_code -ne 0 ]; then
          echo -e "  $${RED}⛌$${RESET} $${step_name} Failed! ($${elapsed}s)" >> "$LOG_DIR/status.log"
          echo "FAIL:$task_id:$step_name" >> "$LOG_DIR/status.log"
        else
          echo -e "  $${GREEN}✓$${RESET} Finished: $${step_name} ($${YELLOW}$${elapsed}s$${RESET})" >> "$LOG_DIR/status.log"
        fi
      ) &
    }

    # Watchdog to wait for background PIDs while logging cleanly
    await_dispatched_tasks() {
      wait

      # If any task failure markers exist in the log output, print telemetry and abort build
      if grep -q "FAIL:" "$LOG_DIR/status.log" 2>/dev/null; then
        echo -e "\n$${RED}[❌ Critical Bootstrapper Failure Detected]$${RESET}\n"
        cat "$LOG_DIR/status.log" | grep -v "FAIL:"

        local failed_id=$(grep "FAIL:" "$LOG_DIR/status.log" | head -n 1 | cut -d':' -f2)
        echo -e "\n$${RED}--- Standard Error Output from Failed Task ($failed_id) ---$${RESET}"
        cat "$LOG_DIR/$failed_id.log"
        exit 1
      fi

      # Output completed block history statuses and flush the buffer log cleanly
      if [ -f "$LOG_DIR/status.log" ]; then
        cat "$LOG_DIR/status.log"
        rm -f "$LOG_DIR/status.log"
      fi
      echo ""
    }

    # ========================================================
    # WAVE 0: Start PostgreSQL and Redis Services
    # ========================================================

    # Start PostgreSQL
    dispatch_task "postgres" "Starting PostgreSQL Service" "
      # Install PostgreSQL if not present
      if ! command -v pg_isready &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends postgresql postgresql-client
      fi

      sudo mkdir -p /run/postgresql && sudo chown postgres:postgres /run/postgresql

      # Find PG version and start
      PG_VER=\$(ls /etc/postgresql/ 2>/dev/null | sort -V | tail -1)
      PG_BIN=\"/usr/lib/postgresql/\$PG_VER/bin\"

      if [ -n \"\$PG_VER\" ] && [ -d \"\$PG_BIN\" ]; then
        sudo pg_ctlcluster \$PG_VER start 2>/dev/null || \
          sudo -u postgres \$PG_BIN/pg_ctl -D /var/lib/postgresql/data start 2>/dev/null || true
      else
        sudo mkdir -p /var/lib/postgresql/data && sudo chown -R postgres:postgres /var/lib/postgresql
        PG_INITDB=\$(find /usr/lib/postgresql -name initdb 2>/dev/null | head -1)
        PG_CTL=\$(find /usr/lib/postgresql -name pg_ctl 2>/dev/null | head -1)
        if [ -n \"\$PG_INITDB\" ]; then
          sudo -u postgres \$PG_INITDB -D /var/lib/postgresql/data 2>/dev/null || true
          sudo -u postgres \$PG_CTL -D /var/lib/postgresql/data start 2>/dev/null || true
        fi
      fi

      # Wait for PostgreSQL to be ready
      PG_ISREADY=\$(find /usr/lib/postgresql -name pg_isready 2>/dev/null | head -1)
      if [ -z \"\$PG_ISREADY\" ]; then PG_ISREADY=\$(which pg_isready 2>/dev/null); fi
      for i in 1 2 3 4 5 6 7 8 9 10; do
        if sudo -u postgres \$PG_ISREADY -q 2>/dev/null; then
          echo 'PostgreSQL is ready.'
          break
        fi
        sleep 1
      done

      # Create coder user and database
      PSQL=\$(find /usr/lib/postgresql -name psql 2>/dev/null | head -1)
      CREATEDB=\$(find /usr/lib/postgresql -name createdb 2>/dev/null | head -1)
      if [ -z \"\$PSQL\" ]; then PSQL=\$(which psql 2>/dev/null); fi
      if [ -z \"\$CREATEDB\" ]; then CREATEDB=\$(which createdb 2>/dev/null); fi
      sudo -u postgres \$PSQL -tc \"SELECT 1 FROM pg_roles WHERE rolname='coder'\" | grep -q 1 || \
        sudo -u postgres \$PSQL -c \"CREATE USER coder WITH SUPERUSER PASSWORD 'coder';\" 2>/dev/null || true
      sudo -u postgres \$PSQL -tc \"SELECT 1 FROM pg_database WHERE datname='metroid_mania_development'\" | grep -q 1 || \
        sudo -u postgres \$CREATEDB -O coder metroid_mania_development 2>/dev/null || true
    "

    # Start Redis
    dispatch_task "redis" "Starting Redis Service" "
      # Install Redis if not present
      if ! command -v redis-server &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends redis-server
      fi

      # Find and start Redis
      REDIS_SERVER=\$(which redis-server 2>/dev/null || find /usr/bin /usr/local/bin -name redis-server 2>/dev/null | head -1)
      REDIS_CLI=\$(which redis-cli 2>/dev/null || find /usr/bin /usr/local/bin -name redis-cli 2>/dev/null | head -1)

      sudo \$REDIS_SERVER --daemonize yes --loglevel warning

      # Verify Redis is running
      for i in 1 2 3 4 5; do
        if \$REDIS_CLI ping 2>/dev/null | grep -q PONG; then
          echo 'Redis is ready.'
          break
        fi
        sleep 1
      done
    "

    await_dispatched_tasks

    # ========================================================
    # WAVE 1: Independent System Operations & Mount Preparations
    # ========================================================

    # 1. Mount Check, directory setup, and Global Gem Cache ownership alignment
    dispatch_task "mount" "Verifying and Fixing Mount Permissions" "
      sudo mkdir -p /workspaces && \
      sudo chown -R \$(whoami):\$(whoami) /workspaces && \
      mkdir -p '${local.workspace_folder}' && \
      if [ -d /usr/local/bundle ]; then sudo chown -R \$(whoami):\$(whoami) /usr/local/bundle; fi
    "

    # 2. Resilient Git Sync (Only if repository chosen is not 'blank')
    if [ "${data.coder_parameter.repo.value}" != "blank" ] && [ -n "${local.repo_url}" ]; then
      if [ ! -d "${local.workspace_folder}/.git" ]; then
        dispatch_task "git" "Git Clone Setup" "
          sudo mkdir -p '${local.workspace_folder}' && \
          sudo chown -R \$(whoami):\$(whoami) '${local.workspace_folder}' && \
          cd '${local.workspace_folder}' && \
          git init && \
          git remote add origin ${local.repo_url} && \
          git fetch --depth=1 origin main && \
          git checkout -f main && \
          git config --local user.name '${local.git_author_name}' && \
          git config --local user.email '${local.git_author_email}' && \
          git checkout -b '${local.workspace_branch_name}'
        "
      else
        echo -e "  $${GREEN}✓$${RESET} Found existing Git tracking layer."
      fi
    fi

    # 2b. Auto-create .env from .env.example
    if [ -n "${local.repo_url}" ] && [ "${data.coder_parameter.repo.value}" != "blank" ]; then
      if [ -f "${local.workspace_folder}/.env.example" ] && [ ! -f "${local.workspace_folder}/.env" ]; then
        dispatch_task "dotenv" "Creating .env from .env.example" "
          cp '${local.workspace_folder}/.env.example' '${local.workspace_folder}/.env'

          sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://coder:coder@localhost:5432/metroid_mania_development|' '${local.workspace_folder}/.env'
          sed -i 's|^REDIS_URL=.*|REDIS_URL=redis://localhost:6379/0|' '${local.workspace_folder}/.env'

          # Generate a random SECRET_KEY_BASE if not set
          if grep -q '^SECRET_KEY_BASE=$' '${local.workspace_folder}/.env'; then
            SECRET_HEX=\$(openssl rand -hex 64)
            sed -i \"s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=\$SECRET_HEX|\" '${local.workspace_folder}/.env'
          fi

          echo 'Created .env from .env.example with database and Redis configuration.'
        "
      else
        echo -e "  $${GREEN}✓$${RESET} .env already exists or .env.example not found."
      fi
    fi

    # 3. Environment Config Skeletal Seed
    dispatch_task "skel" "Seeding User Home Files" "
      if [ ! -f ~/.init_done ]; then
        if [ -d /etc/skel ]; then cp -rT /etc/skel ~; fi
        touch ~/.init_done
      fi
    "

    # 4. Install Jetbrains-mono NF
    dispatch_task "nerdfont" "Installing Jetbrains-Mono NF" "
      FONT_URL=\"https://github.com/Acidicts/Coder-ROR/raw/refs/heads/main/JetBrainsMonoNerdFont-Regular.ttf\"
      FONT_NAME=\"JetBrainsMonoNerdFont-Regular.ttf\"
      FONT_DIR=\"/usr/share/fonts/truetype/Jetbrains_Mono_NF\"

      sudo mkdir -p \"\$FONT_DIR\"

      sudo wget -P \"\$FONT_DIR\" \"\$FONT_URL\"
      sudo fc-cache -fv
    "

    # 5. Hackatime and Starship configuration setup
    dispatch_task "wakatime" "Provisioning Hackatime and Starship Configurations" "
      mkdir -p ~/

      curl -sS https://starship.rs/install.sh | sh -s -- -y

      # Always create wakatime config with placeholder
      WAKA_KEY=\"${data.coder_parameter.wakatime_api_key.value}\"
      WAKA_URL=\"${data.coder_parameter.wakatime_api_url.value}\"
      cat > ~/.wakatime.cfg <<WAKAEOF
[settings]
api_url = \$WAKA_URL
api_key = \$WAKA_KEY
hide_filenames = false
WAKAEOF
      chown \$(whoami):\$(whoami) ~/.wakatime.cfg
      chmod 600 ~/.wakatime.cfg

      mkdir -p ~/.config

      wget -P ~/.config https://raw.githubusercontent.com/Acidicts/Coder-ROR/refs/heads/main/starship.toml

      touch ~/.bashrc
      echo 'export WAKATIME_HOME=\"'\$HOME'\"' >> ~/.bashrc
      echo 'export PATH=\"/usr/local/bundle/bin:\$HOME/.npm-global/bin:/usr/local/bin:\$PATH\"' >> ~/.bashrc
      echo 'export PATH=\"./bin:\$PATH\"' >> ~/.bashrc
      if ! grep -q \"starship init\" ~/.bashrc; then
        echo 'eval \"\$(starship init bash)\"' >> ~/.bashrc
      fi
    "

    # 6. Dependency check (curl)
    dispatch_task "curl" "Checking System Dependencies" "
      if ! command -v curl &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y curl
      fi
    "

    # 7. Check Wakatime installed (Multi-fallback resilience)
    dispatch_task "wakatime_install" "Installing Wakatime" "
      export PATH=\"\$HOME/.local/bin:\$PATH\"

      # Check if already installed
      if command -v wakatime &> /dev/null || command -v wakatime-cli &> /dev/null; then
        echo 'Wakatime is already installed.'
        exit 0
      fi

      # Strategy 1: Try pipx if available
      if command -v pipx &> /dev/null; then
        echo 'Attempting install via pipx...'
        pipx install wakatime && exit 0
      fi

      # Strategy 2: Try standard pip/pip3
      if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
        echo 'pipx missing. Attempting install via pip...'
        PIP_CMD=\$(command -v pip3 || command -v pip)
        \$PIP_CMD install --user wakatime && exit 0
      fi

      # Strategy 3: Complete Standalone Binary Fallback (No Python Required)
      echo 'Python environment restricted. Downloading standalone binary...'
      ARCH=\$(uname -m)
      if [ \"\$ARCH\" = \"x86_64\" ]; then
        WAKA_OS=\"linux-amd64\"
      elif [ \"\$ARCH\" = \"aarch64\" ] || [ \"\$ARCH\" = \"arm64\" ]; then
        WAKA_OS=\"linux-arm64\"
      else
        WAKA_OS=\"linux-amd64\"
      fi

      mkdir -p \$HOME/.local/bin
      curl -L -s \"https://github.com/wakatime/wakatime-cli/releases/latest/download/wakatime-cli-\$${WAKA_OS}.zip\" -o /tmp/waka.zip

      # Ensure unzip is present, if not install it or use python to extract
      if command -v unzip &> /dev/null; then
        unzip -q -o /tmp/waka.zip -d \$HOME/.local/bin/
      else
        python3 -c \"import zipfile; zipfile.ZipFile('/tmp/waka.zip').extractall('\$HOME/.local/bin/')\" 2>/dev/null || \
        (sudo apt-get update && sudo apt-get install -y unzip && unzip -q -o /tmp/waka.zip -d \$HOME/.local/bin/)
      fi

      mv \$HOME/.local/bin/wakatime-cli-\$${WAKA_OS} \$HOME/.local/bin/wakatime 2>/dev/null || true
      chmod +x \$HOME/.local/bin/wakatime*
      rm -f /tmp/waka.zip
    "

    # Block and resolve execution wave cleanly
    await_dispatched_tasks

    # ========================================================
    # WAVE 2: Environment Cleansing & Conditional Rails Bootstrapping
    # ========================================================

    # Bootstrap a Rails app safely if a Blank Workspace is selected
    if [ "${data.coder_parameter.repo.value}" = "blank" ]; then
      if [ ! -f "${local.workspace_folder}/Gemfile" ]; then
        %{ if can(regex("^(test|application|destroy|plugin|runner)$", local.active_folder_name)) }
        local_app_name="rails_app"
        %{ else }
        local_app_name="${local.active_folder_name}"
        %{ endif }

        dispatch_task "rails_bootstrap" "Bootstrapping New Rails App Minimal Template" "
          cd '${local.workspace_folder}' && \
          [ -s '\$HOME/.bashrc' ] && source '\$HOME/.bashrc' || true && \
          if ! command -v rails &> /dev/null; then gem install rails --no-document; fi && \
          echo 'Running rails new for '$local_app_name'...' && \
          rails new . --name=\$local_app_name --minimal --keep
        "
        await_dispatched_tasks
      fi
    fi

    dispatch_task "sanitize" "Sanitizing Ruby Gem Environments" "
      cd '${local.workspace_folder}' && \
      export PATH='/usr/local/bundle/bin:\$HOME/.npm-global/bin:/usr/local/bin:\$PATH:./bin' && \
      unset BUNDLE_APP_CONFIG && \
      if [ -f 'Gemfile' ]; then
        export BUNDLE_GEMFILE='${local.workspace_folder}/Gemfile' && \
        bundle config set --local gemfile '${local.workspace_folder}/Gemfile'
      fi
    "

    await_dispatched_tasks

    # Global context exports needed for direct workspace access profile
    export PATH="/usr/local/bundle/bin:$HOME/.npm-global/bin:/usr/local/bin:./bin:$PATH"
    unset BUNDLE_APP_CONFIG
    if [ -f "${local.workspace_folder}/Gemfile" ]; then
      export BUNDLE_GEMFILE="${local.workspace_folder}/Gemfile"
    fi

    # ========================================================
    # WAVE 3: Dependencies Synchronizations
    # ========================================================

    if [ -f "${local.workspace_folder}/Gemfile" ]; then
      dispatch_task "bundle" "Bundle Dependencies Synchronization" "cd '${local.workspace_folder}' && (bundle check || bundle install)"
    fi

    dispatch_task "yarn" "Yarn Assets Synchronization" "
      cd '${local.workspace_folder}' && \
      if [ -f 'package.json' ]; then
        yarn install --frozen-lockfile || yarn install
      else
        echo 'No package.json configuration found.'
      fi
    "

    await_dispatched_tasks

    # ========================================================
    # WAVE 4: Database Setup and Migrations
    # ========================================================

    if [ -f "${local.workspace_folder}/Gemfile" ]; then
      dispatch_task "db_setup" "Database Setup and Migrations" "
        cd '${local.workspace_folder}' && \
        export DATABASE_URL='postgres://coder:coder@localhost:5432/metroid_mania_development' && \
        export REDIS_URL='redis://localhost:6379/0' && \
        export RAILS_ENV=development && \
        bin/rails db:create db:migrate 2>/dev/null || \
        bin/rails db:setup 2>/dev/null || \
        bin/rails db:prepare 2>/dev/null || \
        echo 'Database setup skipped or already configured.'
      "
    fi

    await_dispatched_tasks

    # Cleanup logs
    rm -rf "$LOG_DIR"

    echo -e "$${BOLD}$${GREEN}███████████████████████████████████████████████████████$${RESET}"
    echo -e "$${CYAN}===               Workspace Ready!                  ===$${RESET}"
    echo -e "$${CYAN}===          Running On Ruby 3.4.3 + Rails 8.1      ===$${RESET}"
    echo -e "$${CYAN}===     PostgreSQL: localhost:5432  Redis: 6379     ===$${RESET}"
    echo -e "$${BOLD}$${GREEN}███████████████████████████████████████████████████████$${RESET}\n"
  EOT

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
    WAKATIME_HOME       = "$HOME"
    DATABASE_URL        = "postgres://coder:coder@localhost:5432/metroid_mania_development"
    REDIS_URL           = "redis://localhost:6379/0"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Workspace Disk"
    key          = "3_workspace_disk"
    script       = "du -sh /workspaces/* 2>/dev/null | awk '{print $1 \"iB\"}' | head -1 || echo 'N/A'"
    interval     = 60
    timeout      = 2
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "PostgreSQL"
    key          = "8_postgres"
    script       = "sudo pg_isready -q 2>/dev/null && echo 'Running' || echo 'Stopped'"
    interval     = 30
    timeout      = 2
  }

  metadata {
    display_name = "Redis"
    key          = "9_redis"
    script       = "redis-cli ping 2>/dev/null | grep -q PONG && echo 'Running' || echo 'Stopped'"
    interval     = 30
    timeout      = 2
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
  folder   = local.workspace_folder

  extensions = [
    "esbenp.prettier-vscode",
    "yusifaliyevpro.vscicons",
    "ritwickdey.LiveServer",
    "WakaTime.vscode-wakatime",
    "sst-dev.opencode"
  ]

  settings = {
    "workbench.colorTheme" = "Dark+",
    "workbench.iconTheme" : "icons",
    "editor.semanticHighlighting.enabled" : false,
    "editor.bracketPairColorization.enabled" : true,

    "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'JetBrainsMono NF', Menlo, Monaco, 'Courier New', monospace",
    "editor.fontFamily": "'JetBrainsMono Nerd Font', 'JetBrainsMono NF', Menlo, Monaco, 'Courier New', monospace",

    "editor.language.colorizedBracketPairs" : [
      ["(", ")"],
      ["[", "]"],
      ["{", "}"],
    ],

    "terminal.integrated.defaultProfile.linux": "bash",

    "editor.tokenColorCustomizations" : {
      "textMateRules" : [
        {
          "name" : "Force ERB tags to blue and ignore bracket colorizer",
          "scope" : [
            "punctuation.section.embedded.begin.erb",
            "punctuation.section.embedded.end.erb",
            "punctuation.section.embedded.ruby",
            "punctuation.definition.tag.erb",
            "meta.embedded.block.erb",
            "meta.embedded.line.erb",
          ],
          "settings" : {
            "foreground" : "#569CD6",
          },
        },
        {
          "name" : "Force ERB tags to blue and ignore bracket colorizer",
          "scope" : ["source.ruby.embedded.erb"],
          "settings" : {
            "foreground" : "#D4D4D4",
          },
        },
      ],
    }
  }
}

module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = local.workspace_folder
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id
  item {
    key   = "workspace image"
    value = local.workspace_image
  }
  item {
    key   = "git url"
    value = local.repo_url == "" ? "none (blank workspace)" : local.repo_url
  }
  item {
    key   = "framework"
    value = "Ruby on Rails 8.1"
  }
  item {
    key   = "ruby"
    value = "3.4.3"
  }
}
