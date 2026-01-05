#!/usr/bin/env bash

# 本脚本用于根据指定的 code-server/VS Code 版本，自动查询并下载所需扩展的 VSIX 安装包。
# 将脚本放在任意目录并执行后，会把所有匹配的扩展下载到脚本所在的目录，方便离线安装。
#
# 使用方式:
#   ./download-code-server-extensions.sh            # 自动模式（默认），使用最新版本和默认插件
#   ./download-code-server-extensions.sh --manual   # 交互模式，提示用户输入

# 下载的扩展将保存到脚本所在目录，并缓存用户输入
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_FILE="$SCRIPT_DIR/.download-code-server-extensions.cache"

# 检查是否为手动模式（默认为自动模式）
AUTO_MODE=true
if [ "$1" = "--manual" ]; then
    AUTO_MODE=false
fi

# 从缓存读取上一次的输入
load_cache() {
    if [ -f "$CACHE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CACHE_FILE"
    fi
}

# 将当前输入写入缓存
save_cache() {
    {
        printf 'LAST_VSCODE_VERSION=%q\n' "$VSCODE_VERSION"
        printf 'LAST_EXTENSIONS=%q\n' "$EXTENSIONS"
    } > "$CACHE_FILE"
}

# 获取最新的 VS Code 版本
get_latest_vscode_version() {
    echo "正在获取最新的 VS Code 版本..." >&2
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/microsoft/vscode/releases/latest" | jq -r '.tag_name' | sed 's/^v//')

    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "错误：无法获取最新的 VS Code 版本" >&2
        return 1
    fi

    echo "获取到最新版本：$latest_version" >&2
    echo "$latest_version"
    return 0
}

# 提示输入 VS Code 版本，默认使用之前的固定版本
get_vscode_version() {
    if [ "$AUTO_MODE" = true ]; then
        get_latest_vscode_version
        return $?
    fi

    local default_version="${LAST_VSCODE_VERSION:-"1.105.1"}"
    read -r -p "请输入 VS Code 版本 (默认 ${default_version}): " user_version
    if [ -z "$user_version" ]; then
        echo "$default_version"
    else
        echo "$user_version"
    fi
}

# 定义各环境的扩展配置
# 格式：名称|子目录|扩展列表（空格分隔）
# 注意：这些扩展优化用于 code-server 远程环境，重点考虑性能和实用性
declare -a EXTENSION_GROUPS=(
    "通用|common|GitHub.copilot GitHub.copilot-chat openai.chatgpt anthropic.claude-code donjayamanne.githistory mhutchie.git-graph dbaeumer.vscode-eslint esbenp.prettier-vscode usernamehw.errorlens streetsidesoftware.code-spell-checker aaron-bond.better-comments christian-kohler.path-intellisense nonoroazoro.syncing oderwat.indent-rainbow wayou.vscode-todo-highlight formulahendry.code-runner ms-azuretools.vscode-docker redhat.vscode-yaml bradlc.vscode-tailwindcss"
    "Golang|golang|golang.go"
    "PHP|php|bmewburn.vscode-intelephense-client xdebug.php-debug"
    "Python|python|ms-python.python ms-python.vscode-pylance ms-python.black-formatter ms-python.isort"
    "Flutter|flutter|Dart-Code.dart-code Dart-Code.flutter"
)

# 提取通用扩展（用于交互模式的默认值）
DEFAULT_COMMON_EXTENSIONS="GitHub.copilot GitHub.copilot-chat openai.chatgpt anthropic.claude-code donjayamanne.githistory mhutchie.git-graph dbaeumer.vscode-eslint esbenp.prettier-vscode usernamehw.errorlens streetsidesoftware.code-spell-checker aaron-bond.better-comments christian-kohler.path-intellisense nonoroazoro.syncing oderwat.indent-rainbow wayou.vscode-todo-highlight formulahendry.code-runner ms-azuretools.vscode-docker redhat.vscode-yaml"

# 提示输入扩展 ID 列表
get_extensions() {
    local default_extensions="${LAST_EXTENSIONS:-"$DEFAULT_COMMON_EXTENSIONS"}"

    if [ "$AUTO_MODE" = true ]; then
        echo "使用默认扩展列表：$default_extensions" >&2
        echo "$default_extensions"
        return 0
    fi

    read -r -p "请输入扩展 ID 列表，使用空格分隔 (默认 ${default_extensions}): " user_extensions
    if [ -z "$user_extensions" ]; then
        echo "$default_extensions"
    else
        echo "$user_extensions"
    fi
}

# 查找与 VS Code 版本兼容的扩展版本
# 优先返回稳定版（x.y.z 格式），只有在没有稳定版时才返回预览版
find_compatible_version() {
    local extension_id="$1"
    local vscode_version="$2"

    local response
    response=$(curl -s -X POST "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json;api-version=3.0-preview.1" \
        -d "{
            \"filters\": [{
                \"criteria\": [
                    {\"filterType\": 7, \"value\": \"$extension_id\"},
                    {\"filterType\": 12, \"value\": \"4096\"}
                ],
                \"pageSize\": 50
            }],
            \"flags\": 4112
        }")

    # 首先尝试查找稳定版（x.y.z 格式，最多3段）
    local stable_version
    stable_version=$(echo "$response" | jq -r --arg vscode_version "$vscode_version" '
        .results[0].extensions[0].versions[]? |
        select(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]*$")) |
        select(.version | length < 8) |
        {
            version: .version,
            engine: (.properties[]? | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value)
        } |
        select(.engine != null) |
        select(.engine | ltrimstr("^") | split(".") |
            map(split("-")[0] | tonumber?) as $engine_parts |
            ($vscode_version | split(".") | map(tonumber)) as $vscode_parts |
            (
                ($engine_parts[0] // 0) < $vscode_parts[0] or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) < $vscode_parts[1]) or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) == $vscode_parts[1] and ($engine_parts[2] // 0) <= $vscode_parts[2])
            )
        ) |
        .version' 2>/dev/null | head -n 1)

    # 如果找到稳定版，直接返回
    if [ -n "$stable_version" ]; then
        echo "$stable_version"
        return 0
    fi

    # 没有稳定版时，查找预览版（x.y.z.w... 格式，超过3段）
    echo "$response" | jq -r --arg vscode_version "$vscode_version" '
        .results[0].extensions[0].versions[]? |
        select(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]*$")) |
        {
            version: .version,
            engine: (.properties[]? | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value)
        } |
        select(.engine != null) |
        select(.engine | ltrimstr("^") | split(".") |
            map(split("-")[0] | tonumber?) as $engine_parts |
            ($vscode_version | split(".") | map(tonumber)) as $vscode_parts |
            (
                ($engine_parts[0] // 0) < $vscode_parts[0] or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) < $vscode_parts[1]) or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) == $vscode_parts[1] and ($engine_parts[2] // 0) <= $vscode_parts[2])
            )
        ) |
        .version' 2>/dev/null | head -n 1
}

# 将扩展包下载到脚本目录（可选指定子目录）
download_extension() {
    local extension_id="$1"
    local version="$2"
    local subdir="${3:-}"  # 可选的子目录参数
    local publisher extension_name temp_dir package_name download_path target_dir final_path
    publisher=$(echo "$extension_id" | cut -d'.' -f1)
    extension_name=$(echo "$extension_id" | cut -d'.' -f2)
    package_name="${extension_id}-${version}"

    # 确定目标目录
    if [ -n "$subdir" ]; then
        target_dir="$SCRIPT_DIR/$subdir"
        mkdir -p "$target_dir"
    else
        target_dir="$SCRIPT_DIR"
    fi
    final_path="$target_dir/$package_name.vsix"

    # 检查目标版本是否已存在
    if [ -f "$final_path" ]; then
        echo "  ✓ $extension_id v$version 已存在，跳过下载"
        return 0
    fi

    # 删除该扩展的所有旧版本（不同版本号的文件）
    local old_versions_count=0
    while IFS= read -r old_file; do
        if [ -f "$old_file" ]; then
            echo "  - 删除旧版本：$(basename "$old_file")"
            rm -f "$old_file"
            old_versions_count=$((old_versions_count + 1))
        fi
    done < <(find "$target_dir" -maxdepth 1 -type f -name "${extension_id}-*.vsix" 2>/dev/null)

    if [ $old_versions_count -gt 0 ]; then
        echo "  已删除 $old_versions_count 个旧版本"
    fi

    echo "正在下载 $extension_id v$version..."

    temp_dir="$(mktemp -d)"
    download_path="$temp_dir/$package_name.vsix.gz"

    # 下载 VSIX 压缩包
    curl -L "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$extension_name/$version/vspackage" \
        -o "$download_path"

    if [ ! -f "$download_path" ]; then
        echo "  ✗ 下载 $extension_id 失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 解压并移动到目标目录
    if command -v gunzip >/dev/null 2>&1; then
        if ! gunzip -c "$download_path" > "$final_path"; then
            echo "  ✗ 解压 $extension_id 失败"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        if ! gzip -cd "$download_path" > "$final_path"; then
            echo "  ✗ 解压 $extension_id 失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    rm -rf "$temp_dir"

    echo "  ✓ 已保存到 $final_path"
    return 0
}

# 检查所需依赖是否存在
check_dependencies() {
    local missing_deps=()

    # 检查必须的命令
    for cmd in curl jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    # 检查是否存在 gunzip 或 gzip
    if ! command -v gunzip >/dev/null 2>&1 && ! command -v gzip >/dev/null 2>&1; then
        missing_deps+=("gunzip/gzip")
    fi

    if [ "${#missing_deps[@]}" -gt 0 ]; then
        echo "错误：缺少必要的依赖：${missing_deps[*]}"
        echo "请安装缺失的依赖后再执行脚本。"
        exit 1
    fi
}

# 下载一组扩展到指定目录
download_extensions_group() {
    local extensions="$1"
    local subdir="$2"
    local group_name="$3"
    local failed=0

    if [ -n "$group_name" ]; then
        echo ""
        echo "=========================================="
        echo "正在下载 $group_name 扩展..."
        echo "=========================================="
    fi

    # 逐个处理扩展
    for ext in $extensions; do
        echo "正在处理 $ext..."

        # 查找兼容的扩展版本
        version="$(find_compatible_version "$ext" "$VSCODE_VERSION")"

        if [ -z "$version" ]; then
            echo "  ✗ 未找到与 $ext 兼容的版本"
            failed="$((failed + 1))"
        else
            echo "  找到兼容版本：$version"
            if ! download_extension "$ext" "$version" "$subdir"; then
                failed="$((failed + 1))"
            fi
        fi
        echo ""
    done

    return "$failed"
}

# 检查依赖
check_dependencies
load_cache

# 获取（或默认）VS Code 版本
VSCODE_VERSION="$(get_vscode_version)"
if [ $? -ne 0 ] || [ -z "$VSCODE_VERSION" ]; then
    echo "错误：无法获取 VS Code 版本，脚本退出"
    exit 1
fi

echo ""
echo "VS Code 版本：$VSCODE_VERSION"
echo "下载目录：$SCRIPT_DIR"

# 错误计数器
FAILED=0

if [ "$AUTO_MODE" = true ]; then
    # 自动模式：下载所有环境的扩展
    echo "自动模式：将下载通用扩展和各编程语言专用扩展"
    echo ""

    # 遍历下载各组扩展
    for group in "${EXTENSION_GROUPS[@]}"; do
        IFS='|' read -r name subdir extensions <<< "$group"
        download_extensions_group "$extensions" "$subdir" "$name"
        FAILED=$((FAILED + $?))
    done

else
    # 交互模式：按用户输入下载
    echo "交互模式：请手动输入扩展信息"
    echo ""

    EXTENSIONS="$(get_extensions)"
    save_cache

    echo "扩展列表：$EXTENSIONS"
    echo ""

    download_extensions_group "$EXTENSIONS" "" ""
    FAILED=$?
fi

# 下载结果总结
echo ""
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "✓ 所有扩展均已成功下载！"
else
    echo "⚠ 完成，但出现 $FAILED 个错误"
    exit 1
fi
