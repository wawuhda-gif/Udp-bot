#!/bin/bash
# ==========================================
# ZIVPN UDP All-in-One Installer
# Binary: v1.4.9 | Official Config
# Setup: Manager, API, Bot, Shortcuts
# ==========================================

# 1. Check Root
[[ $EUID -ne 0 ]] && echo "Error: Root required!" && exit 1

echo "Memulai Instalasi ZIVPN UDP..."

# 2. Install Dependencies
apt update && apt install -y jq curl wget openssl python3 python3-pip python3-flask python3-dotenv python3-telebot python3-requests fuser vnstat
systemctl enable vnstat && systemctl start vnstat

# 3. Setup Folder & Download Files
mkdir -p /etc/zivpn/certs
CONFIG_FILE="/etc/zivpn/config.json"
META_FILE="/etc/zivpn/accounts_meta.json"
ENV_FILE="/etc/zivpn/bot.env"

echo "Downloading Official Binary & Config..."
wget -q -O /usr/local/bin/zivpn-core "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x /usr/local/bin/zivpn-core

wget -q -O "$CONFIG_FILE" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json"

[ ! -f "$META_FILE" ] && echo '{"accounts":[]}' > "$META_FILE"
[[ ! -f "$ENV_FILE" ]] && echo -e "BOT_TOKEN=BELUM_DISET\nADMIN_ID=BELUM_DISET\nAPI_KEY=$(openssl rand -hex 16)" > "$ENV_FILE"

# 4. Create Manager Script (/usr/local/bin/zivpn-manager)
cat <<'EOF' > /usr/local/bin/zivpn-manager
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
META_FILE="/etc/zivpn/accounts_meta.json"
ENV_FILE="/etc/zivpn/bot.env"

show_config() {
    local u=$1; local p=$2
    local dom=$(jq -r '.domain' $CONFIG_FILE)
    local ip=$(curl -s ipv4.icanhazip.com)
    [[ -z "$dom" || "$dom" == "null" ]] && host=$ip || host=$dom
    echo ""
    echo "--- ZIVPN ACCOUNT INFO ---"
    echo "Host/Domain: $host"
    echo "IP Server  : $ip"
    echo "Username   : $u"
    echo "Password   : $p"
    echo "--------------------------"
    echo ""
}

get_info() {
    echo "--- VPS & BANDWIDTH INFO ---"
    vnstat -d | grep "today"
    echo "CPU Usage: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%"
    echo "RAM Usage: $(free -m | awk '/Mem:/ { print $3 "/" $2 "MB" }')"
}

add_user() {
    [ -z "$1" ] && read -p "User: " u || u=$1
    [ -z "$2" ] && read -p "Pass: " p || p=$2
    [ -z "$3" ] && read -p "Days: " d || d=$3
    exp=$(date -d "+$d days" +"%Y-%m-%d")
    jq --arg u "$u" --arg p "$p" '.auth.config += [{"username":$u, "password":$p}]' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    jq --arg u "$u" --arg e "$exp" '.accounts += [{"username":$u, "exp":$e}]' "$META_FILE" > tmp.json && mv tmp.json "$META_FILE"
    systemctl restart zivpn
    show_config "$u" "$p"
}

renew_user() {
    read -p "Username: " u
    read -p "Add Days: " d
    old_exp=$(jq -r --arg u "$u" '.accounts[] | select(.username==$u) | .exp' "$META_FILE")
    new_exp=$(date -d "$old_exp +$d days" +"%Y-%m-%d")
    jq --arg u "$u" --arg e "$new_exp" '(.accounts[] | select(.username==$u) | .exp) = $e' "$META_FILE" > tmp.json && mv tmp.json "$META_FILE"
    echo "User $u diperpanjang sampai $new_exp"
}

delete_user() {
    [ -z "$1" ] && read -p "User to delete: " u || u=$1
    jq --arg u "$u" 'del(.auth.config[] | select(.username == $u))' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    jq --arg u "$u" 'del(.accounts[] | select(.username == $u))' "$META_FILE" > tmp.json && mv tmp.json "$META_FILE"
    systemctl restart zivpn
    echo "User $u deleted."
}

