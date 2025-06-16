#!/bin/bash
# Installer Otomatis: SSH WebSocket, Xray (VMess WS & Trojan WS), Stunnel5, Squid, BadVPN, OpenVPN, + SSL Otomatis
# Untuk Ubuntu 20.04

# === PERSIAPAN ===
apt update && apt upgrade -y
apt install -y curl wget gnupg2 socat unzip iptables iptables-persistent   nginx certbot python3-certbot-nginx cron net-tools screen openvpn easy-rsa stunnel4 squid

# === INPUT DOMAIN ===
read -p "Masukkan domain anda (pastikan sudah mengarah ke IP VPS): " DOMAIN
mkdir -p /etc/xray && echo "$DOMAIN" > /etc/xray/domain

# === SETUP NGINX ===
cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80;
  server_name $DOMAIN;

  location / {
    root /var/www/html;
    index index.html;
  }

  location /vmess {
    proxy_pass http://127.0.0.1:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
  }

  location /trojan {
    proxy_pass http://127.0.0.1:443;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
  }
}
EOF
systemctl restart nginx

# === AMBIL SERTIFIKAT SSL ===
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/xray/xray.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/xray/xray.key

# === INSTALL XRAY ===
wget https://github.com/XTLS/Xray-install/raw/main/install-release.sh
bash install-release.sh

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 80,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
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
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
systemctl enable xray && systemctl restart xray

# === INSTALL STUNNEL5 ===
cat > /etc/stunnel/stunnel.conf <<EOF
cert = /etc/xray/xray.crt
key = /etc/xray/xray.key
client = no
[ssh]
accept = 443
connect = 127.0.0.1:22
EOF
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
systemctl enable stunnel4 && systemctl restart stunnel4

# === INSTALL SQUID ===
cat > /etc/squid/squid.conf <<EOF
http_port 2025
acl localnet src 0.0.0.0/0
http_access allow localnet
EOF
systemctl restart squid
systemctl enable squid

# === INSTALL BADVPN ===
wget -O /usr/bin/badvpn-udpgw https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw
chmod +x /usr/bin/badvpn-udpgw
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300

# === INSTALL OPENVPN EASY-RSA v3 ===
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
./easyrsa init-pki
echo | ./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server <<EOF
yes
EOF
./easyrsa gen-dh
openvpn --genkey --secret ta.key
cp pki/ca.crt pki/issued/server.crt pki/private/server.key ta.key pki/dh.pem /etc/openvpn/

cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
user nobody
group nogroup
keepalive 10 120
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
explicit-exit-notify 1
EOF
systemctl enable openvpn && systemctl start openvpn

echo -e "\n\e[32mINSTALASI SELESAI. LAYANAN AKTIF:\e[0m"
echo "SSH WebSocket, Xray VMess/Trojan, Squid, Stunnel5, BadVPN, OpenVPN"
