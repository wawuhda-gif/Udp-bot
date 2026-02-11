#!/bin/bash
# ZIVPN BOT - INTEGRATED VERSION
# Features: Detailed Account Info & Delete Confirmation

ENV_FILE="/etc/zivpn/bot.env"
[ ! -f "$ENV_FILE" ] && { echo "ENV file not found"; exit 1; }
source "$ENV_FILE"

CONFIG="/etc/zivpn/config.json"
META="/etc/zivpn/accounts_meta.json"
SERVICE="zivpn.service"
OFFSET_FILE="/tmp/zivpn_offset"
BACKUP_DIR="/etc/zivpn"

# State files
STATE_FILE="/tmp/zivpn_state_${ADMIN_ID}"
DATA_FILE="/tmp/zivpn_state_data_${ADMIN_ID}"
LAST_BOT_FILE="/tmp/zivpn_last_bot_${ADMIN_ID}"

# ---------------- Telegram helpers ----------------
tg_post() {
  local method="$1"; shift
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/$method" "$@"
}

delete_msg() {
  local msg_id="$1"
  [ -z "$msg_id" ] && return
  tg_post "deleteMessage" -d "chat_id=$ADMIN_ID" -d "message_id=$msg_id" >/dev/null 2>&1 || true
}

save_last_bot() { echo -n "$1" > "$LAST_BOT_FILE"; }
get_last_bot() { [ -f "$LAST_BOT_FILE" ] && cat "$LAST_BOT_FILE" || echo ""; }
clear_last_bot() { rm -f "$LAST_BOT_FILE"; }

send_msg_raw() {
  local TEXT="$1"
  local RM="$2"
  if [ -n "$RM" ]; then
    tg_post "sendMessage" -d "chat_id=$ADMIN_ID" --data-urlencode "text=$TEXT" --data-urlencode "parse_mode=Markdown" --data-urlencode "reply_markup=$RM"
  else
    tg_post "sendMessage" -d "chat_id=$ADMIN_ID" --data-urlencode "text=$TEXT" --data-urlencode "parse_mode=Markdown"
  fi
}

replace_bot_message() {
  local TEXT="$1"
  local RM="$2"
  local last
  last="$(get_last_bot)"
  [ -n "$last" ] && delete_msg "$last"
  clear_last_bot
  local resp msgid
  resp="$(send_msg_raw "$TEXT" "$RM")"
  msgid="$(echo "$resp" | jq -r '.result.message_id // empty')"
  [ -n "$msgid" ] && save_last_bot "$msgid"
}

answer_cb() {
  local CB_ID="$1"
  local TXT="$2"
  [ -z "$TXT" ] && TXT="OK"
  tg_post "answerCallbackQuery" --data-urlencode "callback_query_id=$CB_ID" --data-urlencode "text=$TXT" >/dev/null
}

# ---------------- State helpers ----------------
set_state() { echo -n "$1" > "$STATE_FILE"; }
get_state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo ""; }
clear_state() { rm -f "$STATE_FILE" "$DATA_FILE"; }
set_pending_user() { echo -n "$1" > "$DATA_FILE"; }
get_pending_user() { [ -f "$DATA_FILE" ] && cat "$DATA_FILE" || echo ""; }

# ---------------- UI markups ----------------
RM_MENU='{"inline_keyboard":[
  [{"text":"📋 List Akun","callback_data":"LIST"},{"text":"🖥 Status VPS","callback_data":"STATUS"}],
  [{"text":"📊 Bandwidth","callback_data":"BANDWIDTH"},{"text":"📂 Backup","callback_data":"BACKUP"}],
  [{"text":"➕ Add User","callback_data":"ADD"},{"text":"🗑 Del User","callback_data":"DEL"}],
  [{"text":"🏠 Menu Utama","callback_data":"MENU"}]
]}'

RM_CANCEL='{"inline_keyboard":[[{"text":"❌ Batal","callback_data":"CANCEL"}]]}'

# ---------------- core logic ----------------

