#!/bin/sh

Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

init() {
    if [ $MODE = manage ]; then
        /var/cosslan-client/client_cli -uri ws://103.63.139.136:8080/api/v1/ws -key $KEY
        if [ $? -eq 0 ]; then
            echo "${OK} 管理模式命令执行成功"
        else
            echo "${Error} 管理模式命令执行失败"S
        fi
    elif [ $MODE = work ]; then
        /var/cosslan-client/client_cli -uri ws://103.63.139.136:8080/api/v1/ws -tool run -key $KEY
        if [ $? -eq 0 ]; then
            echo "${OK} 工作模式命令执行成功"
        else
            echo "${Error} 工作模式命令执行失败"
        fi
    else
        echo "${Error} 请指定启动模式"
        exit 1
    fi
}

init