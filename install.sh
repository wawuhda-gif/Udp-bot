#!/bin/bash

# ==========================================
# AUTO INSTALLER ZIVPN + BOT TELEGRAM + MENU PELANGI
# ==========================================

# Warna Standar Bash
BIWhite='\033[1;97m'
NC='\033[0m'

# Pastikan Root
if [[ $EUID -ne 0 ]]; then
   echo "Gunakan akses root!"
   exit 1
fi

clear
echo -e "${BIWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "     ZIVPN ALL-IN-ONE INSTALLER & BOT" | lolcat
echo -e "${BIWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Input Konfigurasi
read -p " 1. Masukkan Token Bot Telegram : " BOT_TOKEN
read -p " 2. Masukkan ID Telegram Admin  : " ADMIN_ID

# Install Dependensi & Lolcat
echo -e "\n[+] Menginstall Dependensi..."
apt update -y && apt install python3 python3-pip ruby lsb-release -y > /dev/null 2>&1
gem install lolcat > /dev/null 2>&1
pip3 install pyTelegramBotAPI > /dev/null 2>&1

# Buat Direktori Kerja
mkdir -p /etc/zivpn
if [ ! -f /etc/zivpn/config.json ]; then
    echo '{"domain": "Belum diatur", "users": []}' > /etc/zivpn/config.json
fi

# ---------------------------------------------------------
# 1. MEMBUAT MENU VPS CLI (Tampilan Pelangi)
# ---------------------------------------------------------
cat <<EOF > /usr/bin/menu
#!/bin/bash
clear
echo "──────────────────────────────────────────────" | lolcat
echo "         ZiVPN PREMIER SCRIPT MENU            " | lolcat -a -d 2
echo "──────────────────────────────────────────────" | lolcat
echo " OS      : \$(lsb_release -ds)" | lolcat
echo " Hostname: \$(hostname)" | lolcat
echo " IP VPS  : \$(curl -s ifconfig.me)" | lolcat
echo "──────────────────────────────────────────────" | lolcat
echo -e " [1] Create Akun ZiVPN" | lolcat
echo -e " [2] Hapus Akun ZiVPN" | lolcat
echo -e " [3] Atur Domain" | lolcat
echo -e " [4] Info Status VPS" | lolcat
echo -e " [5] List Users" | lolcat
echo -e " [x] Keluar" | lolcat
echo "──────────────────────────────────────────────" | lolcat
read -p " Pilih menu [1-5]: " menu_choice

case \$menu_choice in
    1) /usr/bin/zivpn create ;;
    2) /usr/bin/zivpn delete ;;
    3) read -p "Domain: " d; echo "\$d" > /etc/xray/domain; echo "Domain Diupdate!" ;;
    4) uptime -p | lolcat ;;
    5) cat /etc/zivpn/config.json | lolcat ;;
    x) exit ;;
esac
EOF
chmod +x /usr/bin/menu

# ---------------------------------------------------------
# 2. MEMBUAT FILE PYTHON BOT TELEGRAM
# ---------------------------------------------------------
cat <<EOF > /etc/zivpn/bot.py
import telebot
import subprocess
import json
import os
from telebot import types

TOKEN = "$BOT_TOKEN"
ADMIN_ID = $ADMIN_ID
BINARY_PATH = "/usr/bin/zivpn"
CONFIG_PATH = "/etc/zivpn/config.json"

bot = telebot.TeleBot(TOKEN)

def run_shell(command):
    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate()
        return stdout.strip() if stdout else stderr.strip()
    except Exception as e: return str(e)

def main_menu():
    markup = types.InlineKeyboardMarkup(row_width=2)
    markup.add(
        types.InlineKeyboardButton("➕ Create Akun", callback_data="create_acc"),
        types.InlineKeyboardButton("🗑️ Hapus Akun", callback_data="del_acc"),
        types.InlineKeyboardButton("🌐 Set Domain", callback_data="set_dom"),
        types.InlineKeyboardButton("📊 Info VPS", callback_data="vps_info"),
        types.InlineKeyboardButton("📜 List Users", callback_data="list_users")
    )
    return markup

