#!/bin/bash
# Zivpn UDP Module Manager - Fixed Bot Connection
# Fitur: Bot & VPS Sync, Keyboard Menu, Auto-Start Bot

CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"
EXP_FILE="/etc/zivpn/expiration.db"

mkdir -p /etc/zivpn
touch $EXP_FILE

get_ip() { curl -s https://ifconfig.me; }

# --- Fungsi Instalasi Utama ---
install_zivpn() {
    clear
    echo "======================================"
    echo "      INSTALLING ZIVPN BINARY         "
    echo "======================================"
    sudo apt-get update -y && sudo apt-get install jq curl wget lsb-release openssl -y
    
    # Perbaikan Download Bin
    rm -f $BIN_PATH
    wget -q --show-progress "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O $BIN_PATH
    if [[ ! -s $BIN_PATH ]]; then
        wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/udp-zivpn-linux-amd64" -O $BIN_PATH
    fi
    chmod +x $BIN_PATH

    # Config & SSL
    wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" -O $CONFIG_FILE
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=JK/L=JK/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    
    # Service VPN
    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=Zivpn UDP Service
After=network.target
[Service]
ExecStart=$BIN_PATH server -c $CONFIG_FILE
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable zivpn.service && systemctl restart zivpn.service
    cp "$0" "$MENU_PATH" && chmod +x "$MENU_PATH"
    echo "Binary Installed! Ketik 'zivpn' untuk menu."; sleep 2
}

# --- Fitur Bot Telegram (Fixed Connection) ---
setup_bot() {
    clear
    echo "=== SETUP BOT TELEGRAM ==="
    read -p "Masukkan Token Bot: " BOT_TOKEN
    read -p "Masukkan ID Admin: " ADMIN_ID
    
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo "Error: Data tidak lengkap!"; sleep 2; return
    fi

    cat <<'EOF' > $BOT_SCRIPT
#!/bin/bash
TOKEN="REPLACE_TOKEN"
CHAT_ID="REPLACE_ADMIN"
API_URL="https://api.telegram.org/bot$TOKEN"
EXP_FILE="/etc/zivpn/expiration.db"
CONFIG_FILE="/etc/zivpn/config.json"

# Pastikan temp file index ada
echo 0 > /tmp/t_idx

send_menu() {
    local text="🏠 *ZIVPN UDP MENU*%0A━━━━━━━━━━━━━━━%0A1️⃣ Buat Akun Baru%0A2️⃣ Hapus Akun%0A3️⃣ List Semua Akun%0A4️⃣ Restart Service%0A5️⃣ Status VPS%0A━━━━━━━━━━━━━━━"
    local keyboard='{"inline_keyboard": [
        [{"text": "1) Buat Akun", "callback_data": "/add_info"}, {"text": "2) Hapus Akun", "callback_data": "/del_info"}],
        [{"text": "3) List Akun", "callback_data": "/list"}, {"text": "4) Restart", "callback_data": "/restart"}],
        [{"text": "5) Status VPS", "callback_data": "/vps"}]
    ]}'
    curl -s -X POST "$API_URL/sendMessage" -d chat_id="$CHAT_ID" -d text="$text" -d parse_mode="Markdown" -d reply_markup="$keyboard"
}

