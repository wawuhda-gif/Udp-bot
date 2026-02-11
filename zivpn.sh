#!/bin/bash
# Zivpn UDP Module Manager (Integrated & Fixed)
# Fitur: Masa Aktif, Bot Telegram (IP, Pass, Exp Berurutan), & JQ Support

CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"
EXP_FILE="/etc/zivpn/expiration.db"

# Inisialisasi Database & Folder
mkdir -p /etc/zivpn
touch $EXP_FILE

# --- Fungsi Pendukung ---
get_ip() { curl -s https://ifconfig.me; }

count_active_acc() {
    local total=0
    curr_date=$(date +%Y-%m-%d)
    while IFS=":" read -r user exp; do
        if [[ "$curr_date" < "$exp" || "$curr_date" == "$exp" ]]; then
            ((total++))
        fi
    done < "$EXP_FILE"
    echo "$total"
}

# --- Fungsi Instalasi Utama ---
install_zivpn() {
    clear
    echo "======================================"
    echo "      MEMULAI INSTALASI ZIVPN          "
    echo "======================================"
    
    mkdir -p /etc/zivpn
    mkdir -p /usr/local/bin

    echo "Mengupdate Server & Dependensi..."
    sudo apt-get update -y && sudo apt-get install jq curl wget lsb-release openssl -y
    
    echo "Mendownload UDP Service..."
    rm -f $BIN_PATH
    wget -q --show-progress "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O $BIN_PATH
    
    if [[ ! -f "$BIN_PATH" || ! -s "$BIN_PATH" ]]; then
        echo "❌ Gagal mendownload! Mencoba link alternatif..."
        wget -q --show-progress "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/udp-zivpn-linux-amd64" -O $BIN_PATH
    fi

    if [[ -f "$BIN_PATH" ]]; then
        chmod +x $BIN_PATH
        echo "✅ Binary berhasil diinstal."
    else
        echo "❌ Gagal mendownload binary. Cek internet!"
        exit 1
    fi

    echo "Mendownload Config..."
    wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" -O $CONFIG_FILE
    if [[ ! -s "$CONFIG_FILE" ]]; then
        echo '{"interface":"eth0","local_addr":":5667","config":["admin"]}' > $CONFIG_FILE
    fi

    echo "Membuat Sertifikat SSL..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    
    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=$BIN_PATH server -c $CONFIG_FILE
Restart=always
RestartSec=3
EOF

    systemctl daemon-reload && systemctl enable zivpn.service && systemctl restart zivpn.service
    
    ETH=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    iptables -t nat -A PREROUTING -i $ETH -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    
    cp "$0" "$MENU_PATH"
    chmod +x "$MENU_PATH"
    echo "INSTALASI SELESAI! Ketik 'zivpn' untuk menu."
    sleep 2
}

# --- Fitur Bot Telegram ---
setup_bot() {
    clear
    echo "=============================================="
    echo "         SETUP BOT TELEGRAM REMOTE            "
    echo "=============================================="
    read -p " 1. Masukkan Token Bot: " BOT_TOKEN
    read -p " 2. Masukkan ID Admin : " ADMIN_ID
    
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo -e "\n[!] Token atau ID tidak boleh kosong!" ; sleep 2 ; return
    fi

    cat <<'EOF' > $BOT_SCRIPT
#!/bin/bash
TOKEN="REPLACE_TOKEN"
CHAT_ID="REPLACE_ADMIN"
API_URL="https://api.telegram.org/bot$TOKEN"
EXP_FILE="/etc/zivpn/expiration.db"
CONFIG_FILE="/etc/zivpn/config.json"

while true; do
    updates=$(curl -s "$API_URL/getUpdates?offset=$(cat /tmp/t_idx 2>/dev/null || echo 0)&timeout=10")
    last_idx=$(echo "$updates" | jq -r '.result[-1].update_id')
    [[ "$last_idx" != "null" ]] && echo $((last_idx + 1)) > /tmp/t_idx

    for row in $(echo "$updates" | jq -r '.result[] | @base64'); do
        _jq() { echo ${row} | base64 --decode | jq -r ${1}; }
        chat_id=$(_jq '.message.chat.id')
        text=$(_jq '.message.text')

        if [[ "$chat_id" == "$CHAT_ID" ]]; then
            case $text in
                "/start"|"/menu")
                    msg="🏠 *ZIVPN UDP BOT*%0A━━━━━━━━━━━━━━━%0A*Buat:* \`/add [pass] [hari]\`%0A*Hapus:* \`/del [pass]\`%0A*List:* /list%0A*Status:* /vps" ;;
                
                "/add "*)
                    u_pass=$(echo $text | awk '{print $2}')
                    u_days=$(echo $text | awk '{print $3}')
                    if [[ -z "$u_pass" || -z "$u_days" ]]; then
                        msg="❌ Gunakan: \`/add [pass] [hari]\`"
                    else
                        exp=$(date -d "+$u_days days" +%Y-%m-%d)
                        ip=$(curl -s ifconfig.me)
                        tmp=$(mktemp)
                        jq --arg u "$u_pass" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                        echo "$u_pass:$exp" >> $EXP_FILE
                        systemctl restart zivpn.service
                        msg="✅ *AKUN BERHASIL DIBUAT*%0A━━━━━━━━━━━━━━━%0A🌐 *IP VPS:* \`$ip\`%0A🔑 *Pass:* \`$u_pass\`%0A📅 *Exp:* \`$exp\` ($u_days Hari)%0A━━━━━━━━━━━━━━━"
                    fi ;;

                "/del "*)
                    u_del=$(echo $text | awk '{print $2}')
                    if grep -q "^$u_del:" "$EXP_FILE"; then
                        tmp=$(mktemp)
                        jq --arg u "$u_del" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                        sed -i "/^$u_del:/d" $EXP_FILE
                        systemctl restart zivpn.service
                        msg="🗑 Akun \`$u_del\` Dihapus!"
                    else
                        msg="❌ Akun tidak ditemukan!"
                    fi ;;

                "/list")
                    res="📂 *DAFTAR AKUN AKTIF*%0A🌐 *IP:* \`$(curl -s ifconfig.me)\`%0A━━━━━━━━━━━━━━━%0A"
                    while IFS=":" read -r u e; do
                        res+="👤 \`$u\` -> Exp: \`$e\`%0A"
                    done < $EXP_FILE
                    msg="$res" ;;

                "/vps")
                    msg="📊 *STATUS VPS*%0AIP: \`$(curl -s ifconfig.me)\`%0ARAM: \`$(free -h | awk '/^Mem:/ {print $3}')\`" ;;
            esac
            curl -s -X POST "$API_URL/sendMessage" -d chat_id="$chat_id" -d text="$msg" -d parse_mode="Markdown" > /dev/null
        fi
    done
    sleep 2
