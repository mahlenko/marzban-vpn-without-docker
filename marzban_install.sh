#!/bin/bash

# Останавливаем скрипт при ошибке
set -e

# Функция для вывода цветного текста
color_echo() {
    local color="$1"
    local text="$2"
    if command -v tput &>/dev/null; then
        echo -e "$(tput setaf $color)$text$(tput sgr0)"
    else
        echo -e "$text"
    fi
}

# Проверка и установка зависимостей
install_if_missing() {
    if ! dpkg -l | grep -q "^ii  $1 "; then
        apt install -y -qq "$1"
    fi
}

apt update -y -qq
install_if_missing curl
install_if_missing unzip
install_if_missing git
install_if_missing python3
install_if_missing python3-pip
install_if_missing jq
install_if_missing python3-venv

# Устанавливаем Xray, если он отсутствует
if ! command -v xray &> /dev/null; then
    color_echo 2 "Install Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# Добавляем API Xray, если его нет
CONFIG_FILE="/usr/local/etc/xray/config.json"
if ! grep -q '"api"' $CONFIG_FILE; then
    jq '.api |= if . then . + {services: ["HandlerService", "StatsService"], tag: "api"} else {services: ["HandlerService", "StatsService"], tag: "api"} end' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE
    jq '.inbounds |= . + [{"port": 10085, "listen": "127.0.0.1", "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}, "tag": "api"}]' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE
    systemctl restart xray
fi

# Устанавливаем Marzban, если он отсутствует
if [ ! -d "/opt/marzban" ]; then
    color_echo 2 "Install Marzban Dashboard..."
    cd /opt && git clone https://github.com/Gozargah/Marzban.git marzban
    
    cd /opt/marzban 
    python3 -m venv venv
    source venv/bin/activate 
    pip install -r requirements.txt
    alembic upgrade head

    # Добавляем администратора
    color_echo 2 "🔑 Create user admin"
    /opt/marzban/marzban-cli.py admin create --sudo
fi

# Создаём сервис Marzban, если его нет
if [ ! -f "/etc/systemd/system/marzban.service" ]; then
    cat > /etc/systemd/system/marzban.service <<EOF
[Unit]
Description=Marzban Panel
After=network.target

[Service]
User=root
WorkingDirectory=/opt/marzban
ExecStart=/opt/marzban/venv/bin/python /opt/marzban/main.py
Restart=always
Environment=PATH=/opt/marzban/venv/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now marzban
fi

# Спрашиваем домен пользователя
color_echo 2 "🌐 Enter your domain for the dashboard:"
read -r DOMAIN

if [[ -n "$DOMAIN" ]]; then
  echo "Domain used: $DOMAIN"

  install_if_missing snapd
  install_if_missing nginx

  # Настраиваем Nginx
  if [ ! -f "/etc/nginx/sites-available/marzban" ]; then
    echo "Конфигурация Nginx отсутствует, создаем..."

    cat > /etc/nginx/sites-available/marzban <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    ln -s /etc/nginx/sites-available/marzban /etc/nginx/sites-enabled/marzban
  fi

  # Выпускаем SSL-сертификат, если его нет
  if [ ! -f "/usr/bin/certbot" ]; then
    install_if_missing snapd
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
  fi

  if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
  fi

else
  DOMAIN=$(hostname -I | awk '{print $1}')
  echo "The domain has not been entered, we use the IP: $DOMAIN"
fi

XRAY_PRIVATE_KEY=$(xray x25519 | grep -oP 'Private key: \K.*')
SHORT_ID=$(openssl rand -hex 8)

VLESS_REALITY_CONFIG='{
  "tag": "VLESS TCP REALITY",
  "listen": "0.0.0.0",
  "port": 2040,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "tcpSettings": {},
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "tradingview.com:443",
      "xver": 0,
      "serverNames": ["tradingview.com"],
      "privateKey": "'$XRAY_PRIVATE_KEY'",
      "shortIds": ["", "'$SHORT_ID'"]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  }
}'

# Выводим информацию о завершении установки
color_echo 0 "✅ The installation is complete! 🎉"
color_echo 2 "🔗 Control panel: http://$DOMAIN/dashboard"

# Добавим конфиги для VLESS
XRAY_CONFIG_JSON=/opt/marzban/xray_config.json
jq --argjson vless "$VLESS_REALITY_CONFIG" '.inbounds[0] = $vless' "$XRAY_CONFIG_JSON" > temp.json && mv temp.json "$XRAY_CONFIG_JSON"
color_echo 2 "Added configuration for Bless REALITY"

systemctl restart marzban
rm ./marzban_install.sh
