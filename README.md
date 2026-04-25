📜 VPS Banner Installer

Безопасный установщик баннера для VPS, который добавляет сообщение при входе в систему через /etc/profile.d, не изменяя напрямую /etc/profile.

✨ Особенности
✅ Не изменяет /etc/profile
✅ Использует /etc/profile.d
✅ Безопасное обновление через маркеры
✅ Не перезаписывает чужие файлы
✅ Поддержка --force
✅ Показывает баннер только в интерактивных сессиях
🚀 Установка (одной командой)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/your-repo/install_vps_banner.sh)
🔥 Переустановка (force)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/your-repo/install_vps_banner.sh) --force
⚙️ Использование
install_vps_banner.sh [--file PATH] [--force]
Параметры
--file — путь к файлу в /etc/profile.d/
(по умолчанию: /etc/profile.d/99-vps-banner.sh)
--force — принудительно перезаписать баннер
📌 Примеры
Стандартная установка
sudo ./install_vps_banner.sh
Установка в другой файл
sudo ./install_vps_banner.sh --file /etc/profile.d/custom-banner.sh
Переустановка
sudo ./install_vps_banner.sh --force
🔒 Безопасность

Скрипт:

❗ Требует запуск от root
❗ Работает только с /etc/profile.d/*.sh
❗ Не перезапишет файл без своих маркеров
✔ Удаляет только свой блок:
# >>> vps-banner >>>
...
# <<< vps-banner <<<
🖥 Как это работает

Создаётся файл:

/etc/profile.d/99-vps-banner.sh

Содержимое:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Welcome to your VPS
   Unauthorized access is prohibited.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Баннер отображается только при интерактивном входе (SSH / терминал).

🧹 Удаление
sudo rm /etc/profile.d/99-vps-banner.sh
🛠 Кастомизация
sudo nano /etc/profile.d/99-vps-banner.sh

Измени текст внутри:

cat <<'EOF_BANNER'
...
EOF_BANNER
⚠️ Важно

Баннер не показывается в:

cron
скриптах
non-interactive shell

Это сделано специально, чтобы не ломать автоматизацию.

💡 Советы

Перед запуском можно посмотреть код:

curl -fsSL https://raw.githubusercontent.com/your-repo/install_vps_banner.sh | less
