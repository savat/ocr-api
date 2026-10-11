#!/bin/sh
# ZIVPN manager  (ติดตั้งเป็นคำสั่ง: m)
# ผู้ใช้ = รหัสผ่านใน config.json (auth.mode = passwords)
# ข้อมูล: $ETC/manager.conf , $ETC/users.db , $ETC/config.json
# เรียกจาก install.sh:  m render | m health | m add | m expire | m nat up|down | m backup
VERSION="1.0.0"
ETC="${ZP_ETC:-/etc/zivpn}"
DRY="${ZP_DRY:-0}"
CONF="$ETC/manager.conf"
DB="$ETC/users.db"
CFG="$ETC/config.json"
UNIT=/etc/systemd/system

# อ่านค่าจาก manager.conf แบบปลอดภัย (ไม่ source เพราะ obfs มี backtick ได้)
conf() { [ -r "$CONF" ] && sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF" | head -n1; }
HOST=$(conf HOST); PORT=$(conf PORT); RANGE=$(conf RANGE); OBFS=$(conf OBFS)
PORT=${PORT:-5667}
OBFS=${OBFS:-zivpn}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  E=$(printf '\033'); R="$E[1;31m"; G="$E[1;32m"; Y="$E[1;33m"; C="$E[1;36m"; B="$E[1m"; D="$E[2m"; N="$E[0m"
else
  E=""; R=""; G=""; Y=""; C=""; B=""; D=""; N=""
fi
BAR="════════════════════════════════════════════════════"
head() {
  printf '%s\n' "$BAR"
  printf '             %sZIVPN MANAGER%s  %s%s%s\n' "$B" "$N" "$D" "v$VERSION" "$N"
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
      [ -z "$_rw" ] && continue
      _p="$_p\"$(jesc "$_rw")\","
    done < "$DB"
  fi
  _p=$(printf '%s' "$_p" | sed 's/,$//')
  [ -z "$_p" ] && _p='"zi"'
  cat > "$CFG" <<EOF
{
  "listen": ":$PORT",
  "cert": "$ETC/zivpn.crt",
  "key": "$ETC/zivpn.key",
  "obfs": "$(jesc "$OBFS")",
  "auth": {
    "mode": "passwords",
    "config": [$_p]
  }
}
EOF
  chmod 600 "$CFG" 2>/dev/null
}

reload() { [ "$DRY" = 1 ] || systemctl restart zivpn.service >/dev/null 2>&1; }

count() { [ -r "$DB" ] && grep -c . "$DB" 2>/dev/null || printf '0'; }

cmd_add() {
  _n=$1; _w=$2; _d=$3
  [ -z "$_n" ] && { printf 'ชื่อผู้ใช้: '; read -r _n; }
  [ -z "$_n" ] && { bad "ยกเลิก"; return 1; }
  if [ -r "$DB" ] && grep -qF "$_n:" "$DB"; then bad "มีผู้ใช้ $_n อยู่แล้ว"; return 1; fi
  [ -z "$_w" ] && { printf 'รหัสผ่าน (เว้นว่าง = ใช้ชื่อผู้ใช้): '; read -r _w; [ -z "$_w" ] && _w=$_n; }
  if [ -z "$_d" ]; then printf 'อายุ (วัน, 0 = ไม่หมดอายุ) [30]: '; read -r _d; [ -z "$_d" ] && _d=30; fi
  case $_d in *[!0-9]*) _d=30 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  printf '%s:%s:%s\n' "$_n" "$_w" "$_exp" >> "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "เพิ่มผู้ใช้ $_n (รหัส: $_w, หมดอายุ: $(dfmt "$_exp"))"
}

cmd_del() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้ที่จะลบ: '; read -r _n; }
  [ -z "$_n" ] && return 1
  grep -qF "$_n:" "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  awk -F: -v n="$_n" '$1 != n' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "ลบผู้ใช้ $_n แล้ว"
}

cmd_passwd() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  grep -qF "$_n:" "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  printf 'รหัสผ่านใหม่: '; read -r _w
  [ -z "$_w" ] && { bad "ยกเลิก"; return 1; }
  awk -F: -v n="$_n" -v w="$_w" 'BEGIN{OFS=":"} $1==n{$2=w} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  render; reload; ok "เปลี่ยนรหัสผ่าน $_n แล้ว"
}

cmd_setexp() {
  _n=$1; _d=$2
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  grep -qF "$_n:" "$DB" 2>/dev/null || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  if [ -z "$_d" ]; then printf 'อายุใหม่ (วัน, 0 = ไม่หมดอายุ): '; read -r _d; fi
  case $_d in ''|*[!0-9]*) bad "จำนวนวันไม่ถูกต้อง"; return 1 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  awk -F: -v n="$_n" -v e="$_exp" 'BEGIN{OFS=":"} $1==n{$3=e} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  ok "ตั้งอายุ $_n -> $(dfmt "$_exp")"
}

