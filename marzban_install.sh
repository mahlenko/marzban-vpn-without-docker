#!/bin/bash

# chmod +x marzban_install.sh

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
        apt install -y -q "$1"
    fi
}

apt update -y -q
install_if_missing curl
install_if_missing unzip
install_if_missing git
install_if_missing python3
install_if_missing python3-pip
install_if_missing nginx
install_if_missing snapd
install_if_missing jq

# Устанавливаем Certbot, если он отсутствует
if ! command -v certbot &> /dev/null; then
    snap install core; snap refresh core
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
fi

# Устанавливаем Xray, если он отсутствует
if ! command -v xray &> /dev/null; then
    color_echo 2 "Устанавливаем Xray..."
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
    color_echo 2 "Устанавливаем Marzban..."
    cd /opt && git clone https://github.com/Gozargah/Marzban.git marzban
    cd marzban && pip3 install -r requirements.txt

    alembic upgrade head

    # Добавляем администратора
    color_echo 2 "🔑 Создаём администратора"
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
ExecStart=/usr/bin/python3 /opt/marzban/main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now marzban
fi

# Настраиваем Nginx
if [ ! -f "/etc/nginx/sites-available/marzban" ]; then
    # Спрашиваем домен пользователя
    color_echo 2 "🌐 Введите ваш домен для дашборда:"
    read DOMAIN

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

    # Выпускаем SSL-сертификат, если его нет
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
    fi
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
color_echo 0 "✅ Установка завершена! 🎉"
color_echo 2 "🔗 Панель управления: https://$DOMAIN/dashboard"

# Добавим конфиги для VLESS
jq --argjson vless "$VLESS_REALITY_CONFIG" '.inbounds[0] = $vless' "$XRAY_CONFIG_JSON" > temp.json && mv temp.json "$XRAY_CONFIG_JSON"
color_echo 2 "Добавлена конфигурация для Vless REALITY"
