---
display_name: DinD Dev Containers
description: A workspace that runs in Dev Containers using Docker in Docker.
icon: ../../../site/static/icon/docker.png
verified: true  
tags: [docker, container, devcontainer, node]  
---

# 在 Dev Containers 中进行远程开发

该模板会配置以下资源：

- Docker 卷：挂载到 `/workspaces`（持久化）
- Docker 卷：挂载到 `/var/lib/docker`（持久化）

这意味着：当工作空间重启时，除 workspaces 目录与 docker 数据目录外的其它工具或文件都不会被保留。
