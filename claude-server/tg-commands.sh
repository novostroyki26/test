#!/usr/bin/env bash
# Кнопки и команды Telegram-бота Claude Code.
# Запуск от root на сервере бота:  bash tg-commands.sh
# Повторный запуск безопасен.
#
# Что делает:
#   1. Регистрирует меню команд бота (setMyCommands, только для чата владельца).
#   2. Присылает владельцу постоянную клавиатуру из 8 кнопок.
#   3. Ставит помощники ~/bin/server-status и ~/bin/claude-stop пользователю claude.
#   4. Обновляет раздел «Команды и кнопки» в ~/work/CLAUDE.md.
#
# Чего НЕ делает: getUpdates, setWebhook, deleteWebhook. Получатель обновлений
# у бота один, это плагин telegram; посторонний getUpdates отнял бы у него сообщения.
# Токен бота никогда не выводится на экран.
set -euo pipefail

OWNER_TG_ID="${OWNER_TG_ID:-5472230307}"
CUSER=claude
CHOME=/home/$CUSER
WORK=$CHOME/work
ENV_FILE=$CHOME/.claude/channels/telegram/.env
TG_API="${TG_API:-https://api.telegram.org}"

[ "$(id -u)" -eq 0 ] || { echo "Запустите от root: bash tg-commands.sh"; exit 1; }
id "$CUSER" &>/dev/null || { echo "Нет пользователя $CUSER: сначала выполните setup.sh"; exit 1; }

token="$(grep -oE '[0-9]+:[A-Za-z0-9_-]{30,}' "$ENV_FILE" 2>/dev/null | head -1 || true)"
[ -n "$token" ] || { echo "Токен бота не найден: сначала выполните /telegram:configure"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Вызов Bot API. Токен передаётся curl через stdin (-K -), а не в аргументах,
# поэтому не виден в списке процессов. Печатает «ok» или «ошибка: <описание>».
bot_api() {
  local method=$1 body=$2 resp
  resp="$(printf 'url = "%s/bot%s/%s"\n' "$TG_API" "$token" "$method" |
    curl -sS --max-time 20 -K - -H 'Content-Type: application/json' --data-binary @"$body" 2>&1 || true)"
  resp="${resp//$token/***}"
  python3 - "$resp" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except ValueError:
    print("ошибка: нет ответа от Telegram: " + raw.strip()[:200])
    sys.exit(1)
if data.get("ok") is True:
    print("ok")
else:
    print("ошибка: " + str(data.get("description", "неизвестная ошибка")))
    sys.exit(1)
PY
}

# --- 1–2. Меню команд и клавиатура -----------------------------------------
python3 - "$OWNER_TG_ID" "$tmp" <<'PY'
import json, sys
owner, out = int(sys.argv[1]), sys.argv[2]
commands = [
    ("next", "Далее: продолжить текущую задачу по плану"),
    ("implement", "Реализуй: выполнить план из последнего сообщения"),
    ("ok", "ОК: согласие с последним предложением"),
    ("status", "Статус: что делаю, что сделано, чего жду"),
    ("waiting", "Ждут ответа: открытые вопросы ко мне"),
    ("stop", "Остановить текущую задачу"),
    ("server", "Сервер: состояние сервера (только чтение)"),
    ("help", "Помощь: справка по кнопкам"),
]
with open(f"{out}/commands.json", "w", encoding="utf-8") as f:
    json.dump({
        "commands": [{"command": c, "description": d} for c, d in commands],
        "scope": {"type": "chat", "chat_id": owner},
    }, f, ensure_ascii=False)
rows = [
    ["▶️ Далее", "🛠 Реализуй", "✅ ОК"],
    ["📊 Статус", "🔔 Ждут ответа", "⏹ Остановить"],
    ["🖥 Сервер", "❓ Помощь"],
]
with open(f"{out}/keyboard.json", "w", encoding="utf-8") as f:
    json.dump({
        "chat_id": owner,
        "text": "Кнопки обновлены",
        "reply_markup": {
            "keyboard": [[{"text": t} for t in row] for row in rows],
            "is_persistent": True,
            "resize_keyboard": True,
        },
    }, f, ensure_ascii=False)
PY

rc=0
result="$(bot_api setMyCommands "$tmp/commands.json")" || rc=1
echo "Команды: $result"
result="$(bot_api sendMessage "$tmp/keyboard.json")" || rc=1
echo "Клавиатура: $result"

# --- 3. Помощники ------------------------------------------------------------
install -d -m 700 -o "$CUSER" -g "$CUSER" "$CHOME/bin"

cat > "$CHOME/bin/server-status" <<'SH'
#!/usr/bin/env bash
# Состояние сервера для кнопки «🖥 Сервер». Только чтение.
echo "Аптайм: $(uptime -p)"
df -h / | awk 'NR==2 {print "Диск /: занято " $3 " из " $2 " (" $5 "), свободно " $4}'
free -h | awk '/^Mem:/ {print "Память: занято " $3 " из " $2 ", доступно " $7}'
echo "Claude Code: $(PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH" claude --version 2>/dev/null || echo 'не найден')"
for host in api.telegram.org api.anthropic.com; do
  code="$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "https://$host" || true)"
  case "$code" in
    ''|000) echo "$host: недоступен" ;;
    *)      echo "$host: доступен (HTTP $code)" ;;
  esac
