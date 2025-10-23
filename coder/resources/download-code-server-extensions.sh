#!/usr/bin/env bash

# 本脚本用于根据指定的 code-server/VS Code 版本，自动查询并下载所需扩展的 VSIX 安装包。
# 将脚本放在任意目录并执行后，会把所有匹配的扩展下载到脚本所在的目录，方便离线安装。

# 下载的扩展将保存到脚本所在目录，并缓存用户输入
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_FILE="$SCRIPT_DIR/.download-code-server-extensions.cache"

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

# 提示输入 VS Code 版本，默认使用之前的固定版本
get_vscode_version() {
    local default_version="${LAST_VSCODE_VERSION:-"1.105.1"}"
    read -r -p "请输入 VS Code 版本 (默认 ${default_version}): " user_version
    if [ -z "$user_version" ]; then
        echo "$default_version"
    else
        echo "$user_version"
    fi
}

# 提示输入扩展 ID 列表
get_extensions() {
    local default_extensions="${LAST_EXTENSIONS:-"GitHub.copilot GitHub.copilot-chat openai.chatgpt"}"
    read -r -p "请输入扩展 ID 列表，使用空格分隔 (默认 ${default_extensions}): " user_extensions
    if [ -z "$user_extensions" ]; then
        echo "$default_extensions"
    else
        echo "$user_extensions"
    fi
}

# 查找与 VS Code 版本兼容的扩展版本
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

    echo "$response" | jq -r --arg vscode_version "$vscode_version" '
        .results[0].extensions[0].versions[] |
        select(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]*$")) |
        select(.version | length < 8) |
        {
            version: .version,
            engine: (.properties[] | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value)
        } |
        select(.engine | ltrimstr("^") | split(".") |
            map(split("-")[0] | tonumber?) as $engine_parts |
            ($vscode_version | split(".") | map(tonumber)) as $vscode_parts |
            (
                ($engine_parts[0] // 0) < $vscode_parts[0] or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) < $vscode_parts[1]) or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) == $vscode_parts[1] and ($engine_parts[2] // 0) <= $vscode_parts[2])
            )
        ) |
        .version' | head -n 1
}

# 将扩展包下载到脚本目录
download_extension() {
    local extension_id="$1"
    local version="$2"
    local publisher extension_name temp_dir package_name download_path final_path
    publisher=$(echo "$extension_id" | cut -d'.' -f1)
    extension_name=$(echo "$extension_id" | cut -d'.' -f2)
    temp_dir="$(mktemp -d)"
    package_name="${extension_id}-${version}"
    download_path="$temp_dir/$package_name.vsix.gz"
    final_path="$SCRIPT_DIR/$package_name.vsix"

    echo "正在下载 $extension_id v$version..."

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

# 检查依赖
check_dependencies
load_cache

# 获取（或默认）VS Code 版本
VSCODE_VERSION="$(get_vscode_version)"
EXTENSIONS="$(get_extensions)"
save_cache

echo ""
echo "VS Code 版本：$VSCODE_VERSION"
echo "扩展列表：$EXTENSIONS"
echo "下载目录：$SCRIPT_DIR"
echo ""

# 错误计数器
FAILED=0

# 逐个处理扩展
for ext in $EXTENSIONS; do
    echo "正在处理 $ext..."

    # 查找兼容的扩展版本
    version="$(find_compatible_version "$ext" "$VSCODE_VERSION")"

    if [ -z "$version" ]; then
        echo "  ✗ 未找到与 $ext 兼容的版本"
        FAILED="$((FAILED + 1))"
    else
        echo "  找到兼容版本：$version"
        if ! download_extension "$ext" "$version"; then
            FAILED="$((FAILED + 1))"
        fi
    fi
    echo ""
done

# 下载结果总结
if [ $FAILED -eq 0 ]; then
    echo "✓ 所有扩展均已成功下载！"
else
    echo "⚠ 完成，但出现 $FAILED 个错误"
    exit 1
fi
