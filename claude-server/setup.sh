#!/usr/bin/env bash
# Установка Claude Code + Telegram-бота на VPS (Ubuntu 24.04).
# Запуск от root:  bash setup.sh
# Повторный запуск безопасен: уже сделанные шаги пропускаются.
set -euo pipefail

OWNER_TG_ID="${OWNER_TG_ID:-5472230307}"   # Telegram ID владельца
CUSER=claude
CHOME=/home/$CUSER
WORK=$CHOME/work
SERVICE=claude-telegram

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mОШИБКА: %s\033[0m\n' "$*" >&2; exit 1; }
asuser() { sudo -u "$CUSER" -H bash -lc "$1"; }

[ "$(id -u)" -eq 0 ] || die "запустите от root: sudo bash setup.sh"
export DEBIAN_FRONTEND=noninteractive

# --- 0. Предпроверка -------------------------------------------------------
say "Проверяю, доступны ли с этого сервера Claude и Telegram"
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }

anth_code="$(curl -s -o /tmp/anth.txt --max-time 15 -w '%{http_code}' https://api.anthropic.com/v1/messages || true)"
if [ "$anth_code" = "000" ] || [ "$anth_code" = "403" ] || grep -qi 'not allowed' /tmp/anth.txt 2>/dev/null; then
  cat /tmp/anth.txt 2>/dev/null; echo
  die "Claude (api.anthropic.com) недоступен с этого сервера (код $anth_code).
       Создайте сервер в другой стране (Нидерланды, Германия) и запустите скрипт там."
fi
echo "Claude: доступен (код $anth_code)"

tg_code="$(curl -s -o /dev/null --max-time 15 -w '%{http_code}' https://api.telegram.org || true)"
case "$tg_code" in
  2*|3*) echo "Telegram: доступен (код $tg_code)";;
  *) die "Telegram недоступен с этого сервера (код $tg_code).";;
esac

# --- 1. Система ------------------------------------------------------------
say "Обновляю систему и ставлю пакеты (несколько минут)"
apt-get update -qq
apt-get -y -qq upgrade
apt-get install -y -qq git tmux curl unzip ffmpeg python3-venv python3-pip ufw fail2ban ca-certificates
timedatectl set-timezone Europe/Moscow 2>/dev/null || true

if ! swapon --show | grep -q .; then
  say "Создаю swap 2 ГБ"
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

say "Настраиваю файрвол (открыт только SSH)"
ssh_ports="$(sshd -T 2>/dev/null | awk '/^port /{print $2}')"
for p in ${ssh_ports:-22}; do ufw allow "$p/tcp" >/dev/null; done
ufw --force enable >/dev/null
systemctl enable --now fail2ban >/dev/null 2>&1 || warn "fail2ban не запустился, продолжаю"

say "Создаю пользователя $CUSER"
id "$CUSER" &>/dev/null || adduser --disabled-password --gecos "" "$CUSER" >/dev/null
install -d -m 700 -o "$CUSER" -g "$CUSER" "$CHOME/.ssh" "$CHOME/bin" "$WORK" "$CHOME/.claude"
for f in .profile .bashrc; do
  grep -q 'claude-server PATH' "$CHOME/$f" 2>/dev/null ||
    echo 'export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH" # claude-server PATH' >> "$CHOME/$f"
done
chown "$CUSER:$CUSER" "$CHOME/.profile" "$CHOME/.bashrc"

# --- 2. Bun и Claude Code --------------------------------------------------
say "Ставлю Bun"
asuser '[ -x ~/.bun/bin/bun ] || curl -fsSL https://bun.sh/install | bash >/dev/null'
asuser '~/.bun/bin/bun --version'

say "Ставлю Claude Code"
asuser '[ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash'
asuser '~/.local/bin/claude --version'

# --- 3. Распознавание голосовых (faster-whisper) ---------------------------
say "Ставлю распознавание речи (faster-whisper)"
asuser '[ -x ~/whisper/bin/python ] || python3 -m venv ~/whisper'
asuser '~/whisper/bin/pip install -q --upgrade pip faster-whisper'

cat > "$CHOME/bin/transcribe" <<'PY'
#!/home/claude/whisper/bin/python
"""Расшифровка аудио в текст (русский). Использование: transcribe <файл> | transcribe --warmup"""
import os
import sys


def pick_model():
    if os.environ.get("WHISPER_MODEL"):
        return os.environ["WHISPER_MODEL"]
    with open("/proc/meminfo") as f:
        mem_kb = int(f.readline().split()[1])
    return "small" if mem_kb >= 3 * 1024 * 1024 else "base"


def main():
    if len(sys.argv) != 2:
        sys.exit("Использование: transcribe <аудиофайл>")
    from faster_whisper import WhisperModel

    model = WhisperModel(pick_model(), device="cpu", compute_type="int8",
                         download_root=os.path.expanduser("~/whisper/models"))
    if sys.argv[1] == "--warmup":
        print("Модель загружена")
        return
    segments, _ = model.transcribe(sys.argv[1], language="ru", vad_filter=True)
    print(" ".join(s.text.strip() for s in segments).strip())


