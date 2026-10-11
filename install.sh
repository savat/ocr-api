#!/bin/bash
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
	echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
	echo -e "\E[44;1;37m             ⇱ TH-VPN PREMIUM SCRIPT ⇲              \E[0m"
	echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
	echo -e "\033[0m"
	echo -e "\033[0;37mเวอร์ชัน OS ของคุณเป็นเวอร์ชันที่ยังไม่รองรับ    "
	echo -e "\033[0;37mสำหรับเวอร์ชันที่รองรับได้ จะมีดังนี้..."
	echo -e "\033[0m"
	echo -e "\033[0;37mUbuntu 18.04 ขึ้นไป    "
	echo -e "\033[0;37mDebian 9 ขึ้นไป    "
	echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
	echo -e "\033[0m"
	exit
fi
	
clear
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\E[44;1;37m             ⇱ TH-VPN PREMIUM SCRIPT ⇲              \E[0m"
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
read -p "Key : " passwds
echo -e "\033[0;37m✅ กำลังตรวจสอบ Key ในระบบสักครู่....        "
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
sleep 6
wget -q -O /usr/bin/key-thvpn https://raw.githubusercontent.com/savat/ocr-api/main/key.txt
if ! grep -w -q $passwds /usr/bin/key-thvpn; then
clear
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\E[44;1;37m             ⇱ TH-VPN PREMIUM SCRIPT ⇲              \E[0m"
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[0;37mKey : 🚨ของคุณไม่ถูกต้อง หรือ หมดอายุการใช้งานแล้ว        "
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"

HOSTNAME=$(hostname)
DATE=`date '+%d-%m-%Y %H:%M:%Sน.'`
IP01=$(wget -qO- ipv4.icanhazip.com)
CY01=$(wget -qO- ipinfo.io/country)

curl --silent  POST https://notify-api.line.me/api/notify \
  -H 'authorization: Bearer AQtZv5GECNeLogNpp3EnpI4erhBLJWqj4lxsCeUcJm8' \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d message="ติดตั้งสคริปต์ 🔑(พรีเมี่ยม)🔑
🖥️ ติดตั้งด้วยชื่อ : $USER
💽 โฮสต์เซิร์ฟเวอร์ : $HOSTNAME
🔐 สคริปต์ถูกรันโดย :  http://$IP01:81 ($CY01)
📆 วันที่ : $DATE
🔑 คีย์ที่ติดตั้ง : $passwds
🚨เตือนคีย์ไม่ถูกต้อง !!" > /dev/null

rm -rf /usr/bin/key-thvpn
rm -rf install.sh*
exit
	
fi
	
	
if [[ "$OS" == "ubuntu" ]]; then
cat <<-EOF >/etc/apt/sources.list
	deb http://archive.ubuntu.th-vpn.in.net/ubuntu/ $OS_CODENAME main restricted universe multiverse
	deb http://archive.ubuntu.th-vpn.in.net/ubuntu/ $OS_CODENAME-updates main restricted universe multiverse
	deb http://archive.ubuntu.th-vpn.in.net/ubuntu/ $OS_CODENAME-backports main restricted universe multiverse
	deb http://archive.ubuntu.th-vpn.in.net/ubuntu/ $OS_CODENAME-security main restricted universe multiverse
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
	deb http://archive.debian.th-vpn.in.net/debian $OS_CODENAME main contrib non-free
	deb http://archive.debian.th-vpn.in.net/debian $OS_CODENAME-updates main contrib non-free
	deb http://security.debian.org/debian-security $OS_CODENAME-security main contrib non-free
EOF
	else
cat <<-EOF >/etc/apt/sources.list
	deb http://archive.debian.th-vpn.in.net/debian $OS_CODENAME main contrib non-free non-free-firmware
	deb http://archive.debian.th-vpn.in.net/debian $OS_CODENAME-updates main contrib non-free non-free-firmware
	deb http://security.debian.org/debian-security $OS_CODENAME-security main contrib non-free non-free-firmware
EOF
	fi
fi

HOSTNAME=$(hostname)
DATE=`date '+%d-%m-%Y %H:%M:%Sน.'`
IP01=$(wget -qO- ipv4.icanhazip.com)
CY01=$(wget -qO- ipinfo.io/country)

curl --silent  POST https://notify-api.line.me/api/notify \
  -H 'authorization: Bearer AQtZv5GECNeLogNpp3EnpI4erhBLJWqj4lxsCeUcJm8' \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d message="ติดตั้งสคริปต์ 🔑(พรีเมี่ยม)🔑
🖥️ ติดตั้งด้วยชื่อ : $USER
💽 โฮสต์เซิร์ฟเวอร์ : $HOSTNAME
🔐 สคริปต์ถูกรันโดย :  http://$IP01:81 ($CY01)
📆 วันที่ : $DATE
🔑 คีย์ที่ติดตั้ง : $passwds" > /dev/null

rm -rf install.sh; rm -rf thvpn.sh; apt-get update -y; apt-get upgrade -y; apt-get install ca-certificates -y; apt-get install sudo -y; apt-get install ufw -y; wget -q --no-check-certificate https://raw.githubusercontent.com/savat/ocr-api/main/thvpn.sh && chmod +x  thvpn.sh && ./thvpn.sh
exit


