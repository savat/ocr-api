#!/bin/bash
clear
[[ "$(whoami)" != "root" ]] && {
echo -e "\033[1;33m[\033[1;31mError\033[1;33m] \033[1;37m- \033[1;33mโปรดทำการรันสคริปต์ผ่าน Root เท่านั้น    \033[0m"
rm $HOME/autoscript.sh* > /dev/null 2>&1; exit 0
}
_lnk=$(echo 't1:e#n.5s0ul&p4hs$s.0729t9p$&8i&&9r7827c032:3s'| sed -e 's/[^a-z.]//ig'| rev)
_Ink=$(echo '/3×u3#s87r/l32o4×c1a×l1/83×l24×i0b×'|sed -e 's/[^a-z/]//ig')
_1nk=$(echo '/3×u3#s×87r/83×l2×4×i0b×'|sed -e 's/[^a-z/]//ig')

cd $HOME
fun_bar () {
comando[0]="$1"
comando[1]="$2"
 (
[[ -e $HOME/fim ]] && rm $HOME/fim
${comando[0]} -y > /dev/null 2>&1
${comando[1]} -y > /dev/null 2>&1
touch $HOME/fim
 ) > /dev/null 2>&1 &
 tput civis
echo -ne "  \033[1;33mโปรดรอสักครู่ \033[1;37m- \033[1;33m["
while true; do
   for((i=0; i<18; i++)); do
   echo -ne "\033[1;31m#"
   sleep 0.1s
   done
   [[ -e $HOME/fim ]] && rm $HOME/fim && break
   echo -e "\033[1;33m]"
   sleep 1s
   tput cuu1
   tput dl1
   echo -ne "  \033[1;33mโปรดรอสักครู่ \033[1;37m- \033[1;33m["
done
echo -e "\033[1;33m]\033[1;37m -\033[1;32m OK !\033[1;37m"
tput cnorm
}

function verif_key () {
krm=$(echo '5:q-3gs2.o7%8:1'|rev)
chmod +x $_Ink/list > /dev/null 2>&1
[[ ! -e "$_Ink/list" ]] && {
  echo -e "\n\033[1;31mสำเร็จ!\033[0m"
  rm -rf $HOME/autoscript.sh* > /dev/null 2>&1
  sleep 2
  clear; exit 1
}
}

function verif_db () {
[[ -f "$HOME/username.db" ]] && {
	clear
    echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
	echo -e "\E[44;1;37m             ⇱ ออโต้สคริป โดย หลวงพี่ ⇲              \E[0m"
	echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
    echo -e "\033[0m"
	echo -e "\033[1;31m                 \033[1;33m• \033[1;31mคำเตือน !! \033[1;33m•\033[0m"
	echo -e "\033[0m"
    echo -e "\033[1;32m ฐานข้อมูลผู้ใช้งาน \033[1;33m(username.db) \033[1;32mคือ   \033[0m" 
    echo -e "\033[1;32m มีอยู่ในระบบแล้ว! คุณต้องการที่จะใช้ข้อมูลปัจจุบันนี้ ใช่หรือไม่?   \033[0m" 
    echo -e "\033[1;32m บัญชีผู้ใช้งานปัจจุบัน? หรือคุณต้องการ สร้างฐานข้อมูลใหม่?   \033[0m" 
    echo -e "\033[0m"
    echo -e "\033[1;33m [1] ใช้ฐานข้อมูลเดิม?   \033[0m" 
    echo -e "\033[1;33m [2] สร้างฐานข้อมูลใหม่?   \033[0m" 
	echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
	echo -e "\033[0m"
	tput setaf 2 ; tput bold ; read -p "Select ?: " -e -i 1 optiondb ; tput sgr0
} || {
	awk -F : '$3 >= 500 { print $1 " 1" }' /etc/passwd | grep -v '^nobody' > $HOME/username.db
}
[[ "$optiondb" = '2' ]] && awk -F : '$3 >= 500 { print $1 " 1" }' /etc/passwd | grep -v '^nobody' > $HOME/username.db
}

fun_attlist () {
    apt-get update -y
	[[ ! -d /usr/share/.autoscript ]] && mkdir /usr/share/.autoscript
	echo "autoscript: $(date)" > /usr/share/.autoscript/.autoscript
}

