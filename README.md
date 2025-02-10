Когда я впервые попробовал поставить ПУ Marzban у меня не вышло из-за лимитов докера.

# Что делает скрипт? 
- Скачивает и устанавливает XRAY сервер и включает API для Marzban
- Устанавливает nginx и certbot, подключает домен (заранее настройте DNS домена на сервер)
- Создает первого админа
- Настраивает VLESS протокол
- Создаст сервис Marzban

# Установка
Скрипт установки тестировался на Ubuntu 22.04
```bash
curl -sOL https://raw.githubusercontent.com/mahlenko/marzban-vpn-without-docker/refs/heads/main/marzban_install.sh && chmod +x ./marzban_install.sh && ./marzban_install.sh
```
или wget
```bash
wget -q https://raw.githubusercontent.com/mahlenko/marzban-vpn-without-docker/refs/heads/main/marzban_install.sh && chmod +x ./marzban_install.sh && ./marzban_install.sh
```

# Управление
- `systemctl start marzban`
- `systemctl stop marzban`

# Документация marzban (ru)
https://marzban-docs.sm1ky.com/
