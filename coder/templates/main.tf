terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  workspace_image_base     = "kuaifan/coder"
  workspace_image_version  = "0.0.3"
  workspace_image_variants = [
    {
      key        = "default"
      label      = "默认环境"
      version    = local.workspace_image_version
    },
    {
      key        = "golang"
      label      = "Go 环境"
      version    = format("golang-%s", local.workspace_image_version)
    },
    {
      key        = "php"
      label      = "PHP 环境"
      version    = format("php-%s", local.workspace_image_version)
    },
    {
      key        = "python"
      label      = "Python 环境"
      version    = format("python-%s", local.workspace_image_version)
    },
    {
      key        = "pgp"
      label      = "PHP + Go + Python 环境"
      version    = format("pgp-%s", local.workspace_image_version)
    }
  ]
  workspace_image_options = [
    for variant in local.workspace_image_variants : {
      name  = variant.label
      value = variant.key
      image = format("%s:%s", local.workspace_image_base, variant.version)
    }
  ]
  workspace_image_map            = { for option in local.workspace_image_options : option.value => option.image }
  workspace_default_image_key    = element(local.workspace_image_options, 0).value
  workspace_selection_image_key  = trimspace(data.coder_parameter.workspace_image.value)
  workspace_effective_image_key  = local.workspace_selection_image_key != "" ? local.workspace_selection_image_key : local.workspace_default_image_key
  workspace_final_image          = lookup(local.workspace_image_map, local.workspace_effective_image_key, element(local.workspace_image_options, 0).image)
  jetbrains_ide_defaults = {
    default = "IU"
    golang  = "GO"
    php     = "PS"
    python  = "PY"
    pgp     = "IU"
  }
  jetbrains_default_ide = lookup(local.jetbrains_ide_defaults, local.workspace_effective_image_key, "IU")
}

provider "coder" {}
provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "workspace_image" {
  default      = local.workspace_default_image_key
  description  = "选择用于工作区的基础镜像。"
  display_name = "工作区镜像"
  mutable      = true
  name         = "workspace_image"
  type         = "string"
  form_type    = "dropdown"
  order        = 0
  dynamic "option" {
    for_each = local.workspace_image_options
    content {
      name  = option.value.name
      value = option.value.value
    }
  }
}


