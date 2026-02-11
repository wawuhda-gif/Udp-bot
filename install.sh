#!/bin/bash
# Zivpn UDP Module Manager (Full Version)
# All-in-One: Installer, VPS Dashboard, & Telegram Bot

CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"

# --- Fungsi Pendukung ---
get_ip() { curl -s https://ifconfig.me; }

# --- Fungsi Instalasi Utama ---
install_zivpn() {
    clear
    echo "======================================"
    echo "      MEMULAI INSTALASI ZIVPN         "
    echo "======================================"
    echo "Mengupdate Server & Dependensi..."
    sudo apt-get update && sudo apt-get install jq curl lsb-release -y
    
    systemctl stop zivpn.service 1> /dev/null 2> /dev/null
    
    echo "Mendownload UDP Service..."
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN_PATH 1> /dev/null 2> /dev/null
    chmod +x $BIN_PATH
    mkdir -p /etc/zivpn
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O $CONFIG_FILE 1> /dev/null 2> /dev/null

    echo "Membuat Sertifikat SSL..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    
    echo "Optimasi Jaringan..."
    sysctl -w net.core.rmem_max=16777216 1> /dev/null 2> /dev/null
    sysctl -w net.core.wmem_max=16777216 1> /dev/null 2> /dev/null

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

    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    # Setup IPTABLES & UFW
    ETH=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    iptables -t nat -A PREROUTING -i $ETH -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    ufw allow 6000:19999/udp
    ufw allow 5667/udp
    
    # Pasang Shortcut agar bisa dipanggil dengan ketik 'zivpn'
    cp "$0" "$MENU_PATH"
    chmod +x "$MENU_PATH"
    
    echo "--------------------------------------"
    echo "INSTALASI BERHASIL!"
    echo "Ketik 'zivpn' untuk membuka menu."
    echo "--------------------------------------"
    sleep 3
}

# --- Fitur Bot Telegram (Setup Setelah Install) ---
setup_bot() {
    clear
    echo "======================================"
    echo "      SETUP BOT TELEGRAM REMOTE       "
    echo "======================================"
    echo "Dapatkan Token dari @BotFather"
    echo "Dapatkan ID Admin dari @Userinfobot"
    echo "--------------------------------------"
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
                    msg="🏠 *ZIVPN UDP MENU*%0A%0A1. /add\_akun - Create Akun%0A2. /del\_akun - Hapus Akun%0A3. /list - List Akun%0A4. /vps - Info Status VPS%0A5. /restart - Restart Server" ;;
                "/add_"*)
                    new_pw=\${text#/add_}
                    if [[ -z "\$new_pw" || "\$text" == "/add_akun" ]]; then
                        msg="Format salah! Gunakan: \`/add_PASSWORD\`%0AContoh: \`/add_vip77\`"
                    else
                        sed -i "s/\"config\": \[/\"config\": [\"\$new_pw\", /g" $CONFIG_FILE
                        systemctl restart zivpn.service
                        msg="✅ *AKUN BERHASIL DIBUAT*%0A%0AIP: \$(curl -s ifconfig.me)%0APass: \$new_pw%0APort: 6000-19999"
                    fi ;;
                "/del_"*)
                    del_pw=\${text#/del_}
                    if [[ -z "\$del_pw" || "\$text" == "/del_akun" ]]; then
                        accs=\$(grep -Po '(?<="config": \[).*?(?=\])' $CONFIG_FILE | tr -d '" ' | tr ',' '\n' | grep -v '^$')
                        msg="Ketik: \`/del_PASSWORD\`%0A%0A*LIST PW:*%0A\$accs"
                    else
                        sed -i "s/\"\$del_pw\"//g" $CONFIG_FILE
                        sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
                        systemctl restart zivpn.service
                        msg="🗑 Akun \`\$del_pw\` telah dihapus."
                    fi ;;
                "/list")
                    accs=\$(grep -Po '(?<="config": \[).*?(?=\])' $CONFIG_FILE | tr -d '" ' | tr ',' '\n' | grep -v '^$')
                    msg="📂 *AKUN AKTIF:*%0A\$accs" ;;
                "/vps")
                    msg="📊 *INFO VPS*%0A%0AIP: \$(curl -s ifconfig.me)%0ARAM: \$(free -h | awk '/^Mem:/ {print \$3}')/\$(free -h | awk '/^Mem:/ {print \$2}')%0AUptime: \$(uptime -p)" ;;
                "/restart")
                    systemctl restart zivpn.service ; msg="🔄 Service Restarted!" ;;
            esac
            curl -s -X POST "\$API_URL/sendMessage" -d chat_id="\$chat_id" -d text="\$msg" -d parse_mode="Markdown" > /dev/null
        fi
    done
    sleep 2
