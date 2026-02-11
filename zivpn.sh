#!/bin/bash
# Zivpn UDP Module Manager - Full Version
# Fitur: Masa Aktif, Bot Telegram (Keyboard Menu), Fixed Bin Installer, JQ Integration

# --- Konfigurasi Path ---
CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"
EXP_FILE="/etc/zivpn/expiration.db"

# Inisialisasi Database & Direktori
mkdir -p /etc/zivpn
touch $EXP_FILE

# --- Fungsi Pendukung ---
get_ip() { 
    curl -s https://ifconfig.me
}

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

# --- Fungsi Instalasi Utama (Fix Bin) ---
install_zivpn() {
    clear
    echo "======================================"
    echo "      MEMULAI INSTALASI ZIVPN          "
    echo "======================================"
    
    # Update & Install Dependensi
    echo "Mengupdate Server & Dependensi..."
    sudo apt-get update -y && sudo apt-get install jq curl wget lsb-release openssl -y
    
    mkdir -p /etc/zivpn
    
    echo "Mendownload UDP Service..."
    # Menghapus file lama dan mencoba download dengan link yang divalidasi
    rm -f $BIN_PATH
    wget -q --show-progress "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O $BIN_PATH
    
    # Validasi: Jika link utama gagal/file 0 byte, coba link cadangan
    if [[ ! -s $BIN_PATH ]]; then
        echo "Link utama gagal, mencoba link cadangan..."
        wget -q --show-progress "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/udp-zivpn-linux-amd64" -O $BIN_PATH
    fi

    if [[ -s $BIN_PATH ]]; then
        chmod +x $BIN_PATH
        echo "✅ Binary berhasil diinstal."
    else
        echo "❌ Gagal mendownload binary Zivpn. Periksa koneksi internet VPS!"
        exit 1
    fi
    
    # Mendownload Config Default
    wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" -O $CONFIG_FILE
    if [[ ! -s $CONFIG_FILE ]]; then
        echo '{"interface":"eth0","local_addr":":5667","config":["admin"]}' > $CONFIG_FILE
    fi

    echo "Membuat Sertifikat SSL..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    
    # Membuat Systemd Service
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
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable zivpn.service && systemctl restart zivpn.service
    
    # Konfigurasi Iptables Port UDP
    ETH=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    iptables -t nat -A PREROUTING -i $ETH -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    
    # Instalasi Menu Shortcut
    cp "$0" "$MENU_PATH"
    chmod +x "$MENU_PATH"
    echo "======================================"
    echo "INSTALASI BERHASIL! Ketik 'zivpn' untuk membuka menu."
    echo "======================================"
    sleep 2
}

# --- Fitur Bot Telegram (Keyboard Menu Rapi) ---
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

    # Script Bot (Menggunakan 'EOF' agar variabel tidak pecah saat ditulis ke file)
    cat <<'EOF' > $BOT_SCRIPT
#!/bin/bash
TOKEN="REPLACE_TOKEN"
CHAT_ID="REPLACE_ADMIN"
API_URL="https://api.telegram.org/bot$TOKEN"
EXP_FILE="/etc/zivpn/expiration.db"
CONFIG_FILE="/etc/zivpn/config.json"

send_menu() {
    local text="🏠 *ZIVPN UDP DASHBOARD*%0ASilahkan pilih menu di bawah ini:"
    local keyboard='{"inline_keyboard": [
        [{"text": "📋 List Akun", "callback_data": "/list"}, {"text": "🖥 Status VPS", "callback_data": "/vps"}],
        [{"text": "📊 Bandwidth", "callback_data": "/bw"}, {"text": "📁 Backup", "callback_data": "/backup"}],
        [{"text": "♻️ Restore", "callback_data": "/restore"}],
        [{"text": "🔄 Restart Service", "callback_data": "/restart"}],
        [{"text": "➕ Add User", "callback_data": "/add_info"}, {"text": "🗑 Del User", "callback_data": "/del_info"}],
        [{"text": "🔄 Perpanjang Akun", "callback_data": "/renew"}]
    ]}'
    curl -s -X POST "$API_URL/sendMessage" -d chat_id="$CHAT_ID" -d text="$text" -d parse_mode="Markdown" -d reply_markup="$keyboard" > /dev/null
}

