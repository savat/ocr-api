#!/bin/sh
# HYSTERIA1 manager  (ติดตั้งเป็นคำสั่ง: hy)
# Hysteria v1:  auth = "passwords" (เทียบสตริงตรง)  ->  เก็บผู้ใช้เป็น "user:password"
# ข้อมูล: $ETC/manager.conf , $ETC/users.db , $ETC/config.json
# เรียกจาก install.sh:  hy render | hy health | hy add | hy expire | hy backup
VERSION="1.0.0"
ETC="${H1_ETC:-/etc/hysteria1}"
DRY="${H1_DRY:-0}"
CONF="$ETC/manager.conf"
DB="$ETC/users.db"
CFG="$ETC/config.json"
UNIT=/etc/systemd/system
SVC=hysteria1.service

# อ่านค่าจาก manager.conf (ไม่ source เพราะ obfs อาจมีตัวอักษรพิเศษ)
conf() { [ -r "$CONF" ] && sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF" | head -n1; }
HOST=$(conf HOST); PORT=$(conf PORT); OBFS=$(conf OBFS)
PORT=${PORT:-443}
OBFS=${OBFS:-luangphi}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  E=$(printf '\033'); R="$E[1;31m"; G="$E[1;32m"; Y="$E[1;33m"; C="$E[1;36m"; B="$E[1m"; D="$E[2m"; N="$E[0m"
else
  E=""; R=""; G=""; Y=""; C=""; B=""; D=""; N=""
fi
BAR="════════════════════════════════════════════════════"
ui_head() {
  printf '%s\n' "$BAR"
  printf '           %sHYSTERIA1 MANAGER%s  %s%s%s\n' "$B" "$N" "$D" "v$VERSION (Hysteria v1)" "$N"
  printf '%s\n' "$BAR"
}
ok()  { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
bad() { printf '  %s✘%s %s\n' "$R" "$N" "$*" >&2; }

jesc() { printf '%s' "$1" | sed 's/["\\]//g'; }
now()  { date +%s; }
dfmt() { [ -z "$1" ] || [ "$1" = 0 ] && { printf 'ไม่หมดอายุ'; return; }; date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$1"; }

render() {
  [ "$DRY" = 1 ] && return 0
  _p=""
  if [ -r "$DB" ]; then
    while IFS=: read -r _rn _rw _re; do
      [ -z "$_rn" ] && continue
      _p="$_p\"$(jesc "$_rn:$_rw")\","
    done < "$DB"
  fi
  _p=$(printf '%s' "$_p" | sed 's/,$//')
  cat > "$CFG" <<EOF
{
  "listen": ":$PORT",
  "cert": "$ETC/hysteria.crt",
  "key": "$ETC/hysteria.key",
  "obfs": "$(jesc "$OBFS")",
  "up_mbps": 100,
  "down_mbps": 100,
  "recv_window_conn": 196608,
  "recv_window_client": 491520,
  "auth": {
    "mode": "passwords",
    "config": [$_p]
  }
}
EOF
  chmod 600 "$CFG" 2>/dev/null
}

reload() { [ "$DRY" = 1 ] || systemctl restart "$SVC" >/dev/null 2>&1; }
count() { [ -r "$DB" ] && grep -c . "$DB" 2>/dev/null || printf '0'; }

# ค่าที่ลูกค้าต้องใส่เป็น auth_str = "user:password"
auth_str_for() { # $1 = ชื่อผู้ใช้
  [ -r "$DB" ] || return 0
  awk -F: -v n="$1" '$1==n { printf "%s:%s", $1, $2; exit }' "$DB"
}

addr_host() { [ -n "$HOST" ] && printf '%s' "$HOST" || printf 'YOUR_SERVER_IP'; }

cmd_add() {
  _n=$1; _w=$2; _d=$3
  [ -z "$_n" ] && { printf 'ชื่อผู้ใช้: '; read -r _n; }
  [ -z "$_n" ] && { bad "ยกเลิก"; return 1; }
  case $_n in *:*) bad "ชื่อผู้ใช้ห้ามมีเครื่องหมาย :"; return 1 ;; esac
  if [ -r "$DB" ] && awk -F: -v n="$_n" '$1==n{f=1} END{exit !f}' "$DB"; then bad "มีผู้ใช้ $_n อยู่แล้ว"; return 1; fi
  [ -z "$_w" ] && { printf 'รหัสผ่าน (เว้นว่าง = ใช้ชื่อผู้ใช้): '; read -r _w; [ -z "$_w" ] && _w=$_n; }
  if [ -z "$_d" ]; then printf 'อายุ (วัน, 0 = ไม่หมดอายุ) [30]: '; read -r _d; [ -z "$_d" ] && _d=30; fi
  case $_d in *[!0-9]*) _d=30 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  printf '%s:%s:%s\n' "$_n" "$_w" "$_exp" >> "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "เพิ่มผู้ใช้ $_n (auth_str: $_n:$_w, หมดอายุ: $(dfmt "$_exp"))"
}

cmd_del() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้ที่จะลบ: '; read -r _n; }
  [ -z "$_n" ] && return 1
  awk -F: -v n="$_n" '$1==n{f=1} END{exit !f}' "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  awk -F: -v n="$_n" '$1 != n' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "ลบผู้ใช้ $_n แล้ว"
}

