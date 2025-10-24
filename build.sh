#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage:
  build.sh list
  build.sh build <directory> [Dockerfile]
EOF
    exit 1
}

cmd="${1:-}"
shift || true

cur_path="$(pwd)"

# 允许通配符在未匹配时返回空数组，便于复制私有资源
shopt -s nullglob

case "${cmd}" in
    list)
        python3 - <<'PY'
import json, os, glob
base_entries = []
variant_entries = []
for entry in sorted(os.listdir(".")):
    if not os.path.isdir(entry):
        continue
    matches = glob.glob(os.path.join(entry, "*Dockerfile"))
    if not matches:
        continue
    matches.sort(key=lambda p: (0 if os.path.basename(p) == "Dockerfile" else 1, os.path.basename(p)))
    for path in matches:
        base = os.path.basename(path)
        variant = ""
        if base != "Dockerfile" and base.endswith(".Dockerfile"):
            variant = base[: -len(".Dockerfile")]
        label = entry if not variant else f"{entry} ({variant})"
        entry_data = {"dir": entry, "dockerfile": base, "variant": variant, "label": label}
        if base == "Dockerfile":
            base_entries.append(entry_data)
        else:
            variant_entries.append(entry_data)
base_matrix = {"include": base_entries}
variant_matrix = {"include": variant_entries}
print(f"base_matrix={json.dumps(base_matrix)}")
print(f"variant_matrix={json.dumps(variant_matrix)}")
print(f"has_base_targets={'true' if base_entries else 'false'}")
print(f"has_variant_targets={'true' if variant_entries else 'false'}")
PY
        ;;
    build)
        dir="${1:-}"
        dockerfile="${2:-Dockerfile}"

        if [ -z "$dir" ]; then
            usage
        fi

        if [ ! -d "$dir" ]; then
            echo "::warning::目标 ${dir} 不存在，跳过"
            exit 0
        fi

        dockerfilePath="${dir}/${dockerfile}"
        if [ ! -f "$dockerfilePath" ]; then
            echo "::notice::目录 ${dir} 未找到 Dockerfile ${dockerfile}，跳过"
            exit 0
        fi

        echo "::group::处理目录 ${dir}/${dockerfile}"

        configFile="${dir}/config.ini"
        imageName="kuaifan/${dir}"
        imageTag="latest"
        imageForce="no"

        # 判断是否存在 config 文件
        if [ -f "$configFile" ]; then
            echo "::notice::读取配置文件 ${configFile}"
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

        variantTag="$imageTag"
        dockerfileArg=()

        if [ "$dockerfile" != "Dockerfile" ]; then
            variant="${dockerfile%.Dockerfile}"
            variantTag="${variant}-${imageTag}"
            dockerfileArg=(-f "$dockerfile")
            echo "::notice::检测到变体 Dockerfile ${dockerfile}，目标标签 ${variantTag}"
        else
            echo "::notice::使用默认 Dockerfile 构建标签 ${variantTag}"
        fi

        if [ "$imageForce" = "yes" ]; then
            echo "::notice::强制构建，跳过已存在检查"
            response=404
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" -X GET -u "$DOCKERHUB_USERNAME:$DOCKERHUB_TOKEN" "https://hub.docker.com/v2/repositories/$imageName/tags/$variantTag" || echo "404")
        fi

        if [ "$response" = 200 ]; then
            echo "::notice::镜像 ${imageName}:${variantTag} 已存在，跳过构建"
            echo "::endgroup::"
            exit 0
        fi

        # 复制可选的私有资源（为空时跳过以避免报错）
        mkdir -p "${dir}/private-repo"
        if compgen -G "${cur_path}/private-repo/*" > /dev/null; then
            cp -r "${cur_path}"/private-repo/* "${dir}/private-repo"
        fi

        pushd "$dir" > /dev/null
        echo "::notice::开始构建镜像 ${imageName}:${variantTag}"

        tags=("--tag" "${imageName}:${variantTag}")
        if [ "$dockerfile" = "Dockerfile" ] && [ "$variantTag" != "latest" ]; then
            tags+=("--tag" "${imageName}:latest")
        fi

        if docker buildx build --platform linux/amd64,linux/arm64 "${tags[@]}" "${dockerfileArg[@]}" . --push; then
            echo "::notice::✅ 构建成功"
        else
            echo "::error::❌ 构建失败"
            popd > /dev/null
            exit 1
        fi
        popd > /dev/null

        echo "::endgroup::"
        ;;
    ""|*)
        usage
        ;;
esac
