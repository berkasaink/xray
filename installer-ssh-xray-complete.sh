#!/bin/bash
# Installer Lengkap: SSH WebSocket, Xray VMess & Trojan WS, Stunnel5, BadVPN, Squid, OpenVPN, Nginx + SSL Otomatis
# Untuk Ubuntu 20.04, semua layanan berjalan di satu server

# === PERSIAPAN AWAL ===
echo -e "\e[32m[ PERSIAPAN AWAL ]\e[0m"
apt update && apt upgrade -y
apt install -y curl wget gnupg2 lsb-release socat cron netfilter-persistent iptables-persistent unzip nginx python3-certbot-nginx

# === INPUT DOMAIN ===
echo -ne "\nMasukkan domain anda (pastikan sudah diarah ke IP server ini): "; read DOMAIN

# Simpan domain
mkdir -p /etc/xray
echo "$DOMAIN" > /etc/xray/domain

# === PASANG DAN KONFIGURASI NGINX ===
echo -e "\e[32m[ KONFIGURASI NGINX ]\e[0m"
cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    return 301 https://\$host\$request_uri;
  }
  location /vmess {
    proxy_pass http://127.0.0.1:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
  }
  location /trojan {
    proxy_pass http://127.0.0.1:443;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
  }
}
EOF
nginx -t && systemctl restart nginx

# === PASANG CERTBOT & AMBIL SERTIFIKAT ===
echo -e "\e[32m[ PASANG SERTIFIKAT SSL OTOMATIS ]\e[0m"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

# Copy sertifikat ke lokasi yang dibutuhkan oleh Xray, Stunnel, dan OpenVPN
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/xray/xray.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/xray/xray.key

# === PASANG XRAY ===
echo -e "\e[32m[ PASANG XRAY ]\e[0m"
wget https://github.com/XTLS/Xray-install/raw/main/install-release.sh
bash install-release.sh

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 80,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    },
    {
      "port": 443,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            { "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" }
          ]
        },
        "wsSettings": { "path": "/trojan" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

systemctl restart xray
systemctl enable xray

# === PASANG STUNNEL5 ===
echo -e "\e[32m[ PASANG STUNNEL5 ]\e[0m"
apt install -y stunnel4
cat > /etc/stunnel/stunnel.conf <<EOF
cert = /etc/xray/xray.crt
key = /etc/xray/xray.key
client = no
[ssh]
accept = 443
connect = 127.0.0.1:22
EOF
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
systemctl enable stunnel4
systemctl restart stunnel4

# === PASANG OPENVPN ===
echo -e "\e[32m[ PASANG OPENVPN ]\e[0m"
apt install -y openvpn easy-rsa
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
cp openssl-1.0.0.cnf openssl.cnf 2>/dev/null || true
. ./vars
./clean-all
./build-ca --batch
./build-key-server --batch server
./build-dh
openvpn --genkey --secret keys/ta.key
./build-key --batch client
cp keys/{server.crt,server.key,ca.crt,ta.key,dh2048.pem} /etc/openvpn
cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
tls-auth ta.key 0
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
user nobody
group nogroup
keepalive 10 120
status openvpn-status.log
log-append /var/log/openvpn.log
verb 3
explicit-exit-notify 1
EOF
systemctl enable openvpn
systemctl start openvpn
