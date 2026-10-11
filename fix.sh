#!/bin/bash

sudo clear

echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "\033[0;35m────────────────────────────────────\033[0m"
echo -e "\033[1;35m▍\033[1;36mFix แก้ไข Error\033[0m"
echo -e "  \033[1;33m…\033[0m \033[1;37mโปรดรอสักครู่\033[0m"
echo -e "\033[0;35m────────────────────────────────────\033[0m"
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

echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "\033[0;35m────────────────────────────────────\033[0m"
echo -e "\033[1;32m✔ Fix เรียบร้อยแล้ว\033[0m"
echo -e "  \033[1;33m!\033[0m \033[1;37mโปรด Reboot เครื่องอีกครั้ง\033[0m"
echo -e "\033[0;35m────────────────────────────────────\033[0m"

rm -rf fix.sh
