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
  workspace_image = "kuaifan/coder-dind:0.0.4"
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
  description  = "(Optional) Enter the URL of the Git repository to clone into your workspace."
  display_name = "Git Repository"
  mutable      = true
  name         = "repo_url"
  type         = "string"
  order        = 1
  styling = jsonencode({
    placeholder = "https://github.com/username/repository.git"
  })
}

data "coder_parameter" "docker_ports" {
  default      = ""
  description  = "(Optional) List of ports to expose from the workspace container. One port or mapping per line."
  display_name = "Docker Ports"
  mutable      = true
  name         = "docker_ports"
  type         = "string"
  form_type    = "textarea"
  order        = 2
  styling = jsonencode({
    placeholder = <<-EOT
    e.g.
    80
    443
    8080:80
    53/udp
    10053:53/udp
    EOT
  })
}

data "coder_parameter" "wireguard_config" {
  default      = ""
  description  = "(Optional) WireGuard configuration content"
  display_name = "WireGuard Config"
  mutable      = true
  name         = "wireguard_config"
  type         = "string"
  form_type    = "textarea"
  order        = 3
  styling = jsonencode({
    placeholder = <<-EOT
    e.g.
    [Interface]
    PrivateKey = your_private_key_here
    Address = 10.0.0.2/32
    ...
    [Peer]
    PublicKey = server_public_key_here
    Endpoint = vpn.example.com:51820
    ...
    EOT
  })
}

data "coder_parameter" "wireguard_domains" {
  default      = ""
  description  = "(Optional) Domains/IPs to route through WireGuard. Only these domains/IPs will use VPN, other traffic goes directly. One per line."
  display_name = "WireGuard Split Tunneling"
  mutable      = true
  name         = "wireguard_domains"
  type         = "string"
  form_type    = "textarea"
  order        = 4
  styling = jsonencode({
    placeholder = <<-EOT
    e.g.
    example.com
    google.com
    api.openai.com
    192.168.1.100
    10.0.0.0/24
    2001:db8::1
    ...
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

    # Start Docker first
    sudo service docker start

    # Create WireGuard configuration directory
    mkdir -p /home/coder/.wireguard
    
    # Save WireGuard config if provided
    if [ -n "${data.coder_parameter.wireguard_config.value}" ]; then
      echo "${data.coder_parameter.wireguard_config.value}" > /home/coder/.wireguard/wgdind.conf
      chmod 600 /home/coder/.wireguard/wgdind.conf
      echo "WireGuard config saved"
    fi
    
    # Save WireGuard domains if provided
    if [ -n "${data.coder_parameter.wireguard_domains.value}" ]; then
      echo "${data.coder_parameter.wireguard_domains.value}" > /home/coder/.wireguard/domain.txt
      chmod 644 /home/coder/.wireguard/domain.txt
      echo "WireGuard domains saved"
    fi
    
    # Then run WireGuard setup if config exists
    if [ -f /home/coder/.wireguard/wgdind.conf ] && [ -f /home/coder/.wireguard/domain.txt ]; then
      echo "Starting WireGuard initialization..." \
           | tee /home/coder/.wireguard/wgdind.log
      sudo WG_CONF="/home/coder/.wireguard/wgdind.conf" \
           DOMAIN_FILE="/home/coder/.wireguard/domain.txt" \
           bash /usr/local/bin/wireguard-tools.sh \
           >> /home/coder/.wireguard/wgdind.log 2>&1 \
           || (echo "WireGuard setup failed, continuing..." \
               | tee -a /home/coder/.wireguard/wgdind.log)
    fi
  EOT
  shutdown_script = <<-EOT
    set -e
    docker system prune -a -f
    sudo service docker stop

    # Then run WireGuard cleanup if config exists
    if [ -f /home/coder/.wireguard/wgdind.conf ] && [ -f /home/coder/.wireguard/domain.txt ]; then
      echo "Stopping WireGuard..." \
           | tee -a /home/coder/.wireguard/wgdind.log
      sudo WG_CONF="/home/coder/.wireguard/wgdind.conf" \
           DOMAIN_FILE="/home/coder/.wireguard/domain.txt" \
           bash /usr/local/bin/wireguard-tools.sh down \
           >> /home/coder/.wireguard/wgdind.log 2>&1
    fi
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
    "anthropic.claude-code", 
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
