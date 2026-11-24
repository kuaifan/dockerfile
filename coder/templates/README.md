---
display_name: Ubuntu 24.04
description: 基于 Ubuntu 24.04 的 Sysbox DinD 开发容器。
icon: ../../../site/static/icon/ubuntu.svg
verified: true  
tags: [ubuntu, ubuntu-24.04, docker, dind, sysbox, container, devcontainer, node]  
---

Ubuntu 24.04 · Sysbox DinD 开发环境
========================================

基于 Ubuntu 24.04 LTS（noble）的 Dev Container，使用 Sysbox 运行时提供安全的 Docker-in-Docker（DinD），无需特权模式。

架构
----

- 目标架构：**amd64**（`arch = "amd64"`）

宿主机前置条件
--------------

1. **安装 Sysbox**

   ```bash
   wget https://downloads.nestybox.com/sysbox/releases/v0.6.7/sysbox-ce_0.6.7-0.linux_amd64.deb
   dpkg -i sysbox-ce_0.6.7-0.linux_amd64.deb
   ```

2. **创建 Docker 网络**（一次性，默认模式）

   ```bash
   docker network create coder-workspace-network
   ```

3. **创建分流网络**（可选，一次性）

   如果需要让一组工作区通过路由器的另一条线路访问外网，创建专用 Docker bridge 网络：

   ```bash
   docker network create \
     --driver bridge \
     --subnet=172.31.0.0/24 \
     --gateway=172.31.0.1 \
     coder-workspace-split
   ```

   选择“分流网络（SNAT）”后，工作区会加入 `coder-workspace-split`。宿主机需要提前配置 SNAT，把该网络的流量转换为指定的局域网源 IP（例如 `192.168.101.24`），路由器即可按这个源 IP 分流。Coder Agent 仍通过普通 Docker 网络工作，不会受到 macvlan 的宿主机隔离影响。

   示例（宿主机网卡为 `ens160`，分流源 IP 为 `192.168.101.24`）：

   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo iptables -t nat -I POSTROUTING 1 \
     -s 172.31.0.0/24 -o ens160 \
     -j SNAT --to-source 192.168.101.24
   ```

   `192.168.101.24` 必须是宿主机已配置的静态地址，并从路由器 DHCP 地址池中排除。SNAT 和转发规则需要在宿主机上持久化，避免重启后失效。

4. **配置插件定时下载**（可选）
   ```bash
   mkdir -p /home/coder/.code-vsixs
   wget -O /home/coder/.code-vsixs/download-code-server-extensions.sh https://raw.githubusercontent.com/kuaifan/dockerfile/refs/heads/main/coder/resources/download-code-server-extensions.sh
   chmod +x /home/coder/.code-vsixs/download-code-server-extensions.sh
   (crontab -l 2>/dev/null; echo "0 3 * * * /home/coder/.code-vsixs/download-code-server-extensions.sh >> /home/coder/.code-vsixs/download.log 2>&1") | crontab -
   ```

持久化目录
----------

- `/home/coder` — 工作目录（持久化）
- `/var/lib/docker` — Docker 数据目录（持久化）
- `/home/coder/.code-vsixs` — code-server 插件（只读挂载自宿主机）

重启后的行为
------------

工作空间重启后，除以上持久化目录外的其它更改不会保留。需要长期保存的内容，请映射到上述目录或新增卷挂载。

定时任务
-------

- 每天凌晨 5:00 自动清理悬空镜像（`<none>` 标签），日志位于 `/home/coder/.log/docker-prune.log`
