#!/bin/bash

set -e

# 配置参数 - 支持环境变量覆盖
WG_CONF="${WG_CONF:-/root/.wireguard/wgdind.conf}"
DOMAIN_FILE="${DOMAIN_FILE:-/root/.wireguard/domain.txt}"
IPSET_UPSTREAM_V4="wg_upstream_v4"
IPSET_UPSTREAM_V6="wg_upstream_v6"
IPSET_DIRECT_V4="wg_direct_v4"
IPSET_DIRECT_V6="wg_direct_v6"
WG_INTERFACE="wgdind"
WG_FWMARK=100
WG_ROUTE_TABLE=100
IPTABLES_CHAIN="WG_SPLIT"
IP6TABLES_CHAIN="WG_SPLIT6"

# 检查环境
check_requirements() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo "错误：请使用 root 权限运行此脚本"
        exit 1
    fi

    # 检查必要的命令
    for cmd in wg ip iptables ip6tables ipset getent; do
        if ! command -v $cmd &> /dev/null; then
            echo "错误：未找到命令 $cmd，请先安装"
            exit 1
        fi
    done

    # 检查配置文件
    if [ ! -f "$WG_CONF" ]; then
        echo "错误：WireGuard 配置文件不存在: $WG_CONF"
        exit 1
    fi

    if [ ! -f "$DOMAIN_FILE" ]; then
        echo "错误：域名列表文件不存在: $DOMAIN_FILE"
        exit 1
    fi
}

# 解析 WireGuard 配置文件
parse_wireguard_config() {
    local key=$1
    grep "$key" "$WG_CONF" | cut -d'=' -f2- | tr -d ' \t\r\n'
}

# 配置 WireGuard
setup_wireguard() {
    # 解析 WireGuard 配置
    local PRIVATE_KEY=$(parse_wireguard_config "PrivateKey")
    local ADDRESS=$(parse_wireguard_config "Address")
    local PUBLIC_KEY=$(parse_wireguard_config "PublicKey")
    local PRESHARED_KEY=$(parse_wireguard_config "PresharedKey")
    local ENDPOINT=$(parse_wireguard_config "Endpoint")
    local MTU=$(parse_wireguard_config "MTU")
    local KEEPALIVE=$(parse_wireguard_config "PersistentKeepalive")
    
    # 验证必需配置项
    if [ -z "$PRIVATE_KEY" ]; then
        echo "错误：WireGuard 配置中缺少 PrivateKey"
        exit 1
    fi
    
    if [ -z "$ADDRESS" ]; then
        echo "错误：WireGuard 配置中缺少 Address"
        exit 1
    fi
    
    if [ -z "$PUBLIC_KEY" ]; then
        echo "错误：WireGuard 配置中缺少 PublicKey"
        exit 1
    fi
    
    if [ -z "$ENDPOINT" ]; then
        echo "错误：WireGuard 配置中缺少 Endpoint"
        exit 1
    fi
    
    # 设置默认值（可选配置项）
    MTU=${MTU:-1360}
    KEEPALIVE=${KEEPALIVE:-25}

    # 配置 WireGuard 接口
    ip link add dev $WG_INTERFACE type wireguard
    
    # 添加地址（支持多个地址，用逗号或空格分隔，例如: 10.8.0.2/24, fdcc:ad94:bacf:61a4::cafe:2/112）
    echo "$ADDRESS" | tr ',' '\n' | while IFS= read -r addr; do
        addr=$(echo "$addr" | xargs)  # 去除首尾空格
        [ -n "$addr" ] && ip address add dev $WG_INTERFACE "$addr"
    done
    
    # 设置私钥
    echo -n "$PRIVATE_KEY" | wg set $WG_INTERFACE private-key /dev/stdin
    
    # 配置 Peer（支持 PresharedKey）
    local WG_PEER_CMD="wg set $WG_INTERFACE peer $PUBLIC_KEY endpoint $ENDPOINT allowed-ips 0.0.0.0/0,::/0 persistent-keepalive $KEEPALIVE"
    if [ -n "$PRESHARED_KEY" ]; then
        # 使用临时文件传递 PresharedKey（更安全）
        local PSK_FILE=$(mktemp)
        echo -n "$PRESHARED_KEY" > "$PSK_FILE"
        WG_PEER_CMD="$WG_PEER_CMD preshared-key $PSK_FILE"
    fi
    eval "$WG_PEER_CMD"
    [ -n "$PRESHARED_KEY" ] && rm -f "$PSK_FILE"
    
    # 启动接口
    ip link set mtu $MTU up dev $WG_INTERFACE
    
    echo "WireGuard 接口配置完成："
    echo "  地址: $ADDRESS"
    echo "  MTU: $MTU"
    echo "  Endpoint: $ENDPOINT"
    [ -n "$PRESHARED_KEY" ] && echo "  已启用 PresharedKey" || true
}