# 工作区主代理：负责启动脚本、环境变量及资源监控指标
resource "coder_agent" "main" {
  arch            = "amd64"
  os              = "linux"
  startup_script  = <<-EOT
    set -e
    if [ ! -f /home/coder/.init_done ]; then
      cp -rT /etc/skel /home/coder
      touch /home/coder/.init_done
    fi

    # Create necessary directories
    if [ ! -d /home/coder/workspaces ]; then
      mkdir -p /home/coder/workspaces
    fi
    if [ ! -d /home/coder/.log ]; then
      mkdir -p /home/coder/.log
    fi
    if [ ! -d /home/coder/go ]; then
      mkdir -p /home/coder/go
    fi

    # Install oh-my-bash if not installed
    if [ ! -d /home/coder/.oh-my-bash ]; then
      bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
    fi

    # 移除过期的 Yarn 源
    sudo rm -f /etc/apt/sources.list.d/yarn.list 2>/dev/null || true

    # Start Docker first
    sudo service docker start

    # Setup daily docker prune cron job at 5:00 AM (clean dangling images only)
    sudo service cron start
    CRON_JOB="0 5 * * * /usr/bin/docker image prune -f >> /home/coder/.log/docker-prune.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "docker.*prune" || true ; echo "$CRON_JOB") | crontab -
  EOT
  shutdown_script = <<-EOT
    set -e
    docker system prune -a -f
    sudo service docker stop
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
    WORKSPACE_IMAGE_KEY = local.workspace_effective_image_key
    ARCH                = "amd64"
  }

  metadata {
    display_name = "CPU 使用率"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "内存使用率"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home 磁盘"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU 使用率（宿主机）"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "内存使用率（宿主机）"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "平均负载（宿主机）"
    key          = "6_load_host"
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "交换分区使用率（宿主机）"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

# 安装/更新 CLI 工具：后台运行、不阻塞工作区就绪，输出在工作区 UI 的脚本日志中可见
resource "coder_script" "cli_setup" {
  agent_id           = coder_agent.main.id
  display_name       = "CLI 工具安装"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -e
    wget -qO- https://raw.githubusercontent.com/kuaifan/dockerfile/refs/heads/main/coder/resources/cli-setup.sh | python3
  EOT
}

# 安装 code-server 扩展：后台运行、不阻塞工作区就绪，输出在工作区 UI 的脚本日志中可见
resource "coder_script" "code_extensions" {
  agent_id           = coder_agent.main.id
  display_name       = "code-server 扩展安装"
  icon               = "/icon/code.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    vsix_base_dir="/home/coder/.code-vsixs"
    extensions_dir="/home/coder/.code-extensions"
    env_key="$${WORKSPACE_IMAGE_KEY:-default}"
    delay=1
    max_attempts=300

    if [ ! -d "$${vsix_base_dir}" ]; then
      echo "$${vsix_base_dir} not found; skipping extension installation."
      exit 0
    fi
    mkdir -p "$${extensions_dir}"

    # Wait for code-server to be available
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
      if command -v code-server >/dev/null 2>&1; then
        echo "code-server detected after $${attempt} attempt(s)."
        sleep 5
        break
      fi
      echo "Waiting for code-server installation... attempt $${attempt}/$${max_attempts}"
      sleep "$${delay}"
    done

    if ! command -v code-server >/dev/null 2>&1; then
      echo "code-server unavailable after $$(($${max_attempts} * $${delay})) seconds; skipping extension installation."
      exit 0
    fi

    # Function to install extensions from a directory
    install_from_dir() {
      local dir="$1"
      local dir_name=$(basename "$${dir}")

      if [ ! -d "$${dir}" ]; then
        echo "Directory $${dir} does not exist, skipping."
        return
      fi

      local vsix_files=("$${dir}"/*.vsix)
      if [ "$${vsix_files[0]}" = "$${dir}/*.vsix" ]; then
        echo "No VSIX files found in $${dir}, skipping."
        return
      fi

      echo "Installing extensions from $${dir_name}..."
      local vsix
      for vsix in "$${vsix_files[@]}"; do
        [ -f "$${vsix}" ] || continue

        local vsix_name=$(basename "$${vsix}")
        local installed_marker="$${extensions_dir}/.installed_$${vsix_name}"

        if [ -f "$${installed_marker}" ]; then
          echo "  Skipping $${vsix_name} (already installed previously)."
          continue
        fi

        echo "  Installing $${vsix_name}..."
        if code-server --extensions-dir "$${extensions_dir}" --force --install-extension "$${vsix}"; then
          touch "$${installed_marker}"
          echo "  Successfully installed $${vsix_name}."
        else
          echo "  Failed to install $${vsix_name}."
        fi
      done
    }

    # Install common extensions first
    install_from_dir "$${vsix_base_dir}/common"

    # Install environment-specific extensions (skip for default environment)
    if [ "$${env_key}" = "pgp" ]; then
      # Combined environment pulls PHP + Go + Python extensions
      for lang_dir in php golang python; do
        install_from_dir "$${vsix_base_dir}/$${lang_dir}"
      done
    elif [ "$${env_key}" != "default" ]; then
      install_from_dir "$${vsix_base_dir}/$${env_key}"
    fi

    echo "Extension installation completed for environment: $${env_key}"
  EOT
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/code-server/coder"
  version         = "~> 1.0"
  folder          = "/home/coder/workspaces"
  install_prefix  = "/home/coder/.code-server"
  agent_id        = coder_agent.main.id
  extensions_dir  = "/home/coder/.code-extensions"
  settings        = {
    "terminal.integrated.defaultProfile.linux" = "fish"
    "terminal.integrated.profiles.linux" = {
      "Claude Code": {
        "path": "claude",
        "args": [],
        "icon": "robot"
      }
    }
    "workbench.colorTheme" = "Default Dark Modern"
    "window.menuBarVisibility" = "classic"
    "remote.autoForwardPorts" = false
  }
}

# See https://registry.coder.com/modules/coder/cursor
module "cursor" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/cursor/coder"
  version     = "~> 1.0"
  agent_id    = coder_agent.main.id
  folder      = "/home/coder/workspaces/"
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/workspaces"
  default  = [local.jetbrains_default_ide]
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
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

resource "docker_volume" "docker_volume" {
  name = "coder-${data.coder_workspace.me.id}-docker"
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

data "docker_network" "workspace_network" {
  name = "coder-workspace-network"
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = local.workspace_final_image
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  command = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  runtime = "sysbox-runc"

  networks_advanced {
    name = data.docker_network.workspace_network.name
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/home/coder/.code-vsixs"
    host_path      = "/home/coder/.code-vsixs"
    read_only      = true
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