done
EOF
    chmod +x $BOT_SCRIPT
    
    # Create Systemd Bot Service
    cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=Zivpn Telegram Bot Service
After=network.target
[Service]
ExecStart=$BOT_SCRIPT
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable zivpn-bot.service && systemctl start zivpn-bot.service
    echo "Bot Berhasil Diaktifkan! Silakan cek Telegram Anda." ; sleep 2
}

# --- Logika Utama (Loop Menu VPS) ---

# Cek apakah sudah terinstall
if [ ! -f "$BIN_PATH" ]; then
    install_zivpn
fi

while true; do
    clear
    # INFO VPS DI ATAS MENU
    IP_VPS=$(get_ip)
    UPTIME=$(uptime -p | cut -d " " -f 2-)
    RAM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    OS=$(lsb_release -ds)
    DOMAIN=$(openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt 2>/dev/null | sed -n '/^subject/s/^.*CN = //p')

    echo "======================================================"
    echo "                ZIVPN UDP DASHBOARD                  "
    echo "======================================================"
    echo " OS     : $OS"
    echo " IP     : $IP_VPS"
    echo " RAM    : $RAM"
    echo " Uptime : $UPTIME"
    echo " Status : $(systemctl is-active zivpn) | Bot: $(systemctl is-active zivpn-bot 2>/dev/null || echo 'off')"
    echo "======================================================"
    echo "  1) Create Akun (Tambah)   4) Change Domain/Host"
    echo "  2) Hapus Akun             5) Restart Service"
    echo "  3) List Semua Akun        6) SETUP BOT TELEGRAM"
    echo "  x) Exit"
    echo "======================================================"
    read -p " Pilih menu [1-6 atau x]: " opt

    case $opt in
        1)
            echo -e "\n--- CREATE NEW ACCOUNT ---"
            read -p "Masukkan Password Baru: " new_pass
            if [[ -n "$new_pass" ]]; then
                sed -i "s/\"config\": \[/\"config\": [\"$new_pass\", /g" $CONFIG_FILE
                systemctl restart zivpn.service
                clear
                echo "=============================="
                echo "     AKUN BERHASIL DIBUAT     "
                echo "=============================="
                echo " Host : ${DOMAIN:-$IP_VPS}"
                echo " IP   : $IP_VPS"
                echo " Pass : $new_pass"
                echo " Port : 6000-19999 (UDP)"
                echo "=============================="
                read -p "Tekan Enter untuk kembali..."
            fi ;;
        2)
            echo -e "\n--- DELETE ACCOUNT ---"
            read -p "Masukkan Password yang ingin dihapus: " del_pass
            sed -i "s/\"$del_pass\"//g" $CONFIG_FILE
            sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
            systemctl restart zivpn.service
            echo "Akun '$del_pass' telah dihapus." ; sleep 1 ;;
        3)
            echo -e "\n--- LIST AKUN AKTIF ---"
            grep -Po '(?<="config": \[).*?(?=\])' $CONFIG_FILE | tr -d '" ' | tr ',' '\n' | grep -v '^$'
            echo "-----------------------" ; read -p "Tekan Enter..." ;;
        4)
            read -p "Masukkan Domain Baru: " new_dom
            openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=$new_dom" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
            systemctl restart zivpn.service ; echo "Domain Diperbarui!" ; sleep 1 ;;
        5) systemctl restart zivpn.service ; echo "Restarted!" ; sleep 1 ;;
        6) setup_bot ;;
        x) exit ;;
    esac
done