inst_pct () {
_pacotes=("bc" "screen" "nano" "unzip" "lsof" "net-tools" "dos2unix" "nload" "jq" "curl" "figlet" "python3" "python3-pip")
for _prog in ${_pacotes[@]}; do
    apt install $_prog -y
done
pip3 install speedtest-cli > /dev/null 2>&1 || pip3 install --break-system-packages speedtest-cli > /dev/null 2>&1 || apt install speedtest-cli -y > /dev/null 2>&1
}
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\E[44;1;37m             ⇱ ออโต้สคริป โดย หลวงพี่ ⇲              \E[0m"
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[0m"
echo -e "\033[1;31m           คำเตือน! \033[1;33mสคริปต์ SSH OPENVPN นี้ !  \033[0m"
echo -e "\033[0m"
echo -e "\033[1;31m            • \033[1;33mการติดตั้งสคริปต์? เป็นเครื่องมือ  \033[0m" 
echo -e "\033[1;33m        สำหรับเครือข่ายระบบและการจัดการผู้ใช้งาน  \033[0m"
echo -e "\033[0m"
echo -e "\033[1;32m         • เคล็ดลับ! \033[1;33mปรับใช้ธีมมืดในเทอร์มินัลของคุณ  \033[0m"
echo -e "\033[1;33m      เพื่อประสบการณ์ที่ดีขึ้นและการมองเห็นของสิ่งเดียวกัน!  \033[0m"
echo -e "\033[0m"
echo -e "\033[1;31m≠×≠×≠×≠×≠×≠×≠[\033[1;33m • \033[1;32mโดย ปัณณวิชญ์ นารีเดช\033[1;33m • \033[1;31m]×≠×≠×≠×≠×≠×≠×≠\033[0m"
echo -e "\033[0m"
read -p "$(echo -e "\033[1;36mInstall Script \033[1;33m[Y/N]:\033[1;37m ")" -e -i y resp
[[ $resp = @(n|N) ]] && rm $HOME/autoscript.sh* && exit 0
_lnk2=$(echo "$key"|awk -F : '{print $2}')
_lnk1=$(echo "$key"|awk -F : '{print $1}')
rm $_Ink/list > /dev/null 2>&1; wget -P $_Ink https://raw.githubusercontent.com/savat/ocr-api/main/Install/list > /dev/null 2>&1; verif_key
sleep 1s
verif_db
clear
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\E[44;1;37m             ⇱ ออโต้สคริป โดย หลวงพี่ ⇲              \E[0m"
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;33m             [\033[1;31m!\033[1;33m] \033[1;32mกำลังอัปเดตระบบ \033[1;33m[\033[1;31m!\033[1;33m]\033[0m"
fun_bar 'fun_attlist'
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;33m            [\033[1;31m!\033[1;33m] \033[1;32mกำลังติดตั้งแพ็คเกจ \033[1;33m[\033[1;31m!\033[1;33m] \033[0m"
fun_bar 'inst_pct'
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
[[ -f "/usr/sbin/ufw" ]] && ufw allow 443/tcp ; ufw allow 80/tcp ; ufw allow 3128/tcp ; ufw allow 8799/tcp ; ufw allow 8080/tcp
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;33m           [\033[1;31m!\033[1;33m] \033[1;32mตรวจสอบความถูกต้อง \033[1;33m[\033[1;31m!\033[1;33m] \033[0m"
fun_bar "$_Ink/list $_lnk $_Ink $_1nk $key"
cd $HOME
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;33m             • \033[1;32mการติดตั้งเสร็จสมบูรณ์ \033[1;33m• \033[0m"
echo -e "\033[1;33m เปิดเมนูคำสั่ง: \033[1;32mmenu   \033[0m"
echo -e "\033[1;33m มีปัญหาอื่นๆ\033[1;31m(ติดต่อ\033[1;31m)\033[1;33m: \033[1;32mปัณณวิชญ์ นารีเดช   \033[0m"
echo -e "\033[1;31m════════════════════════════════════════════════════\033[0m"
rm $HOME/autoscript.sh* && cat /dev/null > ~/.bash_history && history -c