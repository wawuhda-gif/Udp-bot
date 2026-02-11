#!/bin/bash

# --- Kode Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# --- Variabel Path ---
CONFIG_FILE="/etc/zivpn/config.json"
EXP_FILE="/etc/zivpn/akun.exp"
BIN_PATH="/usr/local/bin/zivpn"
MENU_PATH="/usr/local/bin/zivpn"
BOT_SCRIPT="/etc/zivpn/zivpn-bot.sh"

# --- Fungsi Efek Pelangi ---
rainbow_line() {
    echo -e "${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━${RED}━${YELLOW}━${GREEN}━${CYAN}━${BLUE}━${PURPLE}━"
}

get_ip() { curl -s https://ifconfig.me; }

check_expired() {
    touch $EXP_FILE
    today=$(date +%Y-%m-%d)
    while read -r line; do
        acc_name=$(echo $line | cut -d '|' -f 1)
        exp_date=$(echo $line | cut -d '|' -f 2)
        if [[ "$today" > "$exp_date" ]]; then
            sed -i "s/\"$acc_name\"//g" $CONFIG_FILE
            sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
            sed -i "/$acc_name/d" $EXP_FILE
            systemctl restart zivpn.service
        fi
    done < $EXP_FILE
}

# --- Fungsi Instalasi ---
install_zivpn() {
    clear
    rainbow_line
    echo -e "      ${YELLOW}MEMULAI INSTALASI ${CYAN}ZIVPN UDP${NC}      "
    rainbow_line
    echo -e "${GREEN}Mengupdate Server & Dependensi...${NC}"
    sudo apt-get update && sudo apt-get install jq curl lsb-release -y 1> /dev/null
    
    echo -e "${GREEN}Mendownload UDP Service...${NC}"
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN_PATH 1> /dev/null 2>&1
    chmod +x $BIN_PATH
    mkdir -p /etc/zivpn
    touch $EXP_FILE
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O $CONFIG_FILE 1> /dev/null 2>&1

    echo -e "${GREEN}Membuat Sertifikat SSL...${NC}"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2> /dev/null
    
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
    cp "$0" "$MENU_PATH"
    chmod +x "$MENU_PATH"
    echo -e "${YELLOW}INSTALASI SELESAI!${NC}"
    sleep 2
}

if [ ! -f "$BIN_PATH" ]; then install_zivpn; fi

# --- Loop Menu ---
while true; do
    check_expired
    clear
    IP_VPS=$(get_ip)
    UPTIME=$(uptime -p | cut -d " " -f 2-)
    RAM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    OS=$(lsb_release -ds)
    STATUS=$(systemctl is-active zivpn)
    BOT_STAT=$(systemctl is-active zivpn-bot 2>/dev/null || echo "off")

    rainbow_line
    echo -e "   ${YELLOW}Z I V P N   ${PURPLE}U D P   ${CYAN}D A S H B O A R D${NC}"
    rainbow_line
    echo -e " ${WHITE}OS      : ${CYAN}$OS${NC}"
    echo -e " ${WHITE}IP      : ${CYAN}$IP_VPS${NC}"
    echo -e " ${WHITE}RAM     : ${CYAN}$RAM${NC}"
    echo -e " ${WHITE}Uptime  : ${CYAN}$UPTIME${NC}"
    echo -e " ${WHITE}Status  : ${GREEN}$STATUS${NC} | ${WHITE}Bot: ${YELLOW}$BOT_STAT${NC}"
    rainbow_line
    echo -e "  ${PURPLE}DAFTAR AKUN AKTIF & EXPIRED:${NC}"
    printf "  ${BLUE}%-18s | %-12s${NC}\n" "PASSWORD" "EXPIRED"
    echo -e "  ------------------------------------"
    while read -r line; do
        acc=$(echo $line | cut -d '|' -f 1)
        exp=$(echo $line | cut -d '|' -f 2)
        printf "  ${WHITE}%-18s${NC} | ${YELLOW}%-12s${NC}\n" "$acc" "$exp"
    done < $EXP_FILE
    rainbow_line
    echo -e "  ${GREEN}1)${NC} ${WHITE}Create Akun Baru     ${GREEN}4)${NC} ${WHITE}Change Domain${NC}"
    echo -e "  ${GREEN}2)${NC} ${WHITE}Hapus Akun           ${GREEN}5)${NC} ${WHITE}Restart Service${NC}"
    echo -e "  ${GREEN}3)${NC} ${WHITE}List Semua Akun      ${GREEN}6)${NC} ${CYAN}SETUP BOT TG${NC}"
    echo -e "  ${RED}x)${NC} ${RED}Exit Dashboard${NC}"
    rainbow_line
    echo -ne " ${YELLOW}Pilih Menu >> ${NC}"; read opt

    case $opt in
        1)
            echo -e "\n${CYAN}--- TAMBAH AKUN BARU ---${NC}"
            read -p " Password: " new_pass
            read -p " Durasi (Hari): " masa_aktif
            if [[ -n "$new_pass" ]]; then
                exp_date=$(date -d "+$masa_aktif days" +%Y-%m-%d)
                sed -i "s/\"config\": \[/\"config\": [\"$new_pass\", /g" $CONFIG_FILE
                echo "$new_pass|$exp_date" >> $EXP_FILE
                systemctl restart zivpn.service
                echo -e "${GREEN}Sukses! Expired pada: $exp_date${NC}"
                sleep 2
            fi ;;
        2)
            echo -e "\n${RED}--- HAPUS AKUN ---${NC}"
            read -p " Password yang dihapus: " del_pass
            sed -i "s/\"$del_pass\"//g" $CONFIG_FILE
            sed -i 's/\[,/\[/g; s/,,/,/g; s/, ]/]/g; s/,]/]/g' $CONFIG_FILE
            sed -i "/$del_pass/d" $EXP_FILE
            systemctl restart zivpn.service
            echo -e "${YELLOW}Akun $del_pass telah dihapus!${NC}" ; sleep 2 ;;
        3)
            echo -e "\n${PURPLE}--- DETAIL SEMUA AKUN ---${NC}"
            cat $EXP_FILE | column -t -s "|"
            read -p "Tekan Enter..." ;;
        4)
            read -p " Domain Baru: " new_dom
            openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Zivpn/CN=$new_dom" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
            systemctl restart zivpn.service ; echo -e "${GREEN}Domain Updated!${NC}" ; sleep 2 ;;
        5) systemctl restart zivpn.service ; echo -e "${GREEN}Restarted!${NC}" ; sleep 2 ;;
        6) setup_bot ;;
        x) exit ;;
    esac
done
