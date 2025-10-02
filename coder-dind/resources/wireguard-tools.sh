#!/bin/bash

set -e

# 配置参数 - 支持环境变量覆盖
WG_CONF="${WG_CONF:-/root/.wireguard/wg0.conf}"
DOMAIN_FILE="${DOMAIN_FILE:-/root/.wireguard/domain.txt}"
DNSMASQ_CONF="/etc/dnsmasq.d/wireguard-split.conf"
IPSET_NAME="wg_domains"
WG_INTERFACE="wg0"

# 检查环境
check_requirements() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo "错误：请使用 root 权限运行此脚本"
        exit 1
    fi

    # 检查必要的命令
    for cmd in wg ip iptables ipset dnsmasq; do
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
    [ -n "$PRESHARED_KEY" ] && echo "  已启用 PresharedKey"
}

# 配置 ipset
setup_ipset() {
    ipset create $IPSET_NAME hash:ip
}

# 配置 iptables
setup_iptables() {
    iptables -t mangle -N WG_MARK
    iptables -t mangle -A WG_MARK -j MARK --set-mark 100
    iptables -t mangle -A PREROUTING -m set --match-set $IPSET_NAME dst -j WG_MARK
    iptables -t mangle -A OUTPUT -m set --match-set $IPSET_NAME dst -j WG_MARK
    iptables -t nat -A POSTROUTING -o $WG_INTERFACE -j MASQUERADE
}

# 配置路由
setup_routing() {
    ip rule add fwmark 100 table 100
    ip route add default dev $WG_INTERFACE table 100
}

# 配置 dnsmasq
setup_dnsmasq() {
    mkdir -p /etc/dnsmasq.d
    echo "no-resolv" > $DNSMASQ_CONF
    echo "server=8.8.8.8" >> $DNSMASQ_CONF
    echo "server=1.1.1.1" >> $DNSMASQ_CONF
    echo "listen-address=127.0.0.1" >> $DNSMASQ_CONF

    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        echo "ipset=/$domain/$IPSET_NAME" >> $DNSMASQ_CONF
    done < $DOMAIN_FILE

    echo "nameserver 127.0.0.1" > /etc/resolv.conf
}

# 启动 dnsmasq
start_dnsmasq() {
    pkill dnsmasq || true
    dnsmasq --conf-file=$DNSMASQ_CONF
    echo "dnsmasq 已启动"
}

# 监控 dnsmasq
monitor_dnsmasq() {
    while true; do
        if ! pgrep -x dnsmasq > /dev/null; then
            echo "检测到 dnsmasq 已停止，正在重启..."
            start_dnsmasq
        fi
        sleep 5
    done
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
cleanup_ipset() {
    echo "正在清理 ipset..."
    if ipset list $IPSET_NAME &> /dev/null; then
        ipset destroy $IPSET_NAME
        echo "ipset 已清理"
    else
        echo "ipset 不存在"
    fi
}

# 清理 iptables
cleanup_iptables() {
    echo "正在清理 iptables 规则..."
    iptables -t nat -D POSTROUTING -o $WG_INTERFACE -j MASQUERADE 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m set --match-set $IPSET_NAME dst -j WG_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -m set --match-set $IPSET_NAME dst -j WG_MARK 2>/dev/null || true
    iptables -t mangle -F WG_MARK 2>/dev/null || true
    iptables -t mangle -X WG_MARK 2>/dev/null || true
    echo "iptables 规则已清理"
}

# 清理路由
cleanup_routing() {
    echo "正在清理路由规则..."
    ip route del default dev $WG_INTERFACE table 100 2>/dev/null || true
    ip rule del fwmark 100 table 100 2>/dev/null || true
    echo "路由规则已清理"
}

# 停止 dnsmasq
stop_dnsmasq() {
    echo "正在重启 dnsmasq..."
    pkill dnsmasq || true
    if [ -f "$DNSMASQ_CONF" ]; then
        rm -f "$DNSMASQ_CONF"
        echo "dnsmasq WireGuard 配置已删除"
    fi
    # 重启 dnsmasq（不带 WireGuard 配置）
    dnsmasq
    echo "dnsmasq 已重启"
}

# 恢复 DNS 配置
restore_dns() {
    echo "正在恢复 DNS 配置..."
    # 恢复默认 DNS（可以根据需要修改）
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    echo "DNS 配置已恢复"
}

# WireGuard Up
wireguard_up() {
    echo "正在启动 WireGuard 分流系统..."
    
    check_requirements
    setup_wireguard
    setup_ipset
    setup_iptables
    setup_routing
    setup_dnsmasq
    start_dnsmasq
    
    # 后台运行 dnsmasq 守护进程
    monitor_dnsmasq &
    
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
    
    stop_dnsmasq
    restore_dns
    cleanup_routing
    cleanup_iptables
    cleanup_ipset
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
    echo "  WG_CONF      WireGuard 配置文件路径 (默认: /root/.wireguard/wg0.conf)"
    echo "  DOMAIN_FILE  域名列表文件路径 (默认: /root/.wireguard/domain.txt)"
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