@bot.message_handler(commands=['start', 'menu'])
@bot.message_handler(func=lambda message: message.text.lower() in ['menu', 'zivpn', 'panel', 'start'])
def send_welcome(message):
    if message.from_user.id != ADMIN_ID: return
    ip = run_shell("curl -s ifconfig.me")
    header = (
        f"<code>──────────────────────────────</code>\n"
        f"   <b>ZiVPN PREMIER SCRIPT MENU</b>\n"
        f"<code>──────────────────────────────</code>\n"
        f" <b>Hostname :</b> {run_shell('hostname')}\n"
        f" <b>IP VPS   :</b> {ip}\n"
        f" <b>Status   :</b> Online\n"
        f"<code>──────────────────────────────</code>"
    )
    bot.send_message(message.chat.id, header, parse_mode="HTML", reply_markup=main_menu())

@bot.callback_query_handler(func=lambda call: True)
def callback_query(call):
    if call.data == "create_acc":
        msg = bot.send_message(call.message.chat.id, "✨ <b>Format:</b> <code>user,pw,hari</code>", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_create)
    elif call.data == "del_acc":
        msg = bot.send_message(call.message.chat.id, "🗑️ <b>Username yang dihapus:</b>", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_delete)
    elif call.data == "set_dom":
        msg = bot.send_message(call.message.chat.id, "🌐 <b>Masukkan Domain Baru:</b>", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_domain)
    elif call.data == "vps_info":
        ram = run_shell(\"free -h | grep Mem | awk '{print \$3 \\\"/\\\" \$2}'\")
        bot.send_message(call.message.chat.id, f"📊 <b>VPS INFO</b>\n<code>RAM: {ram}\nUPTIME: {run_shell('uptime -p')}</code>", parse_mode="HTML", reply_markup=main_menu())
    elif call.data == "list_users":
        with open(CONFIG_PATH, 'r') as f:
            data = json.load(f)
        users = "\\n".join([f"• {u['user']} ({u['exp']} hari)" for u in data['users']])
        bot.send_message(call.message.chat.id, f"<b>LIST USERS:</b>\\n<code>{users if users else 'Kosong'}</code>", parse_mode="HTML", reply_markup=main_menu())

def process_create(message):
    try:
        user, pw, days = message.text.split(',')
        run_shell(f"{BINARY_PATH} create {user} {pw} {days}")
        with open(CONFIG_PATH, 'r+') as f:
            data = json.load(f)
            data['users'].append({"user": user, "pw": pw, "exp": days})
            f.seek(0); json.dump(data, f, indent=4); f.truncate()
        ip = run_shell("curl -s ifconfig.me")
        res = f"✅ <b>AKUN DIBUAT</b>\\n<code>Host: {ip}\\nUser: {user}\\nPass: {pw}\\nExp: {days} Hari</code>"
        bot.send_message(message.chat.id, res, parse_mode="HTML", reply_markup=main_menu())
    except: bot.reply_to(message, "❌ Format salah!")

def process_delete(message):
    user = message.text.strip()
    run_shell(f"{BINARY_PATH} delete {user}")
    with open(CONFIG_PATH, 'r+') as f:
        data = json.load(f)
        data['users'] = [u for u in data['users'] if u['user'] != user]
        f.seek(0); json.dump(data, f, indent=4); f.truncate()
    bot.send_message(message.chat.id, f"🗑️ User <b>{user}</b> Dihapus.", parse_mode="HTML", reply_markup=main_menu())

def process_domain(message):
    dom = message.text.strip()
    run_shell(f"echo '{dom}' > /etc/xray/domain")
    with open(CONFIG_PATH, 'r+') as f:
        data = json.load(f)
        data['domain'] = dom
        f.seek(0); json.dump(data, f, indent=4); f.truncate()
    bot.send_message(message.chat.id, f"✅ Domain diatur: <code>{dom}</code>", parse_mode="HTML", reply_markup=main_menu())

bot.polling(none_stop=True)
EOF

# ---------------------------------------------------------
# 3. MEMBUAT SYSTEMD SERVICE (Bot Auto-Start)
# ---------------------------------------------------------
cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=ZiVPN Telegram Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/zivpn/bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Jalankan Service
systemctl daemon-reload
systemctl enable zivpn-bot
systemctl start zivpn-bot

echo -e "\n${BIWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   INSTALLASI SELESAI!" | lolcat
echo -e "   - Ketik 'menu' di VPS untuk Menu Pelangi"
echo -e "   - Ketik 'menu' di Bot Telegram untuk Panel"
echo -e "${BIWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
