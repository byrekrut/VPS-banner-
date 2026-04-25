# 📜 VPS Custom Banner Installer

Установщик кастомного баннера для VPS (Ubuntu-friendly), который:

- скачивает баннер из GitHub  
- сохраняет его как отдельный скрипт  
- безопасно подключает через `/etc/profile.d`  
- **не изменяет `/etc/profile`**

---

## ✨ Особенности

- Безопасная установка без правки системных файлов
- Баннер хранится отдельно (`/usr/local/lib`)
- Автоматическая загрузка с GitHub
- Работает только в интерактивных сессиях
- Поддержка кастомных путей и источника

---

## 🚀 Установка (одной командой)

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/byrekrut/VPS-banner-/main/install_vps_banner.sh)
```

---

## ⚙️ Использование

```bash
install_vps_banner.sh [--source URL] [--profiled-file PATH] [--banner-file PATH]
```

### Параметры

- `--source` — URL баннера  
  (по умолчанию: `vps-custom-banner.sh` из репозитория)

- `--profiled-file` — файл в `/etc/profile.d/`  
  (по умолчанию: `/etc/profile.d/vps-custom-banner.sh`)

- `--banner-file` — куда сохранить баннер  
  (по умолчанию: `/usr/local/lib/vps-custom-banner.sh`)

---

## 📌 Примеры

### Стандартная установка

```bash
sudo ./install_vps_banner.sh
```

---

### Использовать свой баннер

```bash
sudo ./install_vps_banner.sh --source https://example.com/banner.sh
```

---

### Изменить пути установки

```bash
sudo ./install_vps_banner.sh \
  --banner-file /opt/banner.sh \
  --profiled-file /etc/profile.d/banner.sh
```

---

## 🖥 Как это работает

1. Скачивает баннер:
```
https://github.com/byrekrut/VPS-banner-
```

2. Сохраняет его в:
```
/usr/local/lib/vps-custom-banner.sh
```

3. Создаёт launcher:
```
/etc/profile.d/vps-custom-banner.sh
```

4. При входе в систему:
- проверяется интерактивный shell  
- запускается баннер через `bash`

---

## 🔒 Безопасность

Скрипт:

- Требует root
- Не изменяет `/etc/profile`
- Работает только через `/etc/profile.d`
- Очищает баннер от потенциально опасных строк (`set -u`, shebang)

---

## 🧹 Удаление

```bash
sudo rm /etc/profile.d/vps-custom-banner.sh
sudo rm /usr/local/lib/vps-custom-banner.sh
```

---

## 🛠 Кастомизация

Отредактируй файл:

```bash
sudo nano /usr/local/lib/vps-custom-banner.sh
```

---

## ⚠️ Важно

Баннер НЕ показывается в:

- cron
- скриптах
- non-interactive shell

Это сделано специально, чтобы не ломать автоматизацию.

---

## 📎 Лицензия

MIT
