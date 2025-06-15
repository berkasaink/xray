#!/bin/bash
read -p "Username: " USER
read -p "Expired (hari): " EXP
UUID=$(uuidgen)
EXP_DATE=$(date -d "$EXP days" +"%Y-%m-%d")

CONFIG_FILE="/usr/local/etc/xray/config.json"

# VMess
jq '.inbounds[0].settings.clients += [{"id":"'"$UUID"'","email":"'"$USER"'","alterId":0,"expire":"'"$EXP_DATE"'"}]' $CONFIG_FILE > tmp && mv tmp $CONFIG_FILE

# Trojan
jq '.inbounds[1].settings.clients += [{"password":"'"$UUID"'","email":"'"$USER"'","expire":"'"$EXP_DATE"'"}]' $CONFIG_FILE > tmp && mv tmp $CONFIG_FILE

systemctl restart xray
echo "✅ Akun $USER ditambahkan. UUID: $UUID"
