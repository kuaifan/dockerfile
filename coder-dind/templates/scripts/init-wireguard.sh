#!/bin/bash

set -e

# 配置参数 - 支持环境变量覆盖
WG_CONF="${WG_CONF:-/root/workspaces/.wireguard/wg0.conf}"
DOMAIN_FILE="${DOMAIN_FILE:-/root/workspaces/.wireguard/domain.txt}"
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
    local PRIVATE_KEY=$(parse_wireguard_config "PrivateKey")
    local ADDRESS=$(parse_wireguard_config "Address" | cut -d'/' -f1)
    local PUBLIC_KEY=$(parse_wireguard_config "PublicKey")
    local ENDPOINT=$(parse_wireguard_config "Endpoint")
    local MTU=$(parse_wireguard_config "MTU")
    local KEEPALIVE=$(parse_wireguard_config "PersistentKeepalive")

    ip link add dev $WG_INTERFACE type wireguard
    ip address add dev $WG_INTERFACE $ADDRESS/32
    echo -n "$PRIVATE_KEY" | wg set $WG_INTERFACE private-key /dev/stdin
    wg set $WG_INTERFACE peer $PUBLIC_KEY endpoint $ENDPOINT allowed-ips 0.0.0.0/0 persistent-keepalive $KEEPALIVE
    ip link set mtu $MTU up dev $WG_INTERFACE
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

# 主函数
main() {
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

# 执行主函数
main
