#!/bin/sh

key=$1
mode=$2

init() {
    if [ $mode = manage ]; then
        ./client-cli  -uri ws://103.63.139.136:8080/api/v1/ws -tool run -key $1
    elif [ $mode = work ]; then
        ./client-cli  -uri ws://103.63.139.136:8080/api/v1/ws -key $1
    else
        exit 1
    fi
}

init