cmd_passwd() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  awk -F: -v n="$_n" '$1==n{f=1} END{exit !f}' "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  printf 'รหัสผ่านใหม่: '; read -r _w
  [ -z "$_w" ] && { bad "ยกเลิก"; return 1; }
  awk -F: -v n="$_n" -v w="$_w" 'BEGIN{OFS=":"} $1==n{$2=w} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  render; reload; ok "เปลี่ยนรหัสผ่าน $_n แล้ว"
}

cmd_setexp() {
  _n=$1; _d=$2
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  awk -F: -v n="$_n" '$1==n{f=1} END{exit !f}' "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  if [ -z "$_d" ]; then printf 'อายุใหม่ (วัน, 0 = ไม่หมดอายุ): '; read -r _d; fi
  case $_d in ''|*[!0-9]*) bad "จำนวนวันไม่ถูกต้อง"; return 1 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  awk -F: -v n="$_n" -v e="$_exp" 'BEGIN{OFS=":"} $1==n{$3=e} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  render; reload
  ok "ตั้งอายุ $_n -> $(dfmt "$_exp")"
}

cmd_list() {
  ui_head
  if [ ! -s "$DB" ]; then printf '  %sยังไม่มีผู้ใช้งาน%s\n' "$D" "$N"; return; fi
  printf '  %s%-16s %-18s %-18s %s%s\n' "$B" "USER" "PASSWORD" "EXPIRE" "STATUS" "$N"
  while IFS=: read -r _n _w _e; do
    [ -z "$_n" ] && continue
    _s="${G}ok${N}"
    if [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$(now)" ] 2>/dev/null; then _s="${R}หมดอายุ${N}"; fi
    printf '  %-16s %-18s %-18s %b\n' "$_n" "$_w" "$(dfmt "$_e")" "$_s"
  done < "$DB"
  printf '  %sรวม %s ผู้ใช้%s\n' "$D" "$(count)" "$N"
}

cmd_expire() {
  [ -r "$DB" ] || return 0
  _t=$(now); _tmp="$DB.$$"; _rm=0
  while IFS=: read -r _n _w _e; do
    if [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$_t" ] 2>/dev/null; then _rm=$((_rm + 1)); continue; fi
    printf '%s:%s:%s\n' "$_n" "$_w" "$_e" >> "$_tmp"
  done < "$DB"
  if [ "$_rm" -gt 0 ]; then mv -f "$_tmp" "$DB"; chmod 600 "$DB" 2>/dev/null; render; reload; fi
  rm -f "$_tmp"
}

# ---- ดูคอนฟิก client (Hysteria v1) ----------------------------------------
cmd_client() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้ที่ต้องการคอนฟิก: '; read -r _n; }
  _auth=$(auth_str_for "$_n")
  [ -z "$_auth" ] && { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  _host=$(addr_host)
  ui_head
  printf '  %sไฟล์คอนฟิกสำหรับแอป Hysteria v1 (วางเป็น config.json) :%s\n\n' "$D" "$N"
  cat <<EOF
{
  "server": "$_host:$PORT",
  "auth_str": "$_auth",
  "obfs": "$(jesc "$OBFS")",
  "up_mbps": 100,
  "down_mbps": 100,
  "retry": 3,
  "retry_interval": 1,
  "socks5": { "listen": "127.0.0.1:1080" },
  "http": { "listen": "127.0.0.1:8989" },
  "insecure": true,
  "ca": "",
  "recv_window_conn": 196608,
  "recv_window": 491520
}
EOF
}

cmd_health() {
  _st=$(systemctl is-active "$SVC" 2>/dev/null); [ -z "$_st" ] && _st="unknown"
  printf '  %s•%s บริการ      : %b%s%b\n' "$C" "$N" "$([ "$_st" = active ] && printf '%s' "$G" || printf '%s' "$R")" "$_st" "$N"
  printf '  %s•%s พอร์ต UDP  : %s/udp\n' "$C" "$N" "$PORT"
  printf '  %s•%s Obfs       : %s\n' "$C" "$N" "$OBFS"
  printf '  %s•%s ผู้ใช้      : %s\n' "$C" "$N" "$(count)"
  [ -n "$HOST" ] && printf '  %s•%s ที่อยู่     : %s\n' "$C" "$N" "$HOST"
}

cmd_log() {
  command -v journalctl >/dev/null 2>&1 || { bad "ไม่พบ journalctl"; return 1; }
  ui_head
  journalctl -u "$SVC" -n 40 --no-pager 2>/dev/null
}

cmd_backup() {
  _dir="${H1_BACKUP_DIR:-/root}"
  _f="$_dir/hysteria1-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$_dir" 2>/dev/null
  if tar czf "$_f" -C "$(dirname "$ETC")" "$(basename "$ETC")" 2>/dev/null; then
    ok "สำรองข้อมูลแล้ว: $_f"
  else
    bad "สำรองข้อมูลไม่สำเร็จ"
    return 1
  fi
}

cmd_uninstall() {
  systemctl disable --now "$SVC" hysteria1-expire.timer >/dev/null 2>&1
  rm -f "$UNIT/hysteria1.service" "$UNIT/hysteria1-expire.service" "$UNIT/hysteria1-expire.timer"
  systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$ETC" /usr/local/bin/hysteria1
  ok "ถอนติดตั้ง Hysteria1 แล้ว"
  rm -f "$0" 2>/dev/null
}

cmd_menu() {
  while :; do
    ui_head
    printf '  %s[01]%s %s•%s เพิ่มผู้ใช้งาน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[02]%s %s•%s ลบผู้ใช้งาน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[03]%s %s•%s ดูรายชื่อผู้ใช้\n' "$C" "$N" "$Y" "$N"
    printf '  %s[04]%s %s•%s เปลี่ยนรหัสผ่าน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[05]%s %s•%s ตั้งวันหมดอายุ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[06]%s %s•%s ดูคอนฟิก client (Hysteria v1)\n' "$C" "$N" "$Y" "$N"
    printf '  %s[07]%s %s•%s สถานะบริการ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[08]%s %s•%s ดู log ล่าสุด\n' "$C" "$N" "$Y" "$N"
    printf '  %s[09]%s %s•%s สำรองข้อมูล\n' "$C" "$N" "$Y" "$N"
    printf '  %s[10]%s %s•%s รีสตาร์ทบริการ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[11]%s %s•%s ถอนติดตั้ง\n' "$C" "$N" "$Y" "$N"
    printf '  %s[00]%s %s•%s ออก\n' "$C" "$N" "$Y" "$N"
    printf '%s\n' "$BAR"
    printf '  Select Menu ? : '; read -r _x
    case $_x in
      1|01) cmd_add ;;
      2|02) cmd_del ;;
      3|03) cmd_list ;;
      4|04) cmd_passwd ;;
      5|05) cmd_setexp ;;
      6|06) cmd_client ;;
      7|07) cmd_health ;;
      8|08) cmd_log ;;
      9|09) cmd_backup ;;
      10) reload && ok "รีสตาร์ทแล้ว" ;;
      11) cmd_uninstall; return ;;
      0|00) return ;;
      *) : ;;
    esac
    printf '\n  %sกด ENTER เพื่อกลับเมนู...%s' "$D" "$N"; read -r _dummy
  done
}

case "${1:-menu}" in
  render)   render ;;
  health)   cmd_health ;;
  add)      shift; cmd_add "$@" ;;
  list|ls)  cmd_list ;;
  del|rm)   shift; cmd_del "$@" ;;
  passwd)   shift; cmd_passwd "$@" ;;
  setexp)   shift; cmd_setexp "$@" ;;
  expire)   cmd_expire ;;
  client|cfg) shift; cmd_client "$@" ;;
  log)      cmd_log ;;
  backup)   cmd_backup ;;
  restart)  reload; cmd_health ;;
  start)    systemctl start "$SVC" ;;
  stop)     systemctl stop "$SVC" ;;
  status)   systemctl status "$SVC" --no-pager ;;
  uninstall) cmd_uninstall ;;
  menu|'')  cmd_menu ;;
  *) printf 'การใช้งาน: hy {render|health|add|list|del|passwd|setexp|expire|client|log|backup|restart|start|stop|status|uninstall|menu}\n' ;;
esac
