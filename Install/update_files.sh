#!/bin/bash
# อัปเดตสคริปต์ทั้งหมดจาก GitHub แทนไฟล์เดิม - รันบนเครื่องที่ติดตั้งสคริปต์ไว้แล้ว
# วิธีใช้ (รันเป็น root):
#   curl -s https://raw.githubusercontent.com/savat/ocr-api/main/Install/update_files.sh | bash
# หรือ:
#   wget -qO- https://raw.githubusercontent.com/savat/ocr-api/main/Install/update_files.sh | bash
set -u
RAW="https://raw.githubusercontent.com/savat/ocr-api/main"
[[ "$(id -u)" = 0 ]] || { echo -e "\033[1;31m[Error] \033[1;37mต้องรันด้วย root เท่านั้น\033[0m"; exit 1; }

echo -e "\033[1;36m[a] โหลดรายชื่อไฟล์จาก GitHub ...\033[0m"
_list=""
if command -v curl >/dev/null 2>&1; then
  _list=$(curl -fsSL "$RAW/Install/list" 2>/dev/null) || _list=""
fi
if [[ -z "$_list" ]]; then
  _list=$(wget -qO- "$RAW/Install/list" 2>/dev/null)
fi
[[ -n "$_list" ]] || { echo -e "\033[1;31m[Error] \033[1;37mดาวน์โหลด Install/list ไม่สำเร็จ (ตรวจอินเทอร์เน็ต)\033[0m"; exit 1; }

_mdls=$(printf '%s\n' "$_list" | sed -n 's/^_mdls=(\(.*\))$/\1/p' | tr -d '"()')
if [[ -z "$_mdls" ]]; then
  _mdls="addhost delhost alterarsenha criarusuario expcleaner mudardata remover criarteste verifbot droplimiter alterarlimite sshmonitor badvpn userbackup instsqd blockt otimizar menu ferramentascodes gestorcodes usercodes utilscodes speedtest banner senharoot atualizarsistema reiniciarservicos reiniciarsistema attscript conexao delscript detalhes infousers slow_dns verifatt limiter uexpired cabecalho tcpspeed open.py proxy.py wsproxy.py trojan-go onlineapp swapmemory v2raymanager apache2menu webminmenu vnc_inst shadowsocks_user zivpn hysteria1"
fi

echo -e "\033[1;36m[b] ดาวน์โหลดโมดูลทั้งหมด ($(printf '%s' "$_mdls" | wc -w) ไฟล์) แทนไฟล์เดิมใน /bin ...\033[0m"
_nok=0
_fail=""
for _arq in $_mdls; do
  _got=0
  for _try in 1 2 3; do
    wget -q --timeout=20 --tries=2 -O "/bin/$_arq" "$RAW/Modulos/$_arq" \
      && [ -s "/bin/$_arq" ] \
      && head -n1 "/bin/$_arq" 2>/dev/null | grep -q '^#!' \
      && { _got=1; break; }
    sleep 1
  done
  if [ "$_got" = 1 ]; then
    chmod +x "/bin/$_arq"
  else
    _nok=1; _fail="$_fail $_arq"
    echo -e "  \033[1;31m✘ $_arq (ดาวน์โหลดไม่สำเร็จแม้ลอง 3 ครั้ง)\033[0m"
    rm -f "/bin/$_arq"
  fi
done
if [ "$_nok" = 1 ]; then
  echo -e "\033[1;33m! ไฟล์ที่ดาวน์โหลดไม่สำเร็จ: $_fail\033[0m"
  echo -e "\033[1;33m  ลองรันคำสั่งนนี้อีกครั้ง หรือเช็คอินเทอร์เน็ต\033[0m"
fi

echo -e "\033[1;36m[c] ไฟล์เสริม -> /etc/AutoScript ...\033[0m"
[[ -d /etc/AutoScript ]] || mkdir -p /etc/AutoScript
for _arq in cabecalho open.py proxy.py wsproxy.py; do
  [[ -e "/bin/$_arq" ]] && mv -f "/bin/$_arq" "/etc/AutoScript/$_arq"
done
wget -q -O /etc/AutoScript/ShellBot.sh "$RAW/Install/ShellBot.sh"

echo -e "\033[1;36m[d] อัปเดต list / version ...\033[0m"
wget -q -O /usr/local/lib/list "$RAW/Install/list" && chmod +x /usr/local/lib/list
_v=$(wget -qO- "$RAW/Install/version" 2>/dev/null)
printf '%s\n' "$_v" | sed -n '1p' > /bin/version
cat /bin/version > /home/AutoScript 2>/dev/null

# ใบรับรอง licence (ถ้ายังไม่มี)
[[ -e /usr/lib/AutoScript ]] || { mkdir -p /usr/lib; echo -e 'by: @หลวงพี่' > /usr/lib/AutoScript; }
[[ -e /etc/AutoScript/.tmp/autoscript ]] && cp /usr/lib/AutoScript /etc/AutoScript/.tmp/autoscript

echo -e "\033[1;32mเสร็จเรียบร้อย - อัปเดตสคริปต์เป็นเวอร์ชันล่าสุดแล้ว (v$(sed -n '1p' /bin/version 2>/dev/null))\033[0m"
exit 0