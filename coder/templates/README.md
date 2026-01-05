---
display_name: Ubuntu 24.04
description: 基于 Ubuntu 24.04 的 DinD 开发容器。
icon: ../../../site/static/icon/ubuntu.svg
verified: true  
tags: [ubuntu, ubuntu-24.04, docker, dind, container, devcontainer, node]  
---

Ubuntu 24.04 · DinD 开发环境
========================================

这是一个基于 Ubuntu 24.04 LTS（noble）的 Dev Container，内置 Docker-in-Docker（DinD），用于在容器内构建与运行 Docker。

持久化目录
----------

- /home/coder：工作目录（持久化）
- /var/lib/docker：Docker 数据目录（持久化）

重启后的行为
------------

工作空间重启后，除以上持久化目录外的其它更改不会保留。需要长期保存的内容，请映射到上述目录或新增卷挂载。

定时任务
-------

- 每天凌晨 5:00 自动清理悬空镜像（`<none>` 标签），日志位于 `/home/coder/.log/docker-prune.log`
