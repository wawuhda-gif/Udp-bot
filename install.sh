#!/bin/bash
# Zivpn UDP Module Manager (Full Version + Expiry + Rainbow)
# Fitur: Masa Aktif, Auto-Delete, Bot Telegram, & Tampilan Pelangi

CONFIG_FILE="/etc/zivpn/config.json"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"
DB_FILE="/etc/zivpn/database.db"

# Buat database jika belum ada
touch $DB_FILE

# --- KODE WARNA ---
RED='\033[0;31m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
NC='\033[0m' 

# --- Fungsi Pendukung ---
get_ip() { curl -s https://ifconfig.me; }

# Fungsi Cek Masa Aktif (Menghapus jika expired)
check_expiry() {
    today=$(date +%Y-%m-%d)
    tmp_db=$(mktemp)
    while IFS=":" read -r user exp; do
        if [[ "$today" <= "$exp" ]]; then
            echo "$user:$exp" >> "$tmp_db"
        else
            sed -i "s/\"$user\"//g" $CONFIG_FILE
        fi
    done < $DB_FILE
    mv "$tmp_db" $DB_FILE
    sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
}

# --- Fungsi Instalasi Utama ---
install_zivpn() {
    clear
    echo -e "${CYAN}======================================${NC}"
    echo -e "${YELLOW}      MEMULAI INSTALASI ZIVPN         ${NC}"
    echo -e "${CYAN}======================================${NC}"
    sudo apt-get update && sudo apt-get install jq curl lsb-release -y
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN_PATH
    chmod +x $BIN_PATH
    mkdir -p /etc/zivpn
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O $CONFIG_FILE
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=JKT/L=JKT/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    
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
EOF
    systemctl daemon-reload && systemctl enable zivpn.service && systemctl start zivpn.service
    cp "$0" "$MENU_PATH" && chmod +x "$MENU_PATH"
}

# --- Logika Utama (Loop Menu) ---
if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi

while true; do
    check_expiry
    clear
    IP_VPS=$(get_ip)
    RAM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    UPTIME=$(uptime -p | cut -d " " -f 2-)
    OS=$(lsb_release -ds)
    DOMAIN=$(openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt 2>/dev/null | sed -n '/^subject/s/^.*CN = //p')

    # Header ASCII Pelangi
    echo -e "${RED}  ______ ${ORANGE} _____ ${YELLOW} _   _ ${GREEN} _   _ ${BLUE} ____ ${PURPLE}  _   _ ${NC}"
    echo -e "${RED} |___  / ${ORANGE}|_   _|${YELLOW}| | | |${GREEN}| | | |${BLUE}|  _ \ ${PURPLE} | \ | |${NC}"
    echo -e "${RED}    / /  ${ORANGE}  | |  ${YELLOW}| | | |${GREEN}| | | |${BLUE}| |_) |${PURPLE} |  \| |${NC}"
    echo -e "${RED}   / /__ ${ORANGE} _| |_ ${YELLOW} \ V / ${GREEN} \ V / ${BLUE}|  __/ ${PURPLE} | |\  |${NC}"
    echo -e "${RED}  /_____|${ORANGE}|_____|${YELLOW}  \_/  ${GREEN}  \_/  ${BLUE}|_|    ${PURPLE} |_| \_|${NC}"

    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${YELLOW} OS     :${NC} $OS"
    echo -e "${YELLOW} IP     :${NC} $IP_VPS"
    echo -e "${YELLOW} RAM    :${NC} $RAM"
    echo -e "${YELLOW} Uptime :${NC} $UPTIME"
    echo -e "${YELLOW} Status :${NC} $(systemctl is-active zivpn)"
    echo -e "${MAGENTA}======================================================${NC}"
    
    # Menampilkan Akun Aktif di atas menu sesuai permintaan
    echo -e "${PURPLE} LIST AKUN AKTIF (EXPIRED):${NC}"
    if [ ! -s $DB_FILE ]; then
        echo -e "  ${RED}( Tidak ada akun aktif )${NC}"
    else
        cat $DB_FILE | tr ':' ' ' | awk -v y="$YELLOW" -v n="$NC" '{printf "  %s> %-15s [%s]%s\n", y, $1, $2, n}'
    fi
    echo -e "${MAGENTA}======================================================${NC}"
    
    echo -e "  ${ORANGE}[01] Add Account (Set Exp) ${NC}${MAGENTA}|${NC} ${PURPLE}[04] Change Domain${NC}"
    echo -e "  ${ORANGE}[02] Delete Account        ${NC}${MAGENTA}|${NC} ${PURPLE}[05] Restart Service${NC}"
    echo -e "  ${ORANGE}[03] List All Accounts     ${NC}${MAGENTA}|${NC} ${PURPLE}[06] SETUP BOT TELEGRAM${NC}"
    echo -e "  ${RED}[x] Exit${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo -ne "${CYAN} -> Masukkan pilihan Anda: ${NC}"
    read opt

    case $opt in
        01|1)
            echo -e "\n${GREEN}--- CREATE NEW ACCOUNT ---${NC}"
            read -p " Masukkan Password: " new_pass
            read -p " Masa Aktif (Hari): " durasi
            exp_date=$(date -d "$durasi days" +"%Y-%m-%d")
            sed -i "s/\"config\": \[/\"config\": [\"$new_pass\", /g" $CONFIG_FILE
            echo "$new_pass:$exp_date" >> $DB_FILE
            systemctl restart zivpn.service
            echo -e "\n${YELLOW}Sukses! Expired: $exp_date${NC}" ; sleep 2 ;;
        02|2)
            echo -e "\n${RED}--- DELETE ACCOUNT ---${NC}"
            read -p " Password yang dihapus: " del_pass
            sed -i "s/\"$del_pass\"//g" $CONFIG_FILE
            sed -i "/^$del_pass:/d" $DB_FILE
            systemctl restart zivpn.service
            echo -e "${RED}Berhasil Dihapus!${NC}" ; sleep 1 ;;
        03|3)
            echo -e "\n--- LIST DETAIL ---"
            cat $DB_FILE | tr ':' '|' ; read -p "Enter..." ;;
        04|4)
            read -p "Domain Baru: " new_dom
            openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$new_dom" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
            systemctl restart zivpn.service ;;
        05|5) systemctl restart zivpn.service ; sleep 1 ;;
        06|6) # Fungsi setup_bot di sini
            echo "Menuju Setup Bot..." ; sleep 1 ;;
        x) exit ;;
    esac
done