add_user() {
  local USER="$1"
  local DAYS="$2"
  [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=3

  local IP_VPS=$(curl -s ifconfig.me)
  local HOST_NAME=$(hostname)
  local EXP=$(date -d "+$DAYS days" +%Y-%m-%d)

  local exists=$(jq -r --arg u "$USER" '.auth.config[]? | select(.==$u)' "$CONFIG")
  [ -n "$exists" ] && replace_bot_message "❗ User *$USER* sudah ada!" "$RM_MENU" && return

  jq --arg p "$USER" '.auth.config += [$p]' "$CONFIG" > /tmp/conf && mv /tmp/conf "$CONFIG"
  jq --arg u "$USER" --arg e "$EXP" '.accounts += [{"user":$u,"expired":$e}]' "$META" > /tmp/meta && mv /tmp/meta "$META"

  systemctl restart "$SERVICE"

  local MSG="╔══════════════════════╗
   ✅ *AKUN BERHASIL DIBUAT*
╚══════════════════════╝
👤 *Username* : \`$USER\`
🔑 *Password* : \`$USER\`
🌐 *Host* : \`$HOST_NAME\`
📍 *IP VPS* : \`$IP_VPS\`
📅 *Expired* : *$EXP* ($DAYS Hari)
──────────────────────
_Gunakan detail di atas untuk login._"
  replace_bot_message "$MSG" "$RM_MENU"
}

del_user() {
  local USER="$1"
  local DATA_ACC=$(jq -r --arg u "$USER" '.accounts[]? | select(.user==$u)' "$META")
  local EXP_DATE=$(echo "$DATA_ACC" | jq -r '.expired // empty')

  if [ -z "$EXP_DATE" ]; then
    replace_bot_message "❗ User *$USER* tidak ditemukan!" "$RM_MENU"
    return
  fi

  jq --arg p "$USER" '.auth.config |= map(select(. != $p))' "$CONFIG" > /tmp/conf && mv /tmp/conf "$CONFIG"
  jq --arg u "$USER" '.accounts |= map(select(.user != $u))' "$META" > /tmp/meta && mv /tmp/meta "$META"

  systemctl restart "$SERVICE"

  local MSG="╔══════════════════════╗
   🗑️ *AKUN TELAH DIHAPUS*
╚══════════════════════╝
👤 *User* : *$USER*
📅 *Bekas Exp*: *$EXP_DATE*

✅ *Data akun telah dibersihkan dari sistem.*"
  replace_bot_message "$MSG" "$RM_MENU"
}

# ---------------- Loop & Menu ----------------
show_menu() {
  replace_bot_message "✨ *PREMIUM ZIVPN PANEL* ✨\nSilakan pilih menu di bawah:" "$RM_MENU"
}

while true; do
  UPDATES=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/getUpdates" -d "offset=$(cat $OFFSET_FILE 2>/dev/null || echo 0)" -d "timeout=60")
  echo "$UPDATES" | jq -c '.result[]' 2>/dev/null | while read -r row; do
    UPDATE_ID=$(echo "$row" | jq -r '.update_id')
    echo $((UPDATE_ID + 1)) > "$OFFSET_FILE"

    CHAT=$(echo "$row" | jq -r '.message.chat.id // .callback_query.message.chat.id // empty')
    TEXT=$(echo "$row" | jq -r '.message.text // empty')
    CB_DATA=$(echo "$row" | jq -r '.callback_query.data // empty')
    CB_ID=$(echo "$row" | jq -r '.callback_query.id // empty')
    CLICKED_MSG_ID=$(echo "$row" | jq -r '.callback_query.message.message_id // empty')

    [ "$CHAT" != "$ADMIN_ID" ] && continue

    if [ -n "$CB_DATA" ]; then
      answer_cb "$CB_ID"
      [ -n "$CLICKED_MSG_ID" ] && delete_msg "$CLICKED_MSG_ID" && clear_last_bot
      
      case "$CB_DATA" in
        "MENU"|"CANCEL") clear_state; show_menu ;;
        "ADD") set_state "ADD_WAIT_USER"; replace_bot_message "➕ *TAMBAH AKUN*\nKetik *username* baru:" "$RM_CANCEL" ;;
        "DEL") set_state "DEL_WAIT_USER"; replace_bot_message "🗑️ *HAPUS AKUN*\nKetik *username* yang akan dihapus:" "$RM_CANCEL" ;;
        "LIST") 
            LIST=$(jq -r '.accounts[]? | "👤 `\(.user)` | Exp: \(.expired)"' "$META")
            replace_bot_message "📋 *DAFTAR AKUN*\n\n${LIST:-Belum ada akun}" "$RM_MENU" ;;
      esac
      continue
    fi

    STATE=$(get_state)
    case "$STATE" in
      "ADD_WAIT_USER")
        set_pending_user "$TEXT"
        set_state "ADD_WAIT_DAYS"
        replace_bot_message "🗓️ *DURASI*\nUser: *$TEXT*\nBerapa hari akun aktif?" "$RM_CANCEL" ;;
      "ADD_WAIT_DAYS")
        USER=$(get_pending_user)
        clear_state; add_user "$USER" "$TEXT" ;;
      "DEL_WAIT_USER")
        clear_state; del_user "$TEXT" ;;
      *) show_menu ;;
    esac
  done
done
