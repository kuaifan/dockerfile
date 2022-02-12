#!/bin/bash

check_bak() {
    if [ -f /bakdb.sh ]; then
        /bin/sh /bakdb.sh
    fi
}

if [ -f /bakdb.sh ]; then
    chmod -x /bakdb.sh
fi

while true; do
    sleep 10
    check_bak > /dev/null 2>&1 &
done