while true; do
    # Ambil update hanya pesan yang belum dibaca
    curr_idx=$(cat /tmp/t_idx)
    updates=$(curl -s "$API_URL/getUpdates?offset=$curr_idx&timeout=30")
    
    # Cek jika ada hasil
    res_count=$(echo "$updates" | jq '.result | length')
    
    if [[ "$res_count" -gt 0 ]]; then
        for row in $(echo "$updates" | jq -r '.result[] | @base64'); do
            _jq() { echo ${row} | base64 --decode | jq -r ${1}; }
            
            update_id=$(_jq '.update_id')
            # Simpan index berikutnya agar tidak double proses
            echo $((update_id + 1)) > /tmp/t_idx
            
            c_id=$(_jq '.message.chat.id // .callback_query.message.chat.id')
            text=$(_jq '.message.text // .callback_query.data')

            if [[ "$c_id" == "$CHAT_ID" ]]; then
                case $text in
                    "/start"|"/menu") send_menu ;;
                    "/add_info") msg="*1) BUAT AKUN*%0AKetik: \`/add [pass] [hari]\`%0AContoh: \`/add premium 30\`" ;;
                    "/del_info") msg="*2) HAPUS AKUN*%0AKetik: \`/del [pass]\`%0AContoh: \`/del premium\`" ;;
                    "/add "*)
                        p=$(echo $text | awk '{print $2}'); d=$(echo $text | awk '{print $3}')
                        if [[ -n "$p" && -n "$d" ]]; then
                            exp=$(date -d "+$d days" +%Y-%m-%d); ip=$(curl -s ifconfig.me)
                            tmp=$(mktemp); jq --arg u "$p" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                            echo "$p:$exp" >> $EXP_FILE; systemctl restart zivpn.service
                            msg="✅ *SUKSES*%0AIP: \`$ip\`%0APass: \`$p\`%0AExp: $exp"
                        else msg="❌ Format: \`/add [pass] [hari]\`"; fi ;;
                    "/del "*)
                        p=$(echo $text | awk '{print $2}')
                        if grep -q "^$p:" "$EXP_FILE"; then
                            tmp=$(mktemp); jq --arg u "$p" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                            sed -i "/^$p:/d" $EXP_FILE; systemctl restart zivpn.service; msg="🗑 Akun \`$p\` Dihapus!"; else msg="❌ Gagal!"; fi ;;
                    "/list")
                        res="*3) LIST AKUN*%0A"
                        while IFS=":" read -r u e; do res+="👤 \`$u\` | Exp: \`$e\`%0A"; done < $EXP_FILE; msg="$res" ;;
                    "/restart") systemctl restart zivpn.service; msg="✅ Service restarted!";;
                    "/vps") msg="*5) STATUS VPS*%0AIP: \`$(curl -s ifconfig.me)\`%0ARAM: \`$(free -h | awk '/^Mem:/ {print $3}')\`" ;;
                esac
                [[ -n "$msg" ]] && curl -s -X POST "$API_URL/sendMessage" -d chat_id="$CHAT_ID" -d text="$msg" -d parse_mode="Markdown" && unset msg
            fi
        done
    fi
    sleep 1
done
EOF

    # Inject Token & ID
    sed -i "s/REPLACE_TOKEN/$BOT_TOKEN/g" $BOT_SCRIPT
    sed -i "s/REPLACE_ADMIN/$ADMIN_ID/g" $BOT_SCRIPT
    chmod +x $BOT_SCRIPT

    # Service Bot (Agar bot tetap jalan meskipun SSH logout)
    cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=Zivpn Bot Telegram
After=network.target
[Service]
ExecStart=/bin/bash $BOT_SCRIPT
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable zivpn-bot.service && systemctl restart zivpn-bot.service
    echo "Bot Diaktifkan! Silahkan cek Telegram Anda."; sleep 2
}

# --- Dashboard VPS ---
if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi
while true; do
    clear
    echo "======================================================"
    echo "                ZIVPN UDP DASHBOARD                  "
    echo "======================================================"
    echo " 1) Buat Akun Baru"
    echo " 2) Hapus Akun"
    echo " 3) List Semua Akun"
    echo " 4) Restart Service"
    echo " 5) Setup Bot Telegram"
    echo " x) Keluar"
    echo "======================================================"
    read -p " Pilih: " opt
    case $opt in
        1) read -p "Pass: " p; read -p "Hari: " d
           exp=$(date -d "+$d days" +%Y-%m-%d); tmp=$(mktemp)
           jq --arg u "$p" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
           echo "$p:$exp" >> $EXP_FILE; systemctl restart zivpn.service
           echo "Sukses!"; read ;;
        2) read -p "Pass hapus: " p; tmp=$(mktemp)
           jq --arg u "$p" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
           sed -i "/^$p:/d" $EXP_FILE; systemctl restart zivpn.service; sleep 1 ;;
        3) cat $EXP_FILE; read ;;
        4) systemctl restart zivpn.service; sleep 1 ;;
        5) setup_bot ;;
        x) exit ;;
    esac
done
