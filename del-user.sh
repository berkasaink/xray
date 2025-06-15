#!/bin/bash
read -p "Username yang akan dihapus: " USER
CONFIG_FILE="/usr/local/etc/xray/config.json"

for i in 0 1; do
    jq '(.inbounds['$i'].settings.clients) |= map(select(.email != "'"$USER"'"))' $CONFIG_FILE > tmp && mv tmp $CONFIG_FILE
done

systemctl restart xray
echo "✅ Akun $USER dihapus."
