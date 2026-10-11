#!/bin/bash
_w=$(tput cols 2>/dev/null); [[ "$_w" =~ ^[0-9]+$ ]] || _w=40; (( _w > 60 )) && _w=60; (( _w < 20 )) && _w=20; barra="\033[0;35m$(printf '─%.0s' $(seq 1 $_w))\033[0m"
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
  local log_file status_file pid rc step frame=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧')
  log_file=$(mktemp); status_file=$(mktemp)
  _run_install_step() {
    local spec; local -a argv
    for spec in "$@"; do
      [[ -z "$spec" ]] && continue
      if declare -F "$spec" >/dev/null; then
        "$spec" || return $?
      else
        read -r -a argv <<< "$spec"
        "${argv[@]}" || return $?
      fi
    done
  }
  case "${1:-}" in
    fun_attlist) step="กำลังอัปเดตรายการแพ็กเกจ" ;;
    inst_pct) step="กำลังติดตั้งแพ็กเกจที่จำเป็น" ;;
    *) step="กำลังติดตั้งและตั้งค่าระบบ" ;;
  esac
  ( _run_install_step "$@" >"$log_file" 2>&1; echo $? >"$status_file" ) & pid=$!
  tput civis 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  \033[1;35m%s\033[0m \033[1;37m%s\033[0m' "${frames[frame++ % ${#frames[@]}]}" "$step"
    sleep 0.12
  done
  wait "$pid"; rc=$(cat "$status_file" 2>/dev/null || echo 1)
  printf '\r\033[K'; tput cnorm 2>/dev/null || true
  if [[ "$rc" == 0 ]]; then
    echo -e "  \033[1;32m✔\033[0m \033[1;37m$step\033[0m"
  else
    echo -e "  \033[1;31m✘\033[0m \033[1;37m$step\033[0m \033[1;31m(ไม่สำเร็จ)\033[0m"
    tail -n 8 "$log_file" 2>/dev/null
  fi
  rm -f "$log_file" "$status_file"
  return "$rc"
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
	echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
	echo -e "$barra"
	echo -e "\033[1;33m⚠ พบฐานข้อมูลผู้ใช้เดิม\033[0m \033[0;90m(username.db)\033[0m"
	echo -e "\033[1;37mต้องการใช้ข้อมูลเดิมหรือสร้างใหม่?\033[0m"
	echo -e "$barra"
	echo -e "\E[30;46m 1 \E[0m \033[1;37mใช้ฐานข้อมูลเดิม\033[0m"
	echo -e "\E[30;46m 2 \E[0m \033[1;37mสร้างฐานข้อมูลใหม่\033[0m"
	echo -e "$barra"
		read -p "$(echo -e "\033[1;35m❯ \033[1;37mเลือก \033[0;90m[1/2]\033[1;35m › \033[1;37m")" -e -i 1 optiondb
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
_w=$(tput cols 2>/dev/null); [[ "$_w" =~ ^[0-9]+$ ]] || _w=40; (( _w > 60 )) && _w=60
UI_BAR=$(printf '─%.0s' $(seq 1 $_w))
clear
echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "\033[0;35m$UI_BAR\033[0m"
echo -e "\033[1;35m▍\033[1;36mติดตั้ง SSH / VPN\033[0m"
echo -e "  \033[1;32m●\033[0m \033[1;37mจัดการผู้ใช้และเซิร์ฟเวอร์\033[0m"
echo -e "  \033[1;32m●\033[0m \033[1;37mตั้งค่าแพ็กเกจและเครือข่าย\033[0m"
echo -e "  \033[1;33m!\033[0m \033[0;37mแนะนำ VPS ใหม่ + เปิดพอร์ตก่อน\033[0m"
echo -e "\033[0;35m$UI_BAR\033[0m"
read -p "$(echo -e "\033[1;35m❯ \033[1;37mเริ่มติดตั้ง? \033[0;90m[Y/n]\033[1;35m › \033[1;37m")" -e -i y resp
[[ $resp = @(n|N) ]] && rm $HOME/autoscript.sh* && exit 0
_lnk2=$(echo "$key"|awk -F : '{print $2}')
_lnk1=$(echo "$key"|awk -F : '{print $1}')
rm $_Ink/list > /dev/null 2>&1; wget -P $_Ink https://raw.githubusercontent.com/savat/ocr-api/main/Install/list > /dev/null 2>&1; verif_key
sleep 1s
verif_db
clear
echo -e "\033[0;35m$UI_BAR\033[0m"
echo -e "\E[45;1;37m ⚡ หลวงพี่ · AUTOSCRIPT\E[K\E[0m"
echo -e "\033[0;35m$UI_BAR\033[0m"
echo -e "\033[1;35m▍\033[1;36mขั้นที่ 1/3\033[0m  \033[1;37mอัปเดตรายการแพ็กเกจ\033[0m"
fun_bar 'fun_attlist'
echo -e "\n\033[1;35m▍\033[1;36mขั้นที่ 2/3\033[0m  \033[1;37mติดตั้งเครื่องมือที่จำเป็น\033[0m"
fun_bar 'inst_pct'
echo -e "\n\033[1;35m▍\033[1;36mขั้นที่ 3/3\033[0m  \033[1;37mตั้งค่าเครือข่ายและไฟล์ระบบ\033[0m"
[[ -f "/usr/sbin/ufw" ]] && ufw allow 443/tcp ; ufw allow 80/tcp ; ufw allow 3128/tcp ; ufw allow 8799/tcp ; ufw allow 8080/tcp
fun_bar "$_Ink/list $_lnk $_Ink $_1nk $key"
cd $HOME
echo -e "\n\033[0;35m$UI_BAR\033[0m"
echo -e "\033[1;32m✔ ติดตั้งเสร็จเรียบร้อย\033[0m"
echo -e "  พิมพ์ \E[30;46m menu \E[0m เพื่อเปิดเมนู"
echo -e "\033[0;35m$UI_BAR\033[0m"
rm $HOME/autoscript.sh* && cat /dev/null > ~/.bash_history && history -c
