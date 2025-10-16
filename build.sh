#!/bin/bash

cur_path="$(pwd)"

# 允许通配符在未匹配时返回空数组，便于逐目录查找 Dockerfile
shopt -s nullglob

if [ "$#" -gt 0 ]; then
    targets=("$@")
else
    targets=()
    for dir in */; do
        dir="${dir%/}"
        [ -d "$dir" ] || continue
        targets+=("$dir")
    done
fi

for dir in "${targets[@]}"; do
    [ -d "$dir" ] || { echo "::warning::目标 ${dir} 不存在，跳过"; continue; }

    echo "::group::处理目录 $dir"

    configFile="$dir/config.ini"

    # 仅统计一层目录内的 Dockerfile 变体
    mapfile -d '' -t dockerfiles < <(find "$dir" -maxdepth 1 -type f -name '*Dockerfile' -print0)

    # 如果目录下没有 Dockerfile 类型的文件则跳过
    if [ ${#dockerfiles[@]} -eq 0 ]; then
        echo "::notice::目录 $dir 未找到任何 Dockerfile，跳过"
        echo "::endgroup::"
        continue
    fi

    imageName="kuaifan/$dir"
    imageTag="latest"
    imageForce="no"

    # 判断是否存在 config 文件
    if [ -f "$configFile" ]; then
        echo "::notice::读取配置文件 $configFile"
        while IFS= read -r line; do
            if [[ $line =~ "imageName" ]]; then
                imageName=${line#*=}
                continue
            fi
            if [[ $line =~ "imageTag" ]]; then
                imageTag=${line#*=}
                continue
            fi
            if [[ $line =~ "imageForce" ]]; then
                imageForce=${line#*=}
                continue
            fi
        done < "$configFile"
    fi

    # 确保默认 Dockerfile 优先构建
    orderedDockerfiles=()
    for dockerfile in "${dockerfiles[@]}"; do
        baseName="$(basename "$dockerfile")"
        if [ "$baseName" = "Dockerfile" ]; then
            orderedDockerfiles=("$dockerfile" "${orderedDockerfiles[@]}")
        else
            orderedDockerfiles+=("$dockerfile")
        fi
    done

    for dockerfilePath in "${orderedDockerfiles[@]}"; do
        dockerfileName="$(basename "$dockerfilePath")"
        variantTag="$imageTag"
        dockerfileArg=()

        if [ "$dockerfileName" != "Dockerfile" ]; then
            variant="${dockerfileName%.Dockerfile}"
            variantTag="${variant}-${imageTag}"
            dockerfileArg=(-f "$dockerfileName")
            echo "::notice::检测到变体 Dockerfile $dockerfileName，目标标签 ${variantTag}"
        else
            echo "::notice::使用默认 Dockerfile 构建标签 ${variantTag}"
        fi

        echo "-------------------"
        echo "${imageName}:${variantTag}"

        if [ "$imageForce" = "yes" ]; then
            echo "Force push"
            response=404
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" -X GET -u "$DOCKERHUB_USERNAME:$DOCKERHUB_TOKEN" "https://hub.docker.com/v2/repositories/$imageName/tags/$variantTag" || echo "404")
        fi

        if [ "$response" = 200 ]; then
            echo "Already exists"
            echo "::notice::镜像 ${imageName}:${variantTag} 已存在，跳过构建"
            continue
        fi

        mkdir -p "${dir}/private-repo"

        # 复制可选的私有资源（为空时跳过以避免报错）
        if compgen -G "${cur_path}/private-repo/*" > /dev/null; then
            cp -r ${cur_path}/private-repo/* "${dir}/private-repo"
        fi
        
        echo "Start building..."
        pushd "$dir" > /dev/null
        
        # 默认构建变体标签；如果是标准 Dockerfile 再额外标记 latest 以兼容旧引用
        tags=("--tag" "${imageName}:${variantTag}")
        if [ "$dockerfileName" = "Dockerfile" ] && [ "$variantTag" != "latest" ]; then
            tags+=("--tag" "${imageName}:latest")
        fi
        if docker buildx build --platform linux/amd64,linux/arm64 "${tags[@]}" "${dockerfileArg[@]}" . --push; then
            echo "✅ Build successfully"
        else
            echo "❌ Build failed"
            popd > /dev/null
            exit 1
        fi
        popd > /dev/null
    done
    echo "::endgroup::"
done