change_domain() {
    read -p "Enter New Domain: " dom
    [ ! -f "$HOME/.acme.sh/acme.sh" ] && curl https://get.acme.sh | sh
    systemctl stop zivpn && fuser -k 80/tcp
    ~/.acme.sh/acme.sh --issue -d "$dom" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$dom" --key-file "/etc/zivpn/certs/private.key" --fullchain-file "/etc/zivpn/certs/fullchain.pem"
    jq --arg d "$dom" '.domain = $d' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    systemctl start zivpn
}

case $1 in
    add_silent) add_user $2 $3 $4 ;;
    del_silent) delete_user $2 ;;
    *)
        echo "ZIVPN MANAGER"
        echo "1. Add User"
        echo "2. Delete User"
        echo "3. Renew User"
        echo "4. Change Domain"
        echo "5. Info VPS"
        echo "6. Setup Bot"
        echo "7. Exit"
        read -p "Pilihan: " opt
        case $opt in
            1) add_user ;; 2) delete_user ;; 3) renew_user ;; 4) change_domain ;; 5) get_info ;; 6) 
                read -p "Token: " t; read -p "ID: " id
                sed -i "s/BOT_TOKEN=.*/BOT_TOKEN=$t/" "$ENV_FILE"
                sed -i "s/ADMIN_ID=.*/ADMIN_ID=$id/" "$ENV_FILE"
                systemctl restart zivpn-bot ;;
            *) exit ;;
        esac
    ;;
esac
EOF
chmod +x /usr/local/bin/zivpn-manager

# 5. Create Bot Script
cat <<'EOF' > /usr/local/bin/zivpn-bot.py
import telebot, os, json, subprocess
from dotenv import load_dotenv

load_dotenv('/etc/zivpn/bot.env')
token = os.getenv("BOT_TOKEN")
admin_id = os.getenv("ADMIN_ID")

if token and token != "BELUM_DISET":
    bot = telebot.TeleBot(token)

    def get_host():
        with open("/etc/zivpn/config.json", "r") as f:
            data = json.load(f)
            dom = data.get("domain", "")
        return dom if dom and dom != "null" else subprocess.getoutput("curl -s ipv4.icanhazip.com")

    @bot.message_handler(commands=['add'])
    def add(m):
        if str(m.from_user.id) != admin_id: return
        try:
            _, u, p, d = m.text.split()
            os.system(f"zivpn-manager add_silent {u} {p} {d}")
            host = get_host()
            msg = f"Account Created\n\nHost/Domain: {host}\nIP Server: {host}\nUsername: {u}\nPassword: {p}"
            bot.reply_to(m, msg)
        except: bot.reply_to(m, "Format: /add user pass days")

    @bot.message_handler(commands=['del'])
    def delete(m):
        if str(m.from_user.id) != admin_id: return
        try:
            u = m.text.split()[1]
            os.system(f"zivpn-manager del_silent {u}")
            bot.reply_to(m, f"User {u} deleted.")
        except: bot.reply_to(m, "Format: /del user")

    @bot.message_handler(commands=['info'])
    def info(m):
        if str(m.from_user.id) != admin_id: return
        bw = subprocess.getoutput("vnstat --oneline | cut -d';' -f11")
        bot.reply_to(m, f"VPS Info\nBandwidth Today: {bw}")

    bot.polling()
EOF

# 6. Systemd Services
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Core
After=network.target
[Service]
ExecStart=/usr/local/bin/zivpn-core -config /etc/zivpn/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=ZIVPN Bot
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/zivpn-bot.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 7. Shortcuts & Firewall
ln -sf /usr/local/bin/zivpn-manager /usr/local/bin/menu
ln -sf /usr/local/bin/zivpn-manager /usr/local/bin/zivpn
ufw allow 5667/udp
ufw allow 80/tcp

# 8. Start Everything
systemctl daemon-reload
systemctl enable zivpn zivpn-bot
systemctl start zivpn zivpn-bot

echo "Instalasi Selesai. Ketik 'menu' untuk memulai."