done
EOF
    sed -i "s/REPLACE_TOKEN/$BOT_TOKEN/g" $BOT_SCRIPT
    sed -i "s/REPLACE_ADMIN/$ADMIN_ID/g" $BOT_SCRIPT
    chmod +x $BOT_SCRIPT

    cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=Zivpn Telegram Bot
After=network.target
[Service]
ExecStart=$BOT_SCRIPT
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable zivpn-bot.service && systemctl restart zivpn-bot.service
    echo -e "\n[+] Bot Berhasil Aktif!" ; sleep 2
}

# --- Dashboard Utama ---
if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi

while true; do
    clear
    IP_VPS=$(get_ip)
    echo "======================================================"
    echo "                ZIVPN UDP DASHBOARD                  "
    echo "======================================================"
    echo " IP VPS : $IP_VPS"
    echo " STATUS : $(systemctl is-active zivpn) | Bot: $(systemctl is-active zivpn-bot 2>/dev/null || echo 'off')"
    echo "======================================================"
    echo "  1) Buat Akun (Masa Aktif)"
    echo "  2) Hapus Akun"
    echo "  3) List Semua Akun (Detail IP/Pass/Exp)"
    echo "  4) Restart Service"
    echo "  5) SETUP BOT TELEGRAM"
    echo "  x) Keluar"
    echo "======================================================"
    read -p " Pilih menu: " opt

    case $opt in
        1)
            read -p " Password: " new_pass
            read -p " Hari: " durasi
            if [[ -n "$new_pass" ]]; then
                exp_date=$(date -d "+$durasi days" +%Y-%m-%d)
                tmp=$(mktemp)
                jq --arg u "$new_pass" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                echo "$new_pass:$exp_date" >> $EXP_FILE
                systemctl restart zivpn.service
                echo -e "\n✅ BERHASIL: IP: $IP_VPS | Pass: $new_pass | Exp: $exp_date"
                read -p "Enter..."
            fi ;;
        2)
            read -p " Password dihapus: " del_p
            tmp=$(mktemp)
            jq --arg u "$del_p" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
            sed -i "/^$del_p:/d" $EXP_FILE
            systemctl restart zivpn.service
            echo "Dihapus!" ; sleep 1 ;;
        3)
            echo -e "\n--- DAFTAR AKUN ---"
            printf "%-15s | %-12s | %-12s\n" "IP VPS" "PASSWORD" "EXPIRED"
            while IFS=":" read -r u e; do
                printf "%-15s | %-12s | %-12s\n" "$IP_VPS" "$u" "$e"
            done < $EXP_FILE
            read -p "Enter..." ;;
        4) systemctl restart zivpn.service ; echo "Restarted" ; sleep 1 ;;
        5) setup_bot ;;
        x) exit ;;
    esac
done