# 判断 IPv4/IPv6 与 CIDR
is_ipv4() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ipv4_cidr() {
    local cidr=$1
    if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
        local prefix=${BASH_REMATCH[2]}
        (( prefix >= 0 && prefix <= 32 ))
        return
    fi
    return 1
}

is_ipv6() {
    local ip=$1
    [[ $ip == *:* ]] && [[ $ip != *\ * ]] && [[ $ip != */* ]]
}

is_ipv6_cidr() {
    local cidr=$1
    [[ $cidr == *:* && $cidr == */* ]]
}

trim_comment_and_space() {
    local line=$1
    line=${line%%#*}
    echo "$line" | xargs
}

extract_mode_and_value() {
    local line=$1
    local mode="upstream"
    local value="$line"

    if [[ $line =~ ^([Dd][Ii][Rr][Ee][Cc][Tt])[:[:space:]]+(.+)$ ]]; then
        mode="direct"
        value="${BASH_REMATCH[2]}"
    elif [[ $line =~ ^([Uu][Pp][Ss][Tt][Rr][Ee][Aa][Mm])[:[:space:]]+(.+)$ ]]; then
        mode="upstream"
        value="${BASH_REMATCH[2]}"
    fi

    echo "$mode|$value"
}

add_to_ipset() {
    local mode=$1
    local address=$2
    local family=$3
    local set_name

    case "$mode" in
        direct)
            if [ "$family" = "inet" ]; then
                set_name=$IPSET_DIRECT_V4
            else
                set_name=$IPSET_DIRECT_V6
            fi
            ;;
        *)
            if [ "$family" = "inet" ]; then
                set_name=$IPSET_UPSTREAM_V4
            else
                set_name=$IPSET_UPSTREAM_V6
            fi
            ;;
    esac

    if ! ipset add -exist "$set_name" "$address" 2>/dev/null; then
        echo "警告：无法将 $address 添加到 ipset $set_name" >&2
    else
        echo "已添加 ${mode}($family): $address"
    fi
}

resolve_domain() {
    local domain=$1
    local mode=$2
    local output

    if ! output=$(getent ahosts "$domain" 2>/dev/null); then
        output=$(getent hosts "$domain" 2>/dev/null) || {
            echo "警告：无法解析域名 $domain" >&2
            return
        }
    fi

    local ips
    ips=$(echo "$output" | awk '{print $1}' | grep -v '^$' | sort -u)

    if [ -z "$ips" ]; then
        echo "警告：域名 $domain 未解析到有效 IP" >&2
        return
    fi

    while IFS= read -r addr; do
        if is_ipv4 "$addr"; then
            add_to_ipset "$mode" "$addr/32" "inet"
        elif is_ipv6 "$addr"; then
            add_to_ipset "$mode" "$addr/128" "inet6"
        else
            echo "警告：忽略未知地址格式 $addr (来源 $domain)" >&2
        fi
    done <<< "$ips"
}

