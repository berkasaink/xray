#!/bin/bash

# ==========================
# VARIABEL DASAR
# ==========================
DOMAIN=crut.idssh.net
XRAY_PATH=/usr/local/etc/xray
XRAY_BIN=/usr/local/bin/xray
XRAY_SERVICE=/etc/systemd/system/xray.service
TLS_CERT=/etc/xray/xray.crt
TLS_KEY=/etc/xray/xray.key

# ==========================
# 1. Install Xray
# ==========================
apt update -y && apt install -y curl socat xz-utils wget cron bash unzip jq iptables iptables-persistent nginx
bash <(curl -s https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# ==========================
# 2. Setup SSL (acme.sh)
# ==========================
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m admin@$DOMAIN
~/.acme.sh/acme.sh --issue --standalone -d $DOMAIN --force --keylength ec-256
mkdir -p /etc/xray
~/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
--fullchain-file $TLS_CERT \
--key-file $TLS_KEY

# ==========================
# 3. NGINX Reverse Proxy
# ==========================
cat > /etc/nginx/sites-available/default << END
server {
    listen 8080;
    server_name $DOMAIN;

    location /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /trojango {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
END

systemctl restart nginx

# ==========================
# 4. Xray Config Gabungan
# ==========================
cat > $XRAY_PATH/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 10000,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },
    {
      "port": 10001,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojango" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

systemctl daemon-reexec
systemctl restart xray
systemctl enable xray

echo "✅ Xray & Trojan-Go WS diinstal dan dikonfigurasi."
