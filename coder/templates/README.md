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

2. **创建 Docker 网络**（一次性）

   ```bash
   docker network create --label coder.label="默认网络" coder-network-default
   ```

   「工作区网络」下拉框会自动列出宿主机上所有以 `coder-network-` 开头的 Docker 网络。下拉框优先显示网络的 `coder.label` 标签，没有这个标签就显示网络名。存在 `coder-network-default` 时它是默认选项。没有匹配的网络时，工作区无法创建或启动。

   > 模板通过 `docker network ls` 获取网络列表，所以 Coder provisioner 运行环境里必须装有 `docker` CLI，并且能连上宿主机的 Docker（挂载 `/var/run/docker.sock` 或设置 `DOCKER_HOST`）。

   > 下拉框中的网络列表在发布模板时生成。新建的网络可以先通过「自定义」填写网络名使用，重新发布模板后才会出现在下拉框中。

3. **创建分流网络**（可选，一次性）

   如果需要让一组工作区通过路由器的另一条线路访问外网，创建专用 Docker bridge 网络：

   ```bash
   docker network create \
     --driver bridge \
     --subnet=172.31.0.0/24 \
     --gateway=172.31.0.1 \
     --label coder.label="办公线路" \
     -o com.docker.network.host_ipv4=192.168.101.24 \
     coder-network-office
   ```

   工作区选择这个网络（下拉框显示为“办公线路”）后，就会加入 `coder-network-office`。`com.docker.network.host_ipv4` 让 Docker 把该网络出宿主机的流量 SNAT 成指定的局域网源 IP（这里是 `192.168.101.24`），路由器即可按这个源 IP 分流。SNAT 规则由 Docker 自己生成和维护，Docker 或宿主机重启后自动恢复。

   `192.168.101.24` 必须是宿主机已配置的静态地址，并从路由器 DHCP 地址池中排除。地址不存在时，这个网络里的工作区无法访问外网。

   验证：`sudo iptables -t nat -S POSTROUTING | grep 172.31.0.0` 应该看到 `-j SNAT --to-source 192.168.101.24`。

   > 网络选项创建后不能修改。已有网络要改源 IP 时，先停掉使用它的工作区，然后执行 `docker network rm`，再用同名、同标签重建。模板按网络名引用，所以不用重新发布模板。

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
