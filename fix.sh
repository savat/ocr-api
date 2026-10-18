#!/bin/bash
_w=$(tput cols 2>/dev/null); [[ "$_w" =~ ^[0-9]+$ ]] || _w=40; (( _w > 60 )) && _w=60; (( _w < 20 )) && _w=20; barra="\033[38;5;177m$(printf '─%.0s' $(seq 1 $_w))\033[0m"

sudo clear

echo -e "\E[48;5;162;1;38;5;231m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "$barra"
echo -e "\033[1;38;5;213m▍\033[1;38;5;51mFix แก้ไข Error\033[0m"
echo -e "  \033[1;38;5;227m…\033[0m \033[1;38;5;231mโปรดรอสักครู่\033[0m"
echo -e "$barra"
sleep 5

sudo lsof /var/lib/dpkg/lock

sudo rm -rf /var/lib/dpkg/lock

sudo rm -rf /var/lib/dpkg/lock-frontend

sudo rm -rf /var/lib/apt/lists/lock

sudo rm -rf /var/cache/apt/archives/lock

sudo dpkg --configure -a

sudo apt-get update -y

sudo apt-get upgrade -y

sudo clear

echo -e "\E[48;5;162;1;38;5;231m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "$barra"
echo -e "\033[1;38;5;82m✔ Fix เรียบร้อยแล้ว\033[0m"
echo -e "  \033[1;38;5;227m!\033[0m \033[1;38;5;231mโปรด Reboot เครื่องอีกครั้ง\033[0m"
echo -e "$barra"

rm -rf fix.sh
