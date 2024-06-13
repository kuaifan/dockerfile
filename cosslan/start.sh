#!/bin/bash
#fonts color
Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

#version setting
docker_compose_version="v2.5.0"


CmdPath=/cosslan

source '/etc/os-release' > /dev/null

if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    PM="yum"
elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    PM="apt-get"        
fi

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败 ${Font}"
        exit 1
    fi
}


check_system() {
    if [[ "${ID}" = "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo > /dev/null
    elif [[ "${ID}" = "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo > /dev/null
    elif [[ "${ID}" = "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo > /dev/null
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        rm -f $CmdPath
        exit 1
    fi
    #
    if [ "${PM}" = "yum" ]; then
        sudo yum update -y
        sudo yum install -y curl wget socat
    elif [ "${PM}" = "apt-get" ]; then
        apt-get update -y
        apt-get install -y curl wget socat
    fi
    judge "安装脚本依赖"
    #
    if [ "${PM}" = "yum" ]; then
        sudo yum install -y epel-release
    fi
}

check_docker() {
    docker --version &> /dev/null
    if [ $? -ne  0 ]; then
        echo -e "安装docker环境..."
        curl -fsSL https://get.docker.com | sh
        echo -e "${OK} Docker环境安装完成！"
    fi
    systemctl start docker
    if [[ 0 -ne $? ]]; then
        echo -e "${Error} ${RedBG} Docker 启动 失败${Font}"
        rm -f $CmdPath
        exit 1
    fi
    #
    docker-compose --version &> /dev/null
    if [ $? -ne  0 ]; then
        echo -e "安装docker-compose..."
        curl -s -L "https://get.daocloud.io/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo -e "${OK} Docker-compose安装完成！"
        service docker restart
    fi
}

init() {
    echo "1" > /test.log
}

check_system
check_docker
init()