done
SH

cat > "$CHOME/bin/claude-stop" <<'SH'
#!/usr/bin/env bash
# Аварийная остановка текущего хода Claude (как Esc в терминале).
# Только из консоли или SSH владельца:  su - claude -c claude-stop
tmux send-keys -t claude Escape && echo "Отправлен Esc: текущий ход Claude прерван."
SH
chown "$CUSER:$CUSER" "$CHOME/bin/server-status" "$CHOME/bin/claude-stop"
chmod 755 "$CHOME/bin/server-status" "$CHOME/bin/claude-stop"

# Разрешаем Claude запускать server-status без вопроса.
python3 - "$CHOME/.claude/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
settings = json.load(open(path)) if os.path.exists(path) else {}
allow = settings.setdefault("permissions", {}).setdefault("allow", [])
if "Bash(~/bin/server-status)" not in allow:
    allow.append("Bash(~/bin/server-status)")
with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
PY
chown "$CUSER:$CUSER" "$CHOME/.claude/settings.json"

# --- 4. Раздел «Команды и кнопки» в CLAUDE.md ---------------------------------
# Тот же текст есть в шаблоне setup.sh: меняйте оба места вместе.
cat > "$tmp/buttons.md" <<'MD'
<!-- buttons:start -->
## Команды и кнопки

Владелец управляет тобой кнопками Telegram. Нажатие приходит текстом: надписью
кнопки («▶️ Далее») или командой («/next»). Оба варианта означают одно и то же.

| Кнопка | Команда | Что делать |
|---|---|---|
| ▶️ Далее | /next | Продолжить текущую задачу по согласованному плану. |
| 🛠 Реализуй | /implement | Реализовать план из твоего последнего сообщения в согласованном объёме. Если плана в последнем сообщении нет, так и сказать и ничего не начинать. |
| ✅ ОК | /ok | Обычное согласие с последним предложением. |
| 📊 Статус | /status | Кратко, без новой работы: что делаю, что сделано, чего жду. |
| 🔔 Ждут ответа | /waiting | Список твоих открытых вопросов к владельцу или «вопросов нет». |
| ⏹ Остановить | /stop | Прекратить текущую задачу, коротко написать, на чём остановился, ничего не начинать. |
| 🖥 Сервер | /server | Выполнить `~/bin/server-status` и прислать вывод. Только чтение. |
| ❓ Помощь | /help | Прислать справку из раздела ниже. |

### Правила безопасности
- «Далее», «ОК» и «Реализуй» НЕ подтверждают необратимые действия: удаление файлов,
  изменения на боевом сайте, `git push --force`, траты денег. Для них нужен явный
  ответ владельца вида «Да, <действие>» на конкретный вопрос.
- Если ждёшь ответа на вопрос, а пришло «Далее», не продолжай молча: повтори вопрос.
- Если работа заблокирована (лимит, нет доступа, ошибка), «Далее» не повторяет
  попытку по кругу: назови причину и жди решения.

### Справка для «❓ Помощь»
▶️ Далее — продолжить по плану. 🛠 Реализуй — выполнить предложенный план.
✅ ОК — согласие. 📊 Статус — что делаю сейчас. 🔔 Ждут ответа — мои вопросы к вам.
⏹ Остановить — прекратить задачу. 🖥 Сервер — состояние сервера.
Кнопки не подтверждают удаление, изменения на сайте и траты: на такое я спрошу отдельно,
ответьте «Да, <действие>».
Команды /status и /help из меню Telegram перехватывает сам плагин и отвечает за меня,
поэтому для них нажимайте кнопки 📊 и ❓.
Если ⏹ не сработала посреди долгой задачи, аварийная остановка из консоли сервера:
su - claude -c claude-stop
<!-- buttons:end -->
MD

md="$WORK/CLAUDE.md"
touch "$md"
python3 - "$md" "$tmp/buttons.md" <<'PY'
import re, sys
path, section = sys.argv[1], open(sys.argv[2], encoding="utf-8").read().strip()
text = open(path, encoding="utf-8").read()
pattern = re.compile(r"<!-- buttons:start -->.*?<!-- buttons:end -->", re.S)
if pattern.search(text):
    text = pattern.sub(lambda _: section, text)
else:
    text = text.rstrip() + "\n\n" + section + "\n"
open(path, "w", encoding="utf-8").write(text)
PY
chown "$CUSER:$CUSER" "$md"
echo "CLAUDE.md: раздел «Команды и кнопки» обновлён"
echo "Помощники: ~/bin/server-status, ~/bin/claude-stop"

[ "$rc" -eq 0 ] || exit 1
echo "Готово. Перезапустите бота, чтобы Claude перечитал CLAUDE.md: systemctl restart claude-telegram"
