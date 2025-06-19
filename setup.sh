#!/bin/bash

# === SETUP ===
XRAY_CONF="/usr/local/etc/xray/config.json"
CERT_DIR="/usr/local/etc/GoenkTea"
DOMAIN_FILE="/usr/local/etc/domain"

# Cek root
[[ $EUID -ne 0 ]] && echo "❌ Harus dijalankan sebagai root!" && exit 1

# Minta input domain
read -rp "Masukkan domain anda: " DOMAIN
echo "$DOMAIN" > $DOMAIN_FILE

# === INSTALASI DEPENDENSI ===
apt update -y
apt install curl socat cron nginx unzip -y

# === INSTALASI XRAY ===
if ! command -v xray &> /dev/null; then
  echo "📦 Menginstal Xray..."
  bash <(curl -s https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
fi

mkdir -p /usr/local/etc/xray
mkdir -p $CERT_DIR

# === HENTIKAN NGINX SEMENTARA UNTUK ISSUE TLS ===
echo "🚫 Menghentikan Nginx sementara untuk issue sertifikat..."
systemctl stop nginx

# Install acme.sh jika belum
if [ ! -f ~/.acme.sh/acme.sh ]; then
  echo "📥 Menginstal acme.sh..."
  curl https://get.acme.sh | sh
fi
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# === ISSUE SERTIFIKAT ===
echo "🔐 Issue TLS untuk $DOMAIN..."
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone -k ec-256 --force
if [ $? -ne 0 ]; then
  echo "❌ Gagal membuat sertifikat TLS. Pastikan domain mengarah ke IP server ini!"
  exit 1
fi

# Install cert ke direktori yang ditentukan
~/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
  --key-file $CERT_DIR/private.key \
  --fullchain-file $CERT_DIR/fullchain.cer

# === KONFIGURASI NGINX ===
echo "🧩 Menyusun konfigurasi NGINX reverse proxy..."
cat > /etc/nginx/sites-available/xray <<END
server {
    listen 80;
    server_name $DOMAIN;

    location /ws-epro {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:10000;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /trojan {
        proxy_pass http://127.0.0.1:10001;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}

server {
    listen 8443 ssl;
    server_name $DOMAIN;

    ssl_certificate $CERT_DIR/fullchain.cer;
    ssl_certificate_key $CERT_DIR/private.key;

    location /ws-epro {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:10000;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /trojan {
        proxy_pass http://127.0.0.1:10001;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
END

ln -sf /etc/nginx/sites-available/xray /etc/nginx/sites-enabled/xray
rm -f /etc/nginx/sites-enabled/default

#install ssh ws
##WS-EPRO
mkdir -p /usr/local/etc/ws-epro
wget -O /usr/bin/ws-epro "https://raw.githubusercontent.com/berkasaink/convig-vps/main/ws-epro"
chmod +x /usr/bin/ws-epro

cat > /usr/local/etc/ws-epro/config.yaml <<'EOF'
# verbose level 0=info, 1=verbose, 
# 2=very verbose
verbose: 0
listen:
# target ws-epro
- target_host: 127.0.0.1
  target_port: 110
  listen_port: 8888
EOF

#service ssh ws
cat > /etc/systemd/system/ws-epro.service <<EOF
[Unit]
Description=ws-epro

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/ws-epro -f /usr/local/etc/ws-epro/config.yaml
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

# === CONFIG XRAY ===
echo "🧩 Menulis konfigurasi Xray..."
UUID=$(cat /proc/sys/kernel/random/uuid)

cat > $XRAY_CONF <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 10000,
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "$UUID", "alterId": 0 }]
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
        "clients": [{ "password": "trojanpass" }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 🛑 Stop Nginx jika aktif
systemctl stop nginx 2>/dev/null

# 📦 Install dropbear
apt update -y
apt install dropbear build-essential libssl-dev zlib1g-dev curl -y

sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=.*/DROPBEAR_PORT=110/' /etc/default/dropbear
sed -i 's/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 110"/' /etc/default/dropbear

systemctl enable dropbear
systemctl restart dropbear

# 📥 Download & build stunnel5 dari situs resmi
cd /usr/local/src
curl -LO https://www.stunnel.org/downloads/archive/5.x/stunnel-5.72.tar.gz
tar -xvf stunnel-5.72.tar.gz
cd stunnel-5.72
./configure && make && make install

# ⚙️ Konfigurasi stunnel
mkdir -p /etc/stunnel5
cat > /etc/stunnel5/stunnel.conf <<EOF
cert = $CERT_DIR/fullchain.cer
key  = $CERT_DIR/private.key
pid  = /var/run/stunnel5.pid
output = /var/log/stunnel5.log
debug = 7
foreground = no
client = no

[dropbear]
accept = 443
connect = 127.0.0.1:110
EOF

# 🛠 Setup systemd service
cat > /etc/systemd/system/stunnel5.service <<EOF
[Unit]
Description=stunnel5 SSL tunnel for Dropbear
After=network.target

[Service]
ExecStart=/usr/local/bin/stunnel /etc/stunnel5/stunnel.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

#config xray
rm -rf /usr/local/etc/xray/config.json
wget -O /usr/local/etc/xray/config.json "https://raw.githubusercontent.com/berkasaink/xray/refs/heads/main/config.json"

apt install zip -y
wget https://github.com/berkasaink/xray/raw/refs/heads/main/menu.zip
unzip menu.zip -d/
chmod +x /usr/local/bin/menu
chmod +x /usr/local/etc/menu/*
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable stunnel5
systemctl restart stunnel5
systemctl start nginx 2>/dev/null
# === AKTIFKAN DAN JALANKAN XRAY ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable ws-epro
systemctl restart ws-epro
systemctl restart nginx
systemctl daemon-reexec
systemctl restart xray
systemctl enable xray

# === SELESAI ===
echo -e "\n✅ Instalasi selesai!"
echo "🌐 Domain        : $DOMAIN"
echo "🔐 UUID VMess    : $UUID"
echo "🔑 Trojan Pass   : trojanpass"
echo "📁 Config Xray   : $XRAY_CONF"
echo "📁 Sertifikat TLS: $CERT_DIR"
echo "🔒 SSL Listen : 443 → Dropbear port 110"
echo "📁 Sertifikat : $CERT_DIR"
echo "🗂 Log stunnel : /var/log/stunnel5.log"