setup_ipsets() {
    ipset create -exist $IPSET_UPSTREAM_V4 hash:net family inet
    ipset create -exist $IPSET_UPSTREAM_V6 hash:net family inet6
    ipset create -exist $IPSET_DIRECT_V4 hash:net family inet
    ipset create -exist $IPSET_DIRECT_V6 hash:net family inet6

    ipset flush $IPSET_UPSTREAM_V4
    ipset flush $IPSET_UPSTREAM_V6
    ipset flush $IPSET_DIRECT_V4
    ipset flush $IPSET_DIRECT_V6

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        local line
        line=$(trim_comment_and_space "$raw_line")
        [ -z "$line" ] && continue

        local parsed mode value
        parsed=$(extract_mode_and_value "$line")
        mode=${parsed%%|*}
        value=${parsed#*|}
        value=$(echo "$value" | xargs)
        [ -z "$value" ] && continue

        if is_ipv4 "$value"; then
            add_to_ipset "$mode" "$value/32" "inet"
            continue
        fi
        if is_ipv4_cidr "$value"; then
            add_to_ipset "$mode" "$value" "inet"
            continue
        fi
        if is_ipv6 "$value"; then
            add_to_ipset "$mode" "$value/128" "inet6"
            continue
        fi
        if is_ipv6_cidr "$value"; then
            add_to_ipset "$mode" "$value" "inet6"
            continue
        fi

        resolve_domain "$value" "$mode"
    done < "$DOMAIN_FILE"
}

ensure_chain() {
    local cmd=$1
    local table=$2
    local chain=$3

    if ! $cmd -t "$table" -L "$chain" &>/dev/null; then
        $cmd -t "$table" -N "$chain"
    else
        $cmd -t "$table" -F "$chain"
    fi
}

ensure_jump() {
    local cmd=$1
    local table=$2
    local parent=$3
    local chain=$4

    if ! $cmd -t "$table" -C "$parent" -j "$chain" &>/dev/null; then
        $cmd -t "$table" -A "$parent" -j "$chain"
    fi
}

setup_iptables() {
    ensure_chain iptables mangle $IPTABLES_CHAIN
    iptables -t mangle -A $IPTABLES_CHAIN -m set --match-set $IPSET_DIRECT_V4 dst -j RETURN
    iptables -t mangle -A $IPTABLES_CHAIN -m set --match-set $IPSET_UPSTREAM_V4 dst -j MARK --set-mark $WG_FWMARK
    iptables -t mangle -A $IPTABLES_CHAIN -j RETURN

    ensure_jump iptables mangle PREROUTING $IPTABLES_CHAIN
    ensure_jump iptables mangle OUTPUT $IPTABLES_CHAIN

    if ! iptables -t nat -C POSTROUTING -o $WG_INTERFACE -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -o $WG_INTERFACE -j MASQUERADE
    fi

    ensure_chain ip6tables mangle $IP6TABLES_CHAIN
    ip6tables -t mangle -A $IP6TABLES_CHAIN -m set --match-set $IPSET_DIRECT_V6 dst -j RETURN
    ip6tables -t mangle -A $IP6TABLES_CHAIN -m set --match-set $IPSET_UPSTREAM_V6 dst -j MARK --set-mark $WG_FWMARK
    ip6tables -t mangle -A $IP6TABLES_CHAIN -j RETURN

    ensure_jump ip6tables mangle PREROUTING $IP6TABLES_CHAIN
    ensure_jump ip6tables mangle OUTPUT $IP6TABLES_CHAIN
}

# 配置路由
setup_routing() {
    ip rule del fwmark $WG_FWMARK table $WG_ROUTE_TABLE 2>/dev/null || true
    ip route del default dev $WG_INTERFACE table $WG_ROUTE_TABLE 2>/dev/null || true
    ip rule add fwmark $WG_FWMARK table $WG_ROUTE_TABLE
    ip route add default dev $WG_INTERFACE table $WG_ROUTE_TABLE
}

# 停止 WireGuard
stop_wireguard() {
    echo "正在停止 WireGuard 接口..."
    if ip link show $WG_INTERFACE &> /dev/null; then
        ip link set $WG_INTERFACE down
        ip link delete $WG_INTERFACE
        echo "WireGuard 接口已删除"
    else
        echo "WireGuard 接口不存在"
    fi
}

# 清理 ipset
cleanup_ipsets() {
    echo "正在清理 ipset..."
    for set in $IPSET_UPSTREAM_V4 $IPSET_UPSTREAM_V6 $IPSET_DIRECT_V4 $IPSET_DIRECT_V6; do
        if ipset list "$set" &>/dev/null; then
            ipset destroy "$set" 2>/dev/null || ipset flush "$set" 2>/dev/null || true
        fi
    done
    echo "ipset 清理完成"
}

# 清理 iptables
cleanup_iptables() {
    echo "正在清理 iptables 规则..."
    iptables -t nat -D POSTROUTING -o $WG_INTERFACE -j MASQUERADE 2>/dev/null || true
    for parent in PREROUTING OUTPUT; do
        iptables -t mangle -D $parent -j $IPTABLES_CHAIN 2>/dev/null || true
    done
    iptables -t mangle -F $IPTABLES_CHAIN 2>/dev/null || true
    iptables -t mangle -X $IPTABLES_CHAIN 2>/dev/null || true

    for parent in PREROUTING OUTPUT; do
        ip6tables -t mangle -D $parent -j $IP6TABLES_CHAIN 2>/dev/null || true
    done
    ip6tables -t mangle -F $IP6TABLES_CHAIN 2>/dev/null || true
    ip6tables -t mangle -X $IP6TABLES_CHAIN 2>/dev/null || true
    echo "iptables 规则已清理"
}

# 清理路由
cleanup_routing() {
    echo "正在清理路由规则..."
    ip route del default dev $WG_INTERFACE table $WG_ROUTE_TABLE 2>/dev/null || true
    ip rule del fwmark $WG_FWMARK table $WG_ROUTE_TABLE 2>/dev/null || true
    echo "路由规则已清理"
}

# WireGuard Up
wireguard_up() {
    echo "正在启动 WireGuard 分流系统..."
    
    check_requirements
    setup_wireguard
    setup_ipsets
    setup_iptables
    setup_routing
    
    echo "WireGuard 分流系统启动完成！"
    
    # 保持容器运行
    exec /bin/bash
}

# WireGuard Down
wireguard_down() {
    echo "正在关闭 WireGuard 分流系统..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo "错误：请使用 root 权限运行此脚本"
        exit 1
    fi
    
    cleanup_routing
    cleanup_iptables
    cleanup_ipsets
    stop_wireguard
    
    echo "WireGuard 分流系统已关闭！"
}

# 显示使用帮助
show_usage() {
    echo "用法: $0 [up|down]"
    echo ""
    echo "命令:"
    echo "  up    启动 WireGuard 分流系统 (默认)"
    echo "  down  关闭 WireGuard 分流系统"
    echo ""
    echo "环境变量:"
    echo "  WG_CONF      WireGuard 配置文件路径 (默认: /root/.wireguard/wgdind.conf)"
    echo "  DOMAIN_FILE  域名列表文件路径 (默认: /root/.wireguard/domain.txt)"
    echo ""
    echo "domain.txt 格式说明:"
    echo "  支持如下格式的条目（每行一个）："
    echo "  1. 域名: example.com （默认走上游）"
    echo "  2. IPv4/IPv6: 192.168.1.1 或 2404:6800::1"
    echo "  3. CIDR: 192.168.1.0/24 或 2404:6800::/32"
    echo "  4. 显式前缀: upstream example.com / direct example.org"
    echo "  5. 注释: 以 # 开头的行会被忽略"
    echo ""
    echo "示例 domain.txt:"
    echo "  # 上游分流"
    echo "  upstream google.com"
    echo "  # 保持直连"
    echo "  direct example.cn"
    echo "  192.168.1.100"
    echo "  2404:6800::/32"
}

# 主函数
main() {
    local command=${1:-up}
    
    case "$command" in
        up)
            wireguard_up
            ;;
        down)
            wireguard_down
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        *)
            echo "错误：未知命令 '$command'"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
