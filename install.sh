#!/bin/bash
# ==========================================
# ZIVPN UDP CUSTOM SYSTEM - GITHUB VERSION
# ==========================================

# 1. WARNA & VARIABEL
Cyan='\033[0;36m'
Yellow='\033[0;33m'
Green='\033[0;32m'
White='\033[1;97m'
NC='\033[0m'

# 2. INSTALL DEPENDENCIES
apt update && apt install -y python3-pip vnstat screen curl sed wget cron unzip
pip3 install python-telegram-bot --break-system-packages --quiet

# 3. DOWNLOAD & SETUP BINARY ZIVPN
mkdir -p /etc/zivpn
wget -q -O /usr/bin/zivpn-server "https://github.com/fauzanihanipah/ziv-udp/releases/download/udp-zivpn/udp-zivpn-linux-amd64"
chmod +x /usr/bin/zivpn-server

# Buat Service Systemd
cat > /etc/systemd/system/zivpn.service << END
[Unit]
Description=Zivpn UDP Custom Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/zivpn-server server -exclude 22,80,443
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END

systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

# 4. DATABASE & AUTH SETUP
touch /etc/zivpn/udp-users.txt
touch /etc/zivpn/.bot_cred
[ ! -f /etc/xray/domain ] && mkdir -p /etc/xray && echo "$(curl -s ipv4.icanhazip.com)" > /etc/xray/domain

# 5. SCRIPT MANAJEMEN USER (zivpn-add & del)
cat > /usr/bin/zivpn-add << END
#!/bin/bash
USER=\$1
DAYS=\${2:-30}
PASS=\$(shuf -i 1000-9999 -n 1)
DOMAIN=\$(cat /etc/xray/domain)
IP=\$(hostname -I | awk '{print \$1}')
EXP_DATE=\$(date -d "\$DAYS days" +"%Y-%m-%d")

echo "\$USER:\$PASS:\$EXP_DATE" >> /etc/zivpn/udp-users.txt
systemctl restart zivpn > /dev/null 2>&1

echo "━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 UDP ZIVPN AKTIF"
echo "━━━━━━━━━━━━━━━━━━━━"
echo "Host     : \$DOMAIN"
echo "IP VPS   : \$IP"
echo "Password : \$PASS"
echo "Expired  : \$EXP_DATE (\$DAYS Hari)"
echo "━━━━━━━━━━━━━━━━━━━━"
echo "Config   : \$IP:7300@\$USER:\$PASS"
END

cat > /usr/bin/zivpn-del << END
#!/bin/bash
USER=\$1
PASS_LAMA=\$(grep "^\$USER:" /etc/zivpn/udp-users.txt | cut -d':' -f2)
sed -i "/^\$USER:/d" /etc/zivpn/udp-users.txt
systemctl restart zivpn > /dev/null 2>&1
echo "User \$USER Berhasil Dihapus."
END

# Script Auto-XP
cat > /usr/bin/zivpn-xp << END
#!/bin/bash
TODAY=\$(date +"%Y-%m-%d")
while IFS=':' read -r user pass exp; do
    if [[ "\$exp" < "\$TODAY" ]]; then
        sed -i "/^\$user:\$pass:\$exp/d" /etc/zivpn/udp-users.txt
    fi
done < /etc/zivpn/udp-users.txt
systemctl restart zivpn > /dev/null 2>&1
END

chmod +x /usr/bin/zivpn-add /usr/bin/zivpn-del /usr/bin/zivpn-xp
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/zivpn-xp") | crontab -

# 6. BOT TELEGRAM PYTHON
cat > /root/bot_zivpn.py << END
import logging, subprocess, os
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

def get_cred():
    creds = {}
    with open('/etc/zivpn/.bot_cred', 'r') as f:
        for line in f:
            if '=' in line: k, v = line.strip().split('='); creds[k] = v
    return creds

config = get_cred()
TOKEN = config['TOKEN']
ADMIN_ID = int(config['ADMIN_ID'])

async def buat(update, context):
    if update.effective_user.id != ADMIN_ID: return
    if not context.args: return
    user, days = context.args[0], (context.args[1] if len(context.args) > 1 else "30")
    out = subprocess.check_output(f"zivpn-add {user} {days}", shell=True).decode("utf-8")
    await update.message.reply_text(f"✅ **AKUN UDP DIBUAT**\n\n{out}", parse_mode='Markdown')

async def hapus(update, context):
    if update.effective_user.id != ADMIN_ID: return
    if not context.args: return
    out = subprocess.check_output(f"zivpn-del {context.args[0]}", shell=True).decode("utf-8")
    await update.message.reply_text(f"🗑️ **HAPUS BERHASIL**\n{out}")

def main():
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("buat", buat))
    app.add_handler(CommandHandler("hapus", hapus))
    app.run_polling()

if __name__ == '__main__': main()
END

# 7. MENU VPS (Ketik 'menu' di terminal)
cat > /usr/bin/menu << END
#!/bin/bash
clear
echo -e "\${Cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo -e "\${White}         ZIVPN UDP CUSTOM PANEL MENU\${NC}"
echo -e "\${Cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
echo -e " [\${Yellow}1\${NC}] Buat Akun Zivpn Baru"
echo -e " [\${Yellow}2\${NC}] Hapus Akun Zivpn"
echo -e " [\${Yellow}3\${NC}] List Akun & Expired"
echo -e " [\${Yellow}4\${NC}] Setup Token Bot & ID"
echo -e " [\${Yellow}5\${NC}] Start/Restart Bot"
echo -e " [\${Yellow}0\${NC}] Keluar"
echo -e "\${Cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
read -p " Pilih: " opt
case \$opt in
    1) read -p "User: " u; read -p "Hari: " d; zivpn-add \$u \$d; read -p "Enter..."; menu ;;
    2) read -p "User: " u; zivpn-del \$u; menu ;;
    3) clear; echo "User | Password | Exp"; cat /etc/zivpn/udp-users.txt; read -p "Enter..."; menu ;;
    4) read -p "Token: " tk; read -p "ID: " id; echo "TOKEN=\$tk" > /etc/zivpn/.bot_cred; echo "ADMIN_ID=\$id" >> /etc/zivpn/.bot_cred; menu ;;
    5) screen -XS bot_zivpn quit > /dev/null 2>&1; screen -dmS bot_zivpn python3 /root/bot_zivpn.py; echo "Bot OK"; sleep 1; menu ;;
    0) exit ;;
    *) menu ;;
esac
END
chmod +x /usr/bin/menu

clear
echo -e "${Green}Selesai! Ketik 'menu' untuk setting Bot.${NC}"