if __name__ == "__main__":
    main()
PY

say "Скачиваю модель распознавания (один раз)"
chown "$CUSER:$CUSER" "$CHOME/bin/transcribe"; chmod 755 "$CHOME/bin/transcribe"
asuser '~/bin/transcribe --warmup' || warn "Модель не скачалась сейчас, она скачается при первом голосовом"

# --- 4. Уведомления (вызываются с ПК через SSH) ----------------------------
cat > "$CHOME/bin/notify" <<SH
#!/usr/bin/env bash
# Отправляет владельцу сообщение в Telegram. Текст читается из stdin.
# "STOP:<папка>" превращается в стандартное уведомление о завершении задачи.
set -uo pipefail
OWNER_ID=$OWNER_TG_ID
SH
cat >> "$CHOME/bin/notify" <<'SH'
input="$(head -c 3500 || true)"
input="${input%$'\n'}"; input="${input%$'\r'}"
case "$input" in
  STOP:*) f="${input#STOP:}"; text="✅ Claude закончил задачу${f:+ (папка: $f)}";;
  "")     text="✅ Claude закончил задачу";;
  *)      text="$input";;
esac
token="$(grep -oE '[0-9]+:[A-Za-z0-9_-]{30,}' "$HOME/.claude/channels/telegram/.env" 2>/dev/null | head -1)"
[ -n "$token" ] || { echo "Токен бота не найден: сначала выполните /telegram:configure" >&2; exit 1; }
curl -s --max-time 10 -o /dev/null "https://api.telegram.org/bot${token}/sendMessage" \
  --data-urlencode "chat_id=${OWNER_ID}" --data-urlencode "text=${text}"
SH
chown "$CUSER:$CUSER" "$CHOME/bin/notify"; chmod 755 "$CHOME/bin/notify"

# --- 5. Инструкции для Claude и разрешения ---------------------------------
if [ ! -f "$WORK/CLAUDE.md" ]; then
  cat > "$WORK/CLAUDE.md" <<'MD'
# Работа через Telegram

- Владелец пишет из Telegram. Отвечай туда же, кратко и по-русски.
- Голосовое сообщение: скачай вложение инструментом плагина Telegram, выполни
  `~/bin/transcribe <файл>`, в начале ответа процитируй распознанный текст («🎤 …»),
  затем выполни просьбу. Если распознать не удалось, попроси повторить текстом.
- Длинная задача: сразу коротко напиши, что начал, в конце пришли итог.
- Перед необратимыми действиями (удаление файлов, изменения на боевом сайте,
  `git push --force`) спрашивай подтверждение в Telegram.
- Никогда не показывай содержимое `~/.claude/channels/telegram/.env` и ключей из `~/.ssh`.
MD
  chown "$CUSER:$CUSER" "$WORK/CLAUDE.md"
fi

python3 - "$CHOME/.claude/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
settings = json.load(open(path)) if os.path.exists(path) else {}
perms = settings.setdefault("permissions", {})
rules = {
    "allow": [
        "mcp__plugin_telegram_telegram",
        "Bash(git:*)", "Bash(bun:*)", "Bash(npm:*)", "Bash(node:*)",
        "Bash(python3:*)", "Bash(ffmpeg:*)", "Bash(~/bin/transcribe:*)",
    ],
    "deny": [
        "Bash(sudo:*)",
        "Read(~/.ssh/**)",
        "Read(~/.claude/channels/telegram/.env)",
    ],
}
for key, values in rules.items():
    current = perms.setdefault(key, [])
    current.extend(v for v in values if v not in current)
with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
PY
chown -R "$CUSER:$CUSER" "$CHOME/.claude"

# --- 6. Автозапуск ---------------------------------------------------------
say "Настраиваю автозапуск ($SERVICE)"
cat > /etc/systemd/system/$SERVICE.service <<UNIT
[Unit]
Description=Claude Code + Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$CUSER
WorkingDirectory=$WORK
Environment=HOME=$CHOME
Environment=PATH=$CHOME/bin:$CHOME/.local/bin:$CHOME/.bun/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/tmux new-session -d -s claude -c $WORK "claude --channels plugin:telegram@claude-plugins-official"
ExecStop=/usr/bin/tmux kill-session -t claude
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable $SERVICE >/dev/null 2>&1

say "Готово! Установка завершена."
cat <<TXT

Дальше вручную (подробно в README.md, раздел «Шаг 4»):
  1) su - $CUSER
  2) cd ~/work && claude        — войти в аккаунт, доверить папку
  3) /plugin install telegram@claude-plugins-official   (scope: user)
  4) /telegram:configure <НОВЫЙ токен>
  5) /telegram:access allow $OWNER_TG_ID
  6) /telegram:access policy allowlist
  7) /exit, затем exit
  8) systemctl start $SERVICE
TXT