while true; do
    updates=$(curl -s "$API_URL/getUpdates?offset=$(cat /tmp/t_idx 2>/dev/null || echo 0)&timeout=10")
    for row in $(echo "$updates" | jq -r '.result[] | @base64'); do
        _jq() { echo ${row} | base64 --decode | jq -r ${1}; }
        update_id=$(_jq '.update_id')
        chat_id=$(_jq '.message.chat.id // .callback_query.message.chat.id')
        text=$(_jq '.message.text // .callback_query.data')
        echo $((update_id + 1)) > /tmp/t_idx

        if [[ "$chat_id" == "$CHAT_ID" ]]; then
            case $text in
                "/start"|"/menu") send_menu ;;
                "/add_info") msg="*Cara Tambah Akun:*%0AKetik: \`/add [pass] [hari]\`%0AContoh: \`/add vip77 30\`" ;;
                "/del_info") msg="*Cara Hapus Akun:*%0AKetik: \`/del [pass]\`%0AContoh: \`/del vip77\`" ;;
                
                "/add "*)
                    u_pass=$(echo $text | awk '{print $2}')
                    u_days=$(echo $text | awk '{print $3}')
                    if [[ -n "$u_pass" && -n "$u_days" ]]; then
                        exp_date=$(date -d "+$u_days days" +%Y-%m-%d)
                        ip_vps=$(curl -s ifconfig.me)
                        # Input ke JSON via JQ
                        tmp=$(mktemp)
                        jq --arg u "$u_pass" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                        echo "$u_pass:$exp_date" >> $EXP_FILE
                        systemctl restart zivpn.service
                        msg="✅ *AKUN BERHASIL DIBUAT*%0A━━━━━━━━━━━━━━━━━━━━━%0A🌐 *IP VPS:* \`$ip_vps\`%0A👤 *Pass:* \`$u_pass\`%0A📅 *Exp:* \`$exp_date\` ($u_days Hari)%0A━━━━━━━━━━━━━━━━━━━━━"
                    else
                        msg="❌ *Format Salah!*%0AGunakan: \`/add [pass] [hari]\`"
                    fi ;;

                "/del "*)
                    u_del=$(echo $text | awk '{print $2}')
                    if grep -q "^$u_del:" "$EXP_FILE"; then
                        tmp=$(mktemp)
                        jq --arg u "$u_del" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                        sed -i "/^$u_del:/d" $EXP_FILE
                        systemctl restart zivpn.service
                        msg="🗑 Akun \`$u_del\` berhasil dihapus!"
                    else
                        msg="❌ Akun \`$u_del\` tidak ditemukan!"
                    fi ;;

                "/list")
                    res="📂 *DAFTAR AKUN AKTIF*%0A━━━━━━━━━━━━━━━━━━━━━%0A"
                    while IFS=":" read -r u e; do
                        res+="👤 \`$u\` | Exp: \`$e\`%0A"
                    done < $EXP_FILE
                    msg="$res" ;;

                "/vps")
                    msg="📊 *STATUS VPS*%0A━━━━━━━━━━━━━━━━━━━━━%0A📍 IP: \`$(curl -s ifconfig.me)\`%0A📟 RAM: \`$(free -h | awk '/^Mem:/ {print $3 "/" $2}')\`%0A👥 Aktif: \`$(grep -c '^' $EXP_FILE) User\`" ;;

                "/restart")
                    systemctl restart zivpn.service
                    msg="✅ Service Zivpn restarted!" ;;
            esac
            
            if [[ -n "$msg" ]]; then
                curl -s -X POST "$API_URL/sendMessage" -d chat_id="$chat_id" -d text="$msg" -d parse_mode="Markdown" > /dev/null
                unset msg
            fi
        fi
    done
    sleep 2
done
EOF
    # Memasukkan Token & Admin ID asli
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
    echo -e "\n[+] Bot Telegram Berhasil Diaktifkan!" ; sleep 2
}

# --- Logika Menu Utama Dashboard ---
if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi

while true; do
    clear
    IP_VPS=$(get_ip)
    ACC_COUNT=$(count_active_acc)
    echo "======================================================"
    echo "                ZIVPN UDP DASHBOARD                  "
    echo "======================================================"
    echo " IP VPS : $IP_VPS"
    echo " AKUN AKTIF : $ACC_COUNT Akun"
    echo " STATUS : $(systemctl is-active zivpn) | Bot: $(systemctl is-active zivpn-bot 2>/dev/null || echo 'off')"
    echo "======================================================"
    echo "  1) Buat Akun Baru (Masa Aktif)"
    echo "  2) Hapus Akun"
    echo "  3) List Akun (Detail IP/Pass/Exp)"
    echo "  4) Restart Service"
    echo "  5) SETUP BOT TELEGRAM (Menu Tombol)"
    echo "  x) Keluar"
    echo "======================================================"
    read -p " Pilih menu [1-5 atau x]: " opt

    case $opt in
        1)
            echo -e "\n--- BUAT AKUN BARU ---"
            read -p " Password Akun: " p
            read -p " Masa Aktif (Hari): " d
            if [[ -n "$p" && -n "$d" ]]; then
                exp=$(date -d "+$d days" +%Y-%m-%d)
                tmp=$(mktemp)
                jq --arg u "$p" '.config += [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                echo "$p:$exp" >> $EXP_FILE
                systemctl restart zivpn.service
                clear
                echo "✅ AKUN BERHASIL DIBUAT"
                echo "-----------------------"
                echo " IP VPS  : $IP_VPS"
                echo " Pass    : $p"
                echo " Expired : $exp ($d Hari)"
                echo "-----------------------"
                read -p "Tekan Enter untuk kembali..."
            fi ;;
        2)
            echo -e "\n--- HAPUS AKUN ---"
            read -p " Password yang dihapus: " p
            if grep -q "^$p:" "$EXP_FILE"; then
                tmp=$(mktemp)
                jq --arg u "$p" '.config -= [$u]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
                sed -i "/^$p:/d" $EXP_FILE
                systemctl restart zivpn.service
                echo "Akun '$p' berhasil dihapus!" ; sleep 1
            else
                echo "Akun tidak ditemukan!" ; sleep 1
            fi ;;
        3)
            echo -e "\n--- DAFTAR AKUN AKTIF ---"
            echo "--------------------------------------------------------"
            printf "%-15s | %-15s | %-15s\n" "IP VPS" "PASSWORD" "EXPIRED"
            echo "--------------------------------------------------------"
            while IFS=":" read -r u e; do
                printf "%-15s | %-15s | %-15s\n" "$IP_VPS" "$u" "$e"
            done < $EXP_FILE
            echo "--------------------------------------------------------"
            read -p "Tekan Enter untuk kembali..." ;;
        4) systemctl restart zivpn.service ; echo "Service Restarted!" ; sleep 1 ;;
        5) setup_bot ;;
        x) exit ;;
        *) echo "Pilihan salah!" ; sleep 1 ;;
    esac
done
