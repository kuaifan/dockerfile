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
  workspace_image = "kuaifan/coder-dind:0.0.1"
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
  description  = "Enter the URL of the Git repository to clone into your workspace. e.g. https://github.com/coder/coder"
  display_name = "Git Repository"
  mutable      = true
  name         = "repo_url"
  type         = "string"
}

data "coder_parameter" "wireguard_config" {
  default      = ""
  description  = "WireGuard configuration content"
  display_name = "WireGuard Config"
  mutable      = true
  name         = "wireguard_config"
  type         = "string"
  option {
    name  = ""
    value = ""
  }
}

data "coder_parameter" "wireguard_domains" {
  default      = ""
  description  = "Domain list for WireGuard routing (one domain per line)"
  display_name = "WireGuard Domains"
  mutable      = true
  name         = "wireguard_domains"
  type         = "string"
  option {
    name  = ""
    value = ""
  }
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
    
    # Start Docker first
    sudo service docker start

    # Create WireGuard configuration directory
    mkdir -p /home/coder/workspaces/.wireguard
    
    # Save WireGuard config if provided
    if [ -n "${data.coder_parameter.wireguard_config.value}" ]; then
      echo "${data.coder_parameter.wireguard_config.value}" > /home/coder/workspaces/.wireguard/wg0.conf
      chmod 600 /home/coder/workspaces/.wireguard/wg0.conf
      echo "WireGuard config saved"
    fi
    
    # Save WireGuard domains if provided
    if [ -n "${data.coder_parameter.wireguard_domains.value}" ]; then
      echo "${data.coder_parameter.wireguard_domains.value}" > /home/coder/workspaces/.wireguard/domain.txt
      chmod 644 /home/coder/workspaces/.wireguard/domain.txt
      echo "WireGuard domains saved"
    fi
    
    # Then run WireGuard setup if config exists
    if [ -f /home/coder/workspaces/.wireguard/wg0.conf ] && [ -f /home/coder/workspaces/.wireguard/domain.txt ]; then
      echo "Starting WireGuard initialization..."
      sudo WG_CONF="/home/coder/workspaces/.wireguard/wg0.conf" \
           DOMAIN_FILE="/home/coder/workspaces/.wireguard/domain.txt" \
           bash ${path.module}/scripts/init-wireguard.sh \
           || echo "WireGuard setup failed, continuing..."
    fi
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
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
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
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
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
}

resource "coder_script" "init_dind" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Initialize Docker-in-Docker"
  script       = file("${path.module}/scripts/init-dind.sh")
  run_on_start = true
}

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count       = data.coder_parameter.repo_url.value != "" ? data.coder_workspace.me.start_count : 0
  source      = "registry.coder.com/coder/git-clone/coder"
  agent_id    = coder_agent.main.id
  url         = data.coder_parameter.repo_url.value
  base_dir    = "/home/coder/workspaces"
  version     = "~> 1.0"
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/code-server/coder"
  version         = "~> 1.0"
  folder          = data.coder_parameter.repo_url.value != "" ? "/home/coder/workspaces/${trimsuffix(basename(data.coder_parameter.repo_url.value), ".git")}" : "/home/coder/workspaces"
  install_prefix  = "/home/coder/.code-server"
  agent_id        = coder_agent.main.id
  extensions      = [
    "openai.chatgpt", 
    "github.copilot-chat"
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
  folder      = data.coder_parameter.repo_url.value != "" ? "/home/coder/workspaces/${trimsuffix(basename(data.coder_parameter.repo_url.value), ".git")}" : "/home/coder/workspaces"
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
