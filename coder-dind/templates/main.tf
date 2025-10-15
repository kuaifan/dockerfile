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
  workspace_image = "kuaifan/coder-dind:0.0.6"
  repo_url_lines  = [for line in split("\n", replace(data.coder_parameter.repo_url.value, "\r", "")) : trimspace(line)]
  repo_url_inputs = [for line in local.repo_url_lines : line if line != ""]
  repo_primary_folder = length(local.repo_url_inputs) == 1 ? "/home/coder/workspaces/${trimsuffix(basename(element(local.repo_url_inputs, 0)), ".git")}" : "/home/coder/workspaces"
  docker_port_lines = [for line in split("\n", replace(data.coder_parameter.docker_ports.value, "\r", "")) : trimspace(line)]
  docker_port_inputs = [for line in local.docker_port_lines : line if line != ""]
  docker_ports = [
    for entry in local.docker_port_inputs : trimspace(entry)
    if length(regexall("(?i)^\\d+(?::\\d+)?(?:/(tcp|udp))?$", trimspace(entry))) > 0
  ]
  docker_port_entries = [
    for entry in local.docker_ports : {
      numbers  = regexall("\\d+", entry)
      protocol = lower(trimspace(try(element(split("/", entry), 1), "tcp")))
    }
    if length(regexall("\\d+", entry)) > 0
  ]
  docker_port_mappings = [
    for entry in local.docker_port_entries : {
      external = tonumber(element(entry.numbers, 0))
      internal = tonumber(try(element(entry.numbers, 1), element(entry.numbers, 0)))
      protocol = contains(["tcp", "udp"], entry.protocol) ? entry.protocol : "tcp"
    }
  ]
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

data "coder_parameter" "repo_url" {
  default      = ""
  description  = "（可选）输入需要克隆到工作区的 Git 仓库 URL（每行一个）。"
  display_name = "Git 仓库"
  mutable      = true
  name         = "repo_url"
  type         = "string"
  form_type    = "textarea"
  order        = 1
  styling = jsonencode({
    placeholder = <<-EOT
    例如
    https://github.com/username/repository.git
    https://gitlab.com/org/project.git
    EOT
  })
}

data "coder_parameter" "docker_ports" {
  default      = ""
  description  = "（可选）列出需要从工作区容器暴露的端口，每行一个端口或映射。"
  display_name = "Docker 端口"
  mutable      = true
  name         = "docker_ports"
  type         = "string"
  form_type    = "textarea"
  order        = 2
  styling = jsonencode({
    placeholder = <<-EOT
    例如
    80
    443
    8080:80
    53/udp
    10053:53/udp
    EOT
  })
}

resource "coder_agent" "main" {
  arch            = data.coder_provisioner.me.arch
  os              = "linux"
  startup_script  = <<-EOT
    set -e
    if [ ! -f /home/coder/.init_done ]; then
      cp -rT /etc/skel /home/coder
      touch /home/coder/.init_done
    fi

    if [ ! -d /home/coder/.oh-my-bash ]; then
      bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
    fi

    # Start Docker first
    sudo service docker start

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

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  for_each    = data.coder_workspace.me.start_count > 0 ? { for idx, url in local.repo_url_inputs : "${tostring(data.coder_workspace.me.start_count)}-${tostring(idx)}" => url } : {}
  source      = "registry.coder.com/coder/git-clone/coder"
  agent_id    = coder_agent.main.id
  url         = each.value
  base_dir    = "/home/coder/workspaces"
  version     = "~> 1.0"
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/code-server/coder"
  version         = "~> 1.0"
  folder          = local.repo_primary_folder
  install_prefix  = "/home/coder/.code-server"
  agent_id        = coder_agent.main.id
  extensions      = [
    "github.copilot-chat",
    "openai.chatgpt"
  ]
  extensions_dir  = "/home/coder/.code-extensions"
  settings        = {
    "terminal.integrated.defaultProfile.linux" = "fish"
    "workbench.colorTheme" = "Default Dark Modern"
    "window.menuBarVisibility" = "classic"
  }
}

# See https://registry.coder.com/modules/coder/cursor
module "cursor" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/cursor/coder"
  version     = "~> 1.0"
  agent_id    = coder_agent.main.id
  folder      = local.repo_primary_folder
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

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = local.workspace_image
  privileged = true
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  command = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  dynamic "ports" {
    for_each = local.docker_port_mappings
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = ports.value.protocol
    }
  }
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
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
