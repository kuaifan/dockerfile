terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    external = {
      source = "hashicorp/external"
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
  workspace_memory_options = [
    for gb in [8, 16, 24, 32, 48] : {
      key   = tostring(gb)
      label = format("%d GB", gb)
    }
  ]
  workspace_memory_default = "24"
  # 宿主机上以该前缀开头的 Docker 网络会出现在「工作区网络」下拉框中
  workspace_network_prefix    = "coder-network-"
  # 网络上设置该 label 时用作下拉框显示名，否则显示网络名
  workspace_network_label_key = "coder.label"
  # 网络名 => 显示名
  workspace_networks = {
    for name, label in data.external.workspace_networks.result :
    name => trimspace(label) != "" ? trimspace(label) : name
  }
  workspace_network_names   = sort(keys(local.workspace_networks))
  # 下拉框中「自定义」选项的值，Docker 网络名不能以下划线开头，不会与真实网络冲突
  workspace_network_custom  = "__custom__"
  workspace_network_default = (
    contains(local.workspace_network_names, "coder-network-default") ? "coder-network-default" :
    length(local.workspace_network_names) > 0 ? local.workspace_network_names[0] : local.workspace_network_custom
  )
  workspace_network_options = concat(
    [for name in local.workspace_network_names : { name = local.workspace_networks[name], value = name }],
    [{ name = "自定义", value = local.workspace_network_custom }]
  )
  workspace_network_selection = trimspace(data.coder_parameter.workspace_network.value)
  # 自定义输入可以填完整网络名，也可以只填前缀之后的部分
  workspace_network_custom_input = trimspace(try(data.coder_parameter.workspace_network_custom[0].value, ""))
  workspace_network_name = (
    local.workspace_network_selection != local.workspace_network_custom ? local.workspace_network_selection :
    startswith(local.workspace_network_custom_input, local.workspace_network_prefix) ? local.workspace_network_custom_input :
    "${local.workspace_network_prefix}${local.workspace_network_custom_input}"
  )
  jetbrains_ide_defaults   = {
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

data "coder_parameter" "workspace_memory" {
  default      = local.workspace_memory_default
  description  = "容器内存上限（含内嵌 Docker 构建），超出会被 OOM 终止。"
  display_name = "内存上限"
  mutable      = true
  name         = "workspace_memory"
  type         = "string"
  form_type    = "dropdown"
  order        = 1
  dynamic "option" {
    for_each = local.workspace_memory_options
    content {
      name  = option.value.label
      value = option.value.key
    }
  }
}

# 列出宿主机上匹配前缀的 Docker 网络，输出 {"网络名": "label"}（external 只接受字符串到字符串的映射）
data "external" "workspace_networks" {
  program = ["sh", "-c", <<-EOT
    set -eu
    networks=$(docker network ls --format '{{.Name}}\t{{.Label "${local.workspace_network_label_key}"}}')
    printf '%s\n' "$networks" | awk -F '\t' -v prefix='${local.workspace_network_prefix}' '
      function json(s) {
        gsub(/[[:cntrl:]]/, "", s)
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        return "\"" s "\""
      }
      BEGIN { printf "{"; n = 0 }
      $1 != "" && index($1, prefix) == 1 { printf "%s%s:%s", (n++ ? "," : ""), json($1), json($2) }
      END { print "}" }
    '
  EOT
  ]
}

data "coder_parameter" "workspace_network" {
  default      = local.workspace_network_default
  description  = "工作区加入的 Docker 网络。"
  display_name = "工作区网络"
  mutable      = true
  name         = "workspace_network"
  type         = "string"
  form_type    = "dropdown"
  order        = 2
  # 用一个有序列表生成全部选项：网络按名称排序，「自定义」固定在最后
  dynamic "option" {
    for_each = local.workspace_network_options
    content {
      name  = option.value.name
      value = option.value.value
    }
  }
}

# 选择「自定义」时出现，用于填写下拉框中没有的网络（例如模板发布后新建的网络）
data "coder_parameter" "workspace_network_custom" {
  count        = local.workspace_network_selection == local.workspace_network_custom ? 1 : 0
  description  = "填写网络名，可省略 ${local.workspace_network_prefix} 前缀。"
  display_name = "自定义网络"
  mutable      = true
  name         = "workspace_network_custom"
  type         = "string"
  order        = 3
  validation {
    # 允许空值，避免刚选「自定义」时就报错；未填写时由必填检查拦下
    regex = "^([a-zA-Z0-9][a-zA-Z0-9_.-]*)?$"
    error = "网络名只能包含字母、数字、点、下划线和中划线，且以字母或数字开头。"
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
  install_prefix  = "/home/coder/.code-server"
  agent_id        = coder_agent.main.id
  extensions_dir  = "/home/coder/.code-extensions"
  settings        = {
    "window.menuBarVisibility"    = "classic"
    "telemetry.telemetryLevel"    = "off"
    "workbench.enableExperiments" = false
  }
  machine_settings = {
    "files.watcherExclude" = {
      "**/.git/objects/**"        = true
      "**/.git/subtree-cache/**"  = true
      "**/node_modules/**"        = true
      "**/dist/**"                = true
      "**/.cache/**"              = true
      "**/.gradle/**"             = true
      "**/go/pkg/**"              = true
    }
    "search.exclude" = {
      "**/vendor"  = true
      "**/dist"    = true
      "**/build"   = true
      "**/target"  = true
      "**/.next"   = true
      "**/go/pkg"  = true
    }
    "workbench.colorTheme"    = "Default Dark Modern"
    "remote.autoForwardPorts" = false
    "search.followSymlinks"   = false
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
  name = local.workspace_network_name

  lifecycle {
    precondition {
      condition     = length(local.workspace_network_names) > 0
      error_message = "宿主机上没有以 ${local.workspace_network_prefix} 开头的 Docker 网络，请先创建，例如：docker network create ${local.workspace_network_prefix}default"
    }
    precondition {
      condition     = local.workspace_network_selection != local.workspace_network_custom || local.workspace_network_custom_input != ""
      error_message = "请填写自定义网络名。"
    }
    precondition {
      condition     = contains(local.workspace_network_names, local.workspace_network_name)
      error_message = "网络 \"${local.workspace_network_name}\" 不存在，可选网络：${join(", ", local.workspace_network_names)}"
    }
  }
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

  # 内存限制（MB）；memory_swap 与 memory 相等即禁用 swap，避免宿主机 swap 抖动
  memory             = tonumber(data.coder_parameter.workspace_memory.value) * 1024
  memory_swap        = tonumber(data.coder_parameter.workspace_memory.value) * 1024
  memory_reservation = tonumber(data.coder_parameter.workspace_memory.value) * 768

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
