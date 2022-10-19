#!/usr/bin/env sh

curl -s myip.ipip.net
ip=$(curl -s ifconfig.me)
echo "谷歌 IP: ${ip}"
