#!/usr/bin/env bash
# telegram-webhook.sh — скриптовый медиатип Zabbix для алертов в Telegram
# (docs/09-software-stack.md: «Алерты → Telegram-группа дежурных»)
#
# Настройка в Zabbix UI:
#   Alerts → Media types → Create: Type = Script, Name = Telegram (shell)
#   Script name: telegram-webhook.sh
#   Parameters (в этом порядке):
#     {ALERT.SENDTO}    — chat_id группы дежурных (напр. -1001234567890) или макрос {$TG_CHAT_ID}
#     {ALERT.SUBJECT}
#     {ALERT.MESSAGE}
#   Медиатипу добавить токен: передаём через переменную окружения TG_BOT_TOKEN
#   (в systemd-override zabbix-server или /etc/zabbix/telegram.env) — НЕ в параметрах,
#   чтобы токен не светился в БД/экспортах. Альтернатива: макрос {$TG_BOT_TOKEN}
#   с типом "Secret macro" (Zabbix ≥5.0) и 4-м параметром.
#
# Установка: положить в AlertScriptsPath (по умолчанию /usr/lib/zabbix/alertscripts),
# chmod 755, владелец zabbix:zabbix.

set -euo pipefail

CHAT_ID="${1:?chat_id обязателен}"
SUBJECT="${2:-Zabbix alert}"
MESSAGE="${3:-}"
TOKEN="${TG_BOT_TOKEN:-${4:-}}"

if [[ -z "$TOKEN" ]]; then
  echo "ОШИБКА: не задан TG_BOT_TOKEN (env или 4-й параметр)" >&2
  exit 1
fi

# Эмодзи по severity из subject (стандартные префиксы Zabbix: "PROBLEM: ...", "Resolved: ...")
ICON="⚠️"
case "$SUBJECT" in
  Resolved*|OK:*)          ICON="✅" ;;
  *Disaster*|*disaster*)   ICON="🔥" ;;
  *High*|*high*)           ICON="🚨" ;;
esac

# Шаблон сообщения (HTML; пробелы/переносы Zabbix передаёт как есть)
TEXT="${ICON} <b>${SUBJECT}</b>
${MESSAGE}
—
🖥 <i>infra-zabbix</i> | $(date '+%d.%m.%Y %H:%M:%S')"

# Отправка через Bot API. Пары ключ/значение из MESSAGE Zabbix уже отформатированы.
RESPONSE=$(curl -sS --max-time 10 \
  -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${TEXT}" \
  --data-urlencode "parse_mode=HTML" \
  --data-urlencode "disable_web_page_preview=true")

# Bot API вернул {"ok":true,...} — выходим 0, иначе Zabbix пометит отправку failed
if ! grep -q '"ok":true' <<<"$RESPONSE"; then
  echo "Telegram API error: $RESPONSE" >&2
  exit 1
fi
