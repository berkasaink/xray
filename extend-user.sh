#!/bin/bash
read -p "Username: " USER
read -p "Tambah hari: " DAYS

for i in 0 1; do
    jq '(.inbounds['$i'].settings.clients) |= map(if .email == "'"$USER"'" then .expire = "'$(date -d "$DAYS days" +"%Y-%m-%d")'" else . end)' /usr/local/etc/xray/config.json > tmp && mv tmp /usr/local/etc/xray/config.json
done

systemctl restart xray
echo "✅ Masa aktif akun $USER diperpanjang $DAYS hari."
