#!/bin/bash
# Zivpn UDP Module Manager (Full Integrated Version)
# Fitur: Masa Aktif, Auto-Count Dashboard, & Telegram Bot Sync

CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"
EXP_FILE="/etc/zivpn/expiration.db"

# Inisialisasi Database
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
    echo "Mengupdate Server & Dependensi..."
    sudo apt-get update && sudo apt-get install jq curl lsb-release openssl -y
    
    systemctl stop zivpn.service 1> /dev/null 2> /dev/null
    
    echo "Mendownload UDP Service..."
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN_PATH 1> /dev/null 2> /dev/null
    chmod +x $BIN_PATH
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O $CONFIG_FILE 1> /dev/null 2> /dev/null

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

    systemctl daemon-reload && systemctl enable zivpn.service && systemctl start zivpn.service
    
    ETH=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    iptables -t nat -A PREROUTING -i $ETH -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    
    cp "$0" "$MENU_PATH"
    chmod +x "$MENU_PATH"
    echo "INSTALASI BERHASIL! Ketik 'zivpn' untuk menu."
    sleep 2
}

# --- Fitur Bot Telegram ---
setup_bot() {
    clear
    echo "======================================"
    echo "      SETUP BOT TELEGRAM REMOTE       "
    echo "======================================"
    read -p " Masukkan Token Bot: " BOT_TOKEN
    read -p " Masukkan ID Admin : " ADMIN_ID
    
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo "Token atau ID tidak boleh kosong!" ; sleep 2 ; return
    fi

    cat <<EOF > $BOT_SCRIPT
#!/bin/bash
TOKEN="$BOT_TOKEN"
CHAT_ID="$ADMIN_ID"
API_URL="https://api.telegram.org/bot\$TOKEN"
EXP_FILE="$EXP_FILE"
CONFIG_FILE="$CONFIG_FILE"

while true; do
    updates=\$(curl -s "\$API_URL/getUpdates?offset=\$(cat /tmp/t_idx 2>/dev/null || echo 0)&timeout=10")
    for row in \$(echo "\$updates" | jq -r '.result[] | @base64'); do
        _jq() { echo \${row} | base64 --decode | jq -r \${1}; }
        update_id=\$(_jq '.update_id')
        chat_id=\$(_jq '.message.chat.id')
        text=\$(_jq '.message.text')
        echo \$((update_id + 1)) > /tmp/t_idx

        if [[ "\$chat_id" == "\$CHAT_ID" ]]; then
            case \$text in
                "/start"|"/menu")
                    msg="🏠 *ZIVPN UDP MENU*%0A%0A1. \`/add_PASS_HARI\` - Buat Akun%0A2. \`/del_PASS\` - Hapus Akun%0A3. /list - List Akun%0A4. /vps - Status VPS" ;;
                
                "/add_"*)
                    input=\${text#/add_}
                    IFS='_' read -r user days <<< "\$input"
                    if [[ -z "\$user" || -z "\$days" ]]; then
                        msg="Format salah! Gunakan: \`/add_USER_HARI\`%0AContoh: \`/add_vip77_30\`"
                    else
                        exp=\$(date -d "+\$days days" +%Y-%m-%d)
                        sed -i "s/\"config\": \[/\"config\": [\"\$user\", /g" \$CONFIG_FILE
                        echo "\$user:\$exp" >> \$EXP_FILE
                        systemctl restart zivpn.service
                        msg="✅ *AKUN BERHASIL*%0AUser: \`\$user\`%0AExp: \$exp%0AIP: \$(curl -s ifconfig.me)"
                    fi ;;

                "/del_"*)
                    user=\${text#/del_}
                    sed -i "s/\"\$user\"//g" \$CONFIG_FILE
                    sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' \$CONFIG_FILE
                    sed -i "/^\$user:/d" \$EXP_FILE
                    systemctl restart zivpn.service
                    msg="🗑 Akun \`\$user\` dihapus." ;;

                "/list")
                    accs=\$(cat \$EXP_FILE | column -t -s ":")
                    msg="📂 *LIST AKUN:*%0A\`\$accs\`" ;;

                "/vps")
                    msg="📊 *INFO VPS*%0AIP: \$(curl -s ifconfig.me)%0ARAM: \$(free -h | awk '/^Mem:/ {print \$3}')%0AActive: \$(grep -c '^' \$EXP_FILE) Akun" ;;
            esac
            curl -s -X POST "\$API_URL/sendMessage" -d chat_id="\$chat_id" -d text="\$msg" -d parse_mode="Markdown" > /dev/null
        fi
    done
    sleep 2
done
EOF
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
    systemctl daemon-reload && systemctl enable zivpn-bot.service && systemctl start zivpn-bot.service
    echo "Bot Aktif!" ; sleep 2
}

# --- Logika Utama (Dashboard) ---
if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi

while true; do
    clear
    IP_VPS=$(get_ip)
    UPTIME=$(uptime -p | cut -d " " -f 2-)
    RAM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    OS=$(lsb_release -ds)
    ACC_COUNT=$(count_active_acc)
    DOMAIN=$(openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt 2>/dev/null | sed -n '/^subject/s/^.*CN = //p')

    echo "======================================================"
    echo "                ZIVPN UDP DASHBOARD                  "
    echo "======================================================"
    echo " OS     : $OS"
    echo " IP     : $IP_VPS"
    echo " RAM    : $RAM"
    echo " AKUN AKTIF : $ACC_COUNT Akun"
    echo " STATUS : $(systemctl is-active zivpn) | Bot: $(systemctl is-active zivpn-bot 2>/dev/null || echo 'off')"
    echo "======================================================"
    echo "  1) Create Akun (Masa Aktif)  4) Change Domain/Host"
    echo "  2) Hapus Akun                5) Restart Service"
    echo "  3) List Semua Akun           6) SETUP BOT TELEGRAM"
    echo "  x) Exit"
    echo "======================================================"
    read -p " Pilih menu [1-6 atau x]: " opt

    case $opt in
        1)
            read -p " Password Baru: " new_pass
            read -p " Masa Aktif (Hari): " durasi
            if [[ -n "$new_pass" ]]; then
                exp_date=$(date -d "+$durasi days" +%Y-%m-%d)
                sed -i "s/\"config\": \[/\"config\": [\"$new_pass\", /g" $CONFIG_FILE
                echo "$new_pass:$exp_date" >> $EXP_FILE
                systemctl restart zivpn.service
                echo "Berhasil: $new_pass Exp: $exp_date" ; read -p "Enter..."
            fi ;;
        2)
            echo -e "\n--- DAFTAR AKUN ---"
            cat $EXP_FILE | column -t -s ":"
            read -p " Password yang dihapus: " del_pass
            sed -i "s/\"$del_pass\"//g" $CONFIG_FILE
            sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
            sed -i "/^$del_pass:/d" $EXP_FILE
            systemctl restart zivpn.service ; echo "Dihapus!" ; sleep 1 ;;
        3)
            echo -e "\n--- LIST AKUN ---"
            printf "%-20s %-15s\n" "PASSWORD" "EXPIRED"
            echo "-----------------------------------"
            while IFS=":" read -r u e; do printf "%-20s %-15s\n" "$u" "$e"; done < $EXP_FILE
            read -p "Enter..." ;;
        4)
            read -p " Domain Baru: " new_dom
            openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=$new_dom" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
            systemctl restart zivpn.service ;;
        5) systemctl restart zivpn.service ; echo "Restarted!" ; sleep 1 ;;
        6) setup_bot ;;
        x) exit ;;
    esac
done
