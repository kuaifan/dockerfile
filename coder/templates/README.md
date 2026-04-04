---
display_name: Ubuntu 24.04
description: 基于 Ubuntu 24.04 的 Sysbox DinD 开发容器。
icon: ../../../site/static/icon/ubuntu.svg
verified: true  
tags: [ubuntu, ubuntu-24.04, docker, dind, sysbox, container, devcontainer, node, arm64]  
---

Ubuntu 24.04 · Sysbox DinD 开发环境（arm64）
========================================

基于 Ubuntu 24.04 LTS（noble）的 Dev Container，使用 Sysbox 运行时提供安全的 Docker-in-Docker（DinD），无需特权模式。

架构
----

- 目标架构：**arm64**（`arch = "arm64"`）

宿主机前置条件
--------------

1. **安装 Sysbox**

   ```bash
   wget https://downloads.nestybox.com/sysbox/releases/v0.6.7/sysbox-ce_0.6.7-0.linux_arm64.deb
   dpkg -i sysbox-ce_0.6.7-0.linux_arm64.deb
   ```

2. **创建 Docker 网络**（一次性）

   ```bash
   docker network create coder-workspace-network
   ```

3. **配置插件定时下载**（可选）

   将 `coder/resources/download-code-server-extensions.sh` 放到宿主机 `/home/coder/.code-vsixs/` 目录并设置 cron：

   ```bash
   mkdir -p /home/coder/.code-vsixs
   cp coder/resources/download-code-server-extensions.sh /home/coder/.code-vsixs/
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
