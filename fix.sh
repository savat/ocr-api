#!/bin/bash

sudo clear

echo -e "\033[0;33m======================= \033[0m"
echo -e "\033[0;37m สคริปต์ เขียนโดย หลวงพี่  \033[0m  "
echo -e "\033[0;33m======================= \033[0m"
echo ""
echo -e "\033[0;33m======================= \033[0m"
echo -e "\033[0;37m #Fix แก้ไข Error!  \033[0m  "
echo -e "\033[0;33m======================= \033[0m"
echo ""
echo -e "\033[0;33m======================= \033[0m"
echo -e "\033[0;37m #โปรดรอสักครู่ (!!)  \033[0m  "
echo -e "\033[0;33m======================= \033[0m"
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

echo -e "\033[0;33m=========================== \033[0m"
echo -e "\033[0;37m #Fix เรียบร้อยแล้ว (หลวงพี่)   \033[0m  "
echo -e "\033[0;33m=========================== \033[0m"
echo ""
echo -e "\033[0;33m=========================== \033[0m"
echo -e "\033[0;37m #โปรดทำการ Reboot ด้วย ?   \033[0m  "
echo -e "\033[0;33m=========================== \033[0m"
echo ""

rm -rf fix.sh
