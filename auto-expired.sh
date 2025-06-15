#!/bin/bash
TODAY=$(date +%Y-%m-%d)
CONFIG="/usr/local/etc/xray/config.json"

for i in 0 1; do
    jq '(.inbounds['$i'].settings.clients) |= map(select(.expire >= "'$TODAY'"))' $CONFIG > tmp && mv tmp $CONFIG
done

systemctl restart xray
