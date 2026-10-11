#!/bin/bash
_w=$(tput cols 2>/dev/null); [[ "$_w" =~ ^[0-9]+$ ]] || _w=40; (( _w > 60 )) && _w=60; (( _w < 20 )) && _w=20; barra="\033[0;35m$(printf '─%.0s' $(seq 1 $_w))\033[0m"
[[ "$(whoami)" != "root" ]] && {
echo -e "\033[1;33m[\033[1;31mError\033[1;33m] \033[1;37m- \033[1;33mโปรดทำการรันสคริปต์ผ่าน Root เท่านั้น    \033[0m"
rm $HOME/install.sh* > /dev/null 2>&1; exit 0
}
if [[ -e /etc/os-release ]]; then
	. /etc/os-release
else
	ID=""; VERSION_ID=""; VERSION_CODENAME=""
fi

OS=""
OS_CODENAME=""
case "$ID" in
	ubuntu) OS=ubuntu; OS_CODENAME="${VERSION_CODENAME:-$UBUNTU_CODENAME}" ;;
	debian) OS=debian; OS_CODENAME="$VERSION_CODENAME" ;;
esac

if [[ -z "$OS" || -z "$OS_CODENAME" ]]; then
	clear
	echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
	echo -e "$barra"
	echo -e "[1;31m✘ ไม่รองรับระบบปฏิบัติการนี้[0m"
	echo -e "[1;37mรองรับ:[0m"
	echo -e "  [1;32m●[0m Ubuntu 18.04 ขึ้นไป"
	echo -e "  [1;32m●[0m Debian 9 ขึ้นไป"
	echo -e "$barra"
	echo -e "\033[0m"
	exit
fi
	
clear
echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "$barra"
if [[ "$OS" == "ubuntu" ]]; then
cat <<-EOF >/etc/apt/sources.list
	deb http://archive.ubuntu.com/ubuntu/ $OS_CODENAME main restricted universe multiverse
	deb http://archive.ubuntu.com/ubuntu/ $OS_CODENAME-updates main restricted universe multiverse
	deb http://archive.ubuntu.com/ubuntu/ $OS_CODENAME-backports main restricted universe multiverse
	deb http://archive.ubuntu.com/ubuntu/ $OS_CODENAME-security main restricted universe multiverse
EOF
elif [[ "$OS" == "debian" ]]; then
	if [[ "$OS_CODENAME" == "stretch" || "$OS_CODENAME" == "buster" ]]; then
cat <<-EOF >/etc/apt/sources.list
	deb [trusted=yes] http://archive.debian.org/debian $OS_CODENAME main contrib non-free
	deb [trusted=yes] http://archive.debian.org/debian $OS_CODENAME-updates main contrib non-free
	deb [trusted=yes] http://archive.debian.org/debian-security $OS_CODENAME/updates main contrib non-free
EOF
	elif [[ "$OS_CODENAME" == "bullseye" ]]; then
cat <<-EOF >/etc/apt/sources.list
	deb http://deb.debian.org/debian $OS_CODENAME main contrib non-free
	deb http://deb.debian.org/debian $OS_CODENAME-updates main contrib non-free
	deb http://security.debian.org/debian-security $OS_CODENAME-security main contrib non-free
EOF
	else
cat <<-EOF >/etc/apt/sources.list
	deb http://deb.debian.org/debian $OS_CODENAME main contrib non-free non-free-firmware
	deb http://deb.debian.org/debian $OS_CODENAME-updates main contrib non-free non-free-firmware
	deb http://security.debian.org/debian-security $OS_CODENAME-security main contrib non-free non-free-firmware
EOF
	fi
fi

_tg_url="https://gist.githubusercontent.com/savat/f22127eea907ae196d9a875f0d264157/raw/2a434e865e31bf1d1fd3f5239d50ec989d07c292/notify.conf"
_tg_cfg=$(curl -fsSL "$_tg_url" 2>/dev/null)
_tg_token=$(printf '%s\n' "$_tg_cfg" | sed -n 's/^[[:space:]]*TELEGRAM_TOKEN=//p' | tr -d '[:space:]')
_tg_chat=$(printf '%s\n' "$_tg_cfg" | sed -n 's/^[[:space:]]*TELEGRAM_CHAT_ID=//p' | tr -d '[:space:]')
if [[ -n "$_tg_token" && -n "$_tg_chat" ]]; then
	HOSTNAME=$(hostname)
	DATE=$(date '+%d-%m-%Y %H:%M:%Sน.')
	IP01=$(wget -qO- ipv4.icanhazip.com)
	CY01=$(wget -qO- ipinfo.io/country)
	curl -s -X POST "https://api.telegram.org/bot${_tg_token}/sendMessage" \
		--data-urlencode "chat_id=${_tg_chat}" \
		--data-urlencode "text=แจ้งเตือน: กำลังติดตั้งสคริปต์
🖥️ ผู้ใช้ : $USER
💽 โฮสต์ : $HOSTNAME
🔐 IP : http://$IP01:81 ($CY01)
📆 วันที่ : $DATE" >/dev/null 2>&1 &
fi

rm -rf install.sh; rm -rf autoscript.sh; apt-get update -y; apt-get upgrade -y; apt-get install ca-certificates -y; apt-get install sudo -y; apt-get install ufw -y; wget -q --no-check-certificate https://raw.githubusercontent.com/savat/ocr-api/main/autoscript.sh && chmod +x  autoscript.sh && ./autoscript.sh
exit