cmd_list() {
  head
  if [ ! -s "$DB" ]; then printf '  %sยังไม่มีผู้ใช้งาน%s\n' "$D" "$N"; return; fi
  printf '  %s%-16s %-16s %-18s %s%s\n' "$B" "USER" "PASSWORD" "EXPIRE" "STATUS" "$N"
  while IFS=: read -r _n _w _e; do
    [ -z "$_n" ] && continue
    _s="${G}ok${N}"
    if [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$(now)" ] 2>/dev/null; then _s="${R}หมดอายุ${N}"; fi
    printf '  %-16s %-16s %-18s %b\n' "$_n" "$_w" "$(dfmt "$_e")" "$_s"
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

cmd_nat() {
  _act=$1
  [ -z "$RANGE" ] && return 0
  _if=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  [ -z "$_if" ] && _if=$(ip -4 route ls 2>/dev/null | grep default | grep -oE 'dev [^ ]+' | awk '{print $2}' | head -n1)
  [ -z "$_if" ] && { bad "หาการ์ดเครือข่าย (default route) ไม่เจอ"; return 1; }
  _a=${RANGE%:*}; _b=${RANGE#*:}
  case $_act in
    up)
      iptables -t nat -C PREROUTING -i "$_if" -p udp --dport "$_a:$_b" -j DNAT --to-destination ":$PORT" 2>/dev/null || \
      iptables -t nat -A PREROUTING -i "$_if" -p udp --dport "$_a:$_b" -j DNAT --to-destination ":$PORT"
      ;;
    down)
      while iptables -t nat -D PREROUTING -i "$_if" -p udp --dport "$_a:$_b" -j DNAT --to-destination ":$PORT" 2>/dev/null; do :; done
      ;;
  esac
  return 0
}

cmd_backup() {
  _dir="${ZP_BACKUP_DIR:-/root}"
  _f="$_dir/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$_dir" 2>/dev/null
  if tar czf "$_f" -C "$(dirname "$ETC")" "$(basename "$ETC")" 2>/dev/null; then
    ok "สำรองข้อมูลแล้ว: $_f"
  else
    bad "สำรองข้อมูลไม่สำเร็จ"
    return 1
  fi
}

cmd_health() {
  _st=$(systemctl is-active zivpn.service 2>/dev/null); [ -z "$_st" ] && _st="unknown"
  printf '  %s•%s บริการ zivpn : %b%s%b\n' "$C" "$N" "$([ "$_st" = active ] && printf '%s' "$G" || printf '%s' "$R")" "$_st" "$N"
  printf '  %s•%s พอร์ต UDP   : %s/udp\n' "$C" "$N" "$PORT"
  [ -n "$RANGE" ] && printf '  %s•%s Port hopping: %s -> %s\n' "$C" "$N" "$RANGE" "$PORT"
  printf '  %s•%s Obfs        : %s\n' "$C" "$N" "$OBFS"
  printf '  %s•%s ผู้ใช้       : %s\n' "$C" "$N" "$(count)"
  [ -n "$HOST" ] && printf '  %s•%s ที่อยู่      : %s\n' "$C" "$N" "$HOST"
}

cmd_uninstall() {
  systemctl disable --now zivpn.service zivpn-expire.timer zivpn-nat.service >/dev/null 2>&1
  cmd_nat down >/dev/null 2>&1
  rm -f "$UNIT/zivpn.service" "$UNIT/zivpn-expire.service" "$UNIT/zivpn-expire.timer" "$UNIT/zivpn-nat.service"
  systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$ETC" /usr/local/bin/zivpn
  ok "ถอนติดตั้ง ZIVPN แล้ว"
  rm -f "$0" 2>/dev/null
}

cmd_menu() {
  while :; do
    head
    printf '  %s[01]%s %s•%s เพิ่มผู้ใช้งาน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[02]%s %s•%s ลบผู้ใช้งาน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[03]%s %s•%s ดูรายชื่อผู้ใช้\n' "$C" "$N" "$Y" "$N"
    printf '  %s[04]%s %s•%s เปลี่ยนรหัสผ่าน\n' "$C" "$N" "$Y" "$N"
    printf '  %s[05]%s %s•%s ตั้งวันหมดอายุ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[06]%s %s•%s สถานะบริการ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[07]%s %s•%s สำรองข้อมูล\n' "$C" "$N" "$Y" "$N"
    printf '  %s[08]%s %s•%s รีสตาร์ทบริการ\n' "$C" "$N" "$Y" "$N"
    printf '  %s[00]%s %s•%s ออก\n' "$C" "$N" "$Y" "$N"
    printf '%s\n' "$BAR"
    printf '  Select Menu ? : '; read -r _x
    case $_x in
      1|01) cmd_add ;;
      2|02) cmd_del ;;
      3|03) cmd_list ;;
      4|04) cmd_passwd ;;
      5|05) cmd_setexp ;;
      6|06) head; cmd_health ;;
      7|07) cmd_backup ;;
      8|08) reload && ok "รีสตาร์ทแล้ว" ;;
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
  nat)      shift; cmd_nat "$@" ;;
  backup)   cmd_backup ;;
  restart)  reload; cmd_health ;;
  start)    systemctl start zivpn.service ;;
  stop)     systemctl stop zivpn.service ;;
  status)   systemctl status zivpn.service --no-pager ;;
  uninstall) cmd_uninstall ;;
  menu|'')  cmd_menu ;;
  *) printf 'การใช้งาน: m {render|health|add|list|del|passwd|setexp|expire|nat up|down|backup|restart|start|stop|status|uninstall|menu}\n' ;;
esac
