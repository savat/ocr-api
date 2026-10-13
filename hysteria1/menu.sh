#!/bin/sh
# HYSTERIA1 manager  (ติดตั้งเป็นคำสั่ง: hy)
# Hysteria v1:  auth = "passwords" (เทียบสตริงตรง)  ->  เก็บผู้ใช้เป็น "user:password"
# ข้อมูล: $ETC/manager.conf , $ETC/users.db , $ETC/config.json
# เรียกจาก install.sh:  hy render | hy health | hy add | hy expire | hy backup
VERSION="1.1.0"
RAW="${H1_RAW:-https://raw.githubusercontent.com/savat/ocr-api/main}"
ETC="${H1_ETC:-/etc/hysteria1}"
DRY="${H1_DRY:-0}"
CONF="$ETC/manager.conf"
DB="$ETC/users.db"
CFG="$ETC/config.json"
UNIT=/etc/systemd/system
SVC=hysteria1.service

# อ่านค่าจาก manager.conf (ไม่ source เพราะ obfs อาจมีตัวอักษรพิเศษ)
conf() { [ -r "$CONF" ] && sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF" | head -n1; }
conf_set() { # $1 key $2 value -> เขียน/แทนค่าใน manager.conf
  _f="$CONF.$$"; : >"$_f"
  while IFS= read -r _l; do
    case "$_l" in "$1='"*"'") continue ;; esac
    [ -n "$_l" ] && printf '%s\n' "$_l" >>"$_f"
  done < "$CONF"
  printf "%s='%s'\n" "$1" "$2" >>"$_f"
  chmod 600 "$_f" 2>/dev/null && mv -f "$_f" "$CONF"
}
conf_del() { # $1 key -> ลบค่าออกจาก manager.conf
  _f="$CONF.$$"; : >"$_f"
  while IFS= read -r _l; do
    case "$_l" in "$1='"*"'") continue ;; esac
    [ -n "$_l" ] && printf '%s\n' "$_l" >>"$_f"
  done < "$CONF"
  chmod 600 "$_f" 2>/dev/null && mv -f "$_f" "$CONF"
}
HOST=$(conf HOST); PORT=$(conf PORT); OBFS=$(conf OBFS); RANGE=$(conf RANGE); RESOLVER=$(conf RESOLVER); TRACK=$(conf TRACK)
SESS="$ETC/sessions"
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
  printf '       🛡️  %sHYSTERIA1 MANAGER%s  %s%s%s\n' "$B" "$N" "$D" "v$VERSION (Hysteria v1)" "$N"
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
  if [ "$TRACK" = on ] && [ -x "$ETC/auth.sh" ]; then
    _auth="{\"mode\": \"external\", \"config\": {\"cmd\": \"$ETC/auth.sh\"}}"
  else
    _auth="{\"mode\": \"passwords\", \"config\": [$_p]}"
  fi
  cat > "$CFG" <<EOF
{
  "listen": ":$PORT",
  "cert": "$ETC/hysteria.crt",
  "key": "$ETC/hysteria.key",
  "obfs": "$(jesc "$OBFS")",
  "up_mbps": 100,
  "down_mbps": 100,
  "resolver": "${H1_RESOLVER:-${RESOLVER:-udp://1.1.1.1:53}}",
  "resolve_preference": "${H1_RESOLVE_PREF:-46}",
  "recv_window_conn": 196608,
  "recv_window_client": 491520,
  "auth": $_auth
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

# ---- ผู้ใช้ออนไลน์ ----------------------------------------------------------
# แหล่ง 1: conntrack = flow UDP ที่ server ตอบกลับจากพอร์ต $PORT (รวม hopping) -> IP ที่ออนไลน์จริง
# แหล่ง 2: hy track on = auth แบบ external (auth.sh) จดว่า addr ไหนใช้บัญชีอะไร -> แยกรายบัญชี
SESS_WIN=86400   # ถ้าไม่มี log connect/disconnect: ถือว่าออนไลน์ถ้า auth จาก IP นั้นใน 24 ชม. และ IP ยังมี flow

ensure_ct() { # กฎนับเฉย ๆ (ไม่มี target) เพื่อให้ kernel ติดตาม conntrack ของพอร์ตนี้
  [ "$DRY" = 1 ] && return 0
  command -v iptables >/dev/null 2>&1 || return 0
  iptables -w -C INPUT -p udp --dport "$PORT" -m conntrack --ctstate NEW,ESTABLISHED 2>/dev/null && return 0
  modprobe nf_conntrack 2>/dev/null
  iptables -w -I INPUT -p udp --dport "$PORT" -m conntrack --ctstate NEW,ESTABLISHED 2>/dev/null
  return 0
}

ct_list() { # ip<TAB>จำนวน flow
  if [ -r /proc/net/nf_conntrack ]; then cat /proc/net/nf_conntrack 2>/dev/null
  elif command -v conntrack >/dev/null 2>&1; then conntrack -L -p udp 2>/dev/null
  else return 0; fi | awk -v P="$PORT" '
    /(^| )udp / && !/UNREPLIED/ {
      ip=""; c=0; rp=""
      for (i=1;i<=NF;i++) {
        if ($i ~ /^src=/ && ip=="") ip=substr($i,5)
        if ($i ~ /^sport=/) { c++; if (c==2) rp=substr($i,7) }
      }
      if (rp==P && ip!="" && ip!="127.0.0.1") n[ip]++
    }
    END { for (k in n) printf "%s\t%d\n", k, n[k] }' | sort
}

write_auth() {
  cat >"$ETC/auth.sh" <<'AUTHEOF'
#!/bin/sh
# เรียกโดย hysteria v1:  auth.sh ADDR AUTH_STR SEND RECV   (AUTH_STR = user:password)
ETC=/etc/hysteria1
now=$(date +%s)
u=$(awk -F: -v a="$2" -v t="$now" '($1 ":" $2)==a && ($3=="" || $3==0 || $3>t){print $1; exit}' "$ETC/users.db" 2>/dev/null)
[ -n "$u" ] || { echo invalid; exit 1; }
printf '%s|%s|%s\n' "$now" "$1" "$u" >>"$ETC/sessions"
echo "$u"
exit 0
AUTHEOF
  chmod 700 "$ETC/auth.sh"; : >>"$SESS"; chmod 600 "$SESS"
}

need_root() { [ "$DRY" = 1 ] && return 0; [ "$(id -u)" -eq 0 ] || { bad "ต้องรันด้วย root ก่อน (พิมพ์: sudo -i)"; return 1; }; }

cmd_track() {
  case "$1" in on|off) need_root || return 1 ;; esac
  case "$1" in
    on)
      write_auth 2>/dev/null; [ "$DRY" = 1 ] || [ -x "$ETC/auth.sh" ] || { bad "สร้าง $ETC/auth.sh ไม่ได้ - ยกเลิก"; return 1; }
      conf_set TRACK on; TRACK=on; render; reload
      [ "$DRY" = 1 ] && return 0
      sleep 2
      if systemctl is-active --quiet "$SVC"; then
        ok "เปิดการติดตามรายบัญชีแล้ว - ให้ลูกค้าเชื่อมต่อใหม่ แล้วดู: hy online"
        printf '  %sถ้าลูกค้าเชื่อมต่อไม่ได้ ให้สั่ง: hy track off%s\n' "$D" "$N"
      else
        conf_set TRACK off; TRACK=off; render; reload
        bad "Hysteria เริ่มด้วยโหมด external ไม่ได้ - ย้อนกลับแล้ว"; return 1
      fi ;;
    off) conf_set TRACK off; TRACK=off; render; reload; ok "ปิดการติดตามรายบัญชีแล้ว (กลับไปโหมดรหัสผ่าน)" ;;
    *)   printf '  การติดตามรายบัญชี: %s\n  ใช้: hy track on | hy track off\n' "${TRACK:-off}" ;;
  esac
}

act_ips() { # ip<TAB>จำนวนบรรทัดกิจกรรม ใน 3 นาทีล่าสุด  (log v1 มีรูปแบบ [src:IP:PORT] ในทุกคำขอ)
  command -v journalctl >/dev/null 2>&1 || return 0
  journalctl -u "$SVC" --since "$(date -d '-3 min' '+%Y-%m-%d %H:%M:%S')" --no-pager -o cat 2>/dev/null | awk '
    { if (match($0, /src:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) {
        t=substr($0, RSTART+4, RLENGTH-4); sub(/:[0-9]+$/, "", t); n[t]++ } }
    END { for (k in n) printf "%s\t%d\n", k, n[k] }'
}

ip_list() { # IP ที่ออนไลน์ = มีกิจกรรมใน log หรือมี flow ใน conntrack (ถ้าเครื่องมี)
  { act_ips; ct_list; } | awk -F'\t' '
    NF>=2 { if (!($1 in n) || $2+0 > n[$1]) n[$1]=$2+0 }
    END { for (k in n) printf "%s\t%d\n", k, n[k] }' | sort
}

tracked_devices() { # user<TAB>จำนวนเครื่อง(IP ไม่ซ้ำ)<TAB>รายการ IP
  [ "$TRACK" = on ] && [ -s "$SESS" ] || return 0
  # ลูกค้ามือถือพอร์ตต้นทางเปลี่ยนบ่อย (CGNAT) จึงจับคู่ session กับ IP ไม่ใช้ IP:พอร์ต
  ip_list | cut -f1 | while read -r _ip; do
    [ -z "$_ip" ] && continue
    _us=$(awk -F'|' -v p="$_ip:" -v t="$(( $(now) - SESS_WIN ))" '
      index($2,p)==1 { if ($1+0 >= t) w[$3]=1; l=$3 }
      END { n=0; for (u in w) { print u; n=1 } if (!n && l!="") print l "*" }' "$SESS")
    [ -z "$_us" ] && _us="?"
    printf '%s\n' "$_us" | while read -r _u; do printf '%s\t%s\n' "$_u" "$_ip"; done
  done | awk -F'\t' '{
    k=$1 SUBSEP $2
    if (!(k in seen)) { seen[k]=1; n[$1]++; l[$1]=(l[$1] ? l[$1] "," : "") $2 }
  } END { for (u in n) printf "%s\t%d\t%s\n", u, n[u], l[u] }' | sort
}

cmd_online_count() {
  ensure_ct
  _t=$(tracked_devices)
  if [ -n "$_t" ]; then printf '%s\n' "$_t" | awk -F'\t' '{s+=$2} END{print s+0}'; else ip_list | grep -c .; fi
}

cmd_online() {
  need_root || return 1
  ui_head
  ensure_ct
  _trk=$(tracked_devices)
  if [ -n "$_trk" ]; then
    printf '  %s%-18s %-5s %s%s\n' "$B" "USER" "DEV" "IP" "$N"
    printf '%s\n' "$_trk" | while IFS="$(printf '\t')" read -r _u _c _ips; do printf '  %-18s %-5s %s\n' "$_u" "$_c" "$_ips"; done
    printf '%s\n' "$_trk" | grep -q '^[^	]*\*	' && printf '  %s* = ล็อกอินนานเกิน 24 ชม. (เดาจากบัญชีล่าสุดของ IP นั้น)%s\n' "$D" "$N"
    printf '  %sออนไลน์ %s บัญชี / %s เครื่อง (นับตาม IP ต่อบัญชี)%s\n' "$D" "$(printf '%s\n' "$_trk" | grep -c .)" "$(printf '%s\n' "$_trk" | awk -F'\t' '{s+=$2} END{print s+0}')" "$N"
    return 0
  fi
  _out=$(ip_list)
  if [ -z "$_out" ]; then
    printf '  %sไม่พบกิจกรรมของลูกค้าใน 3 นาทีล่าสุด%s\n' "$D" "$N"
    return 0
  fi
  printf '  %s%-40s %s%s\n' "$B" "IP ลูกค้า" "ACT" "$N"
  printf '%s\n' "$_out" | while IFS="$(printf '\t')" read -r _ip _c; do printf '  %-40s %s\n' "$_ip" "$_c"; done
  printf '  %sออนไลน์ %s อุปกรณ์ (นับตาม IP)%s\n' "$D" "$(printf '%s\n' "$_out" | grep -c .)" "$N"
  [ "$TRACK" = on ] || printf '  %s* ดูรายบัญชีได้โดยสั่ง: hy track on%s\n' "$D" "$N"
}

cmd_add() {
  _n=$1; _w=$2; _d=$3
  [ -z "$_n" ] && { printf 'ชื่อผู้ใช้: '; read -r _n; }
  [ -z "$_n" ] && { bad "ยกเลิก"; return 1; }
  case $_n in *:*) bad "ชื่อผู้ใช้ห้ามมีเครื่องหมาย :"; return 1 ;; esac
  if [ -r "$DB" ] && awk -F: -v n="$_n" '$1==n{f=1} END{exit !f}' "$DB"; then bad "มีผู้ใช้ $_n อยู่แล้ว"; return 1; fi
  [ -z "$_w" ] && { printf 'รหัสผ่าน (เว้นว่าง = ใช้ชื่อผู้ใช้): '; read -r _w; [ -z "$_w" ] && _w=$_n; }
  case $_w in *:*) bad "รหัสผ่านห้ามมีเครื่องหมาย : (auth_str ใช้จุดคั่น user:pass)"; return 1 ;; esac
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
  case $_w in *:*) bad "รหัสผ่านห้ามมีเครื่องหมาย :"; return 1 ;; esac
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
  ensure_ct
  [ -f "$SESS" ] && [ "$(wc -l <"$SESS")" -gt 3000 ] && { tail -n 2000 "$SESS" >"$SESS.t" && mv -f "$SESS.t" "$SESS"; chmod 600 "$SESS"; }
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
  if [ -n "$RANGE" ]; then
    _srv="$_host:${RANGE%:*}-${RANGE#*:}"
    _hop=","
    _hopiv='  "hop_interval": 10,'
  else
    _srv="$_host:$PORT"
    _hop=","
    _hopiv=""
  fi
  ui_head
  printf '  %sไฟล์คอนฟิกสำหรับแอป Hysteria v1 (วางเป็น config.json) :%s\n\n' "$D" "$N"
  cat <<EOF
{
  "server": "$_srv",
  "auth_str": "$_auth",
  "obfs": "$(jesc "$OBFS")",
  "up_mbps": 100,
  "down_mbps": 100,
  "retry": 3,
  "retry_interval": 1$_hop
$_hopiv
  "socks5": { "listen": "127.0.0.1:1080" },
  "http": { "listen": "127.0.0.1:8989" },
  "insecure": true,
  "ca": "",
  "recv_window_conn": 196608,
  "recv_window": 491520
}
EOF
}

# ---- DNS (8.8.8.8 + 1.1.1.1 ผ่าน system resolver) ----------------------------
# hysteria v1 รับ resolver แค่ค่าเดียว -> ใช้ "system" แล้วเขียนทั้งคู่ใน resolv.conf
# (OS จะ try ตัวแรกก่อน ทล่มแล้วสลับตัวถัดไปเอง)
cmd_dns() {
  case "$1" in
    up)
      cp -f /etc/resolv.conf "$ETC/resolv.conf.bak" 2>/dev/null
      if ! ( umask 022; cat > /etc/resolv.conf <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:2 attempts:2
EOF
      ); then
        bad "เขียน /etc/resolv.conf ไม่ได้ - ต้องรันเป็น root (sudo hy dns up)"
        return 1
      fi
      conf_set RESOLVER system
      RESOLVER=system
      render; reload
      ok "ตั้ง resolver = system + resolv.conf = 8.8.8.8 / 1.1.1.1 (fallback อัตโนมัติ)"
      ;;
    down)
      conf_del RESOLVER
      RESOLVER=
      [ -f "$ETC/resolv.conf.bak" ] && cp -f "$ETC/resolv.conf.bak" /etc/resolv.conf
      render; reload
      ok "คืน resolver เดิม (udp://1.1.1.1:53)"
      ;;
    *)
      printf '  ใช้: %shy dns up%s   ตั้ง 8.8.8.8 + 1.1.1.1\n' "$B" "$N"
      printf '       %shy dns down%s ย้อนกลับ\n' "$B" "$N"
      ;;
  esac
}

cmd_health() {
  _st=$(systemctl is-active "$SVC" 2>/dev/null); [ -z "$_st" ] && _st="unknown"
  printf '  %s•%s บริการ      : %b%s%b\n' "$C" "$N" "$([ "$_st" = active ] && printf '%s' "$G" || printf '%s' "$R")" "$_st" "$N"
  printf '  %s•%s พอร์ต UDP  : %s/udp\n' "$C" "$N" "$PORT"
  printf '  %s•%s Hopping    : %s\n' "$C" "$N" "${RANGE:-ไม่ใช้}"
  if [ "$RESOLVER" = system ]; then
    _dns=$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ -z "$_dns" ] && _dns='system'
    printf '  %s•%s DNS        : %s%s%s\n' "$C" "$N" "$B" "$_dns" "$N"
  else
    printf '  %s•%s DNS        : %s\n' "$C" "$N" "${RESOLVER:-udp://1.1.1.1:53}"
  fi
  _ho=$(iptables -t nat -L HYST1_NAT -n 2>/dev/null | grep -c DNAT || true)
  printf '  %s•%s NAT rule   : %s\n' "$C" "$N" "$([ "$_ho" -ge 1 ] 2>/dev/null && printf '%s' 'active' || printf '%s' 'off')"
  printf '  %s•%s Obfs       : %s\n' "$C" "$N" "$OBFS"
  printf '  %s•%s ผู้ใช้      : %s\n' "$C" "$N" "$(count)"
  printf '  %s•%s ออนไลน์    : %s\n' "$C" "$N" "$(cmd_online_count)"
  [ -n "$HOST" ] && printf '  %s•%s ที่อยู่     : %s\n' "$C" "$N" "$HOST"
}

# ช่วง hopping ต้องไม่ชนกับ ZIVPN (6000:19999) ที่ลงเครื่องเดียวกันได้
nat_overlap_zivpn() {
  _r0=${RANGE%:*}; _r1=${RANGE#*:}
  [ "$_r0" -le 19999 ] && [ 6000 -le "$_r1" ]
}

cmd_nat() {
  _CH=HYST1_NAT
  case "$1" in
    up)
      [ -n "$RANGE" ] || { bad "ยังไม่ได้ตั้งค่า RANGE"; return 1; }
      if nat_overlap_zivpn; then
        bad "ช่วง $RANGE ชนกับ ZIVPN (6000:19999) - เลือกช่วงอื่น เช่น 20000:29999"
        return 1
      fi
      for _t in iptables ip6tables; do
        command -v "$_t" >/dev/null 2>&1 || continue
        $_t -t nat -N $_CH 2>/dev/null
        $_t -t nat -F $_CH 2>/dev/null
        $_t -t nat -D PREROUTING -p udp -j $_CH 2>/dev/null
        $_t -t nat -I PREROUTING -p udp -j $_CH
        $_t -t nat -A $_CH -p udp --dport "$RANGE" -j DNAT --to-destination ":$PORT"
      done
      ok "เปิด NAT hopping ${RANGE%:*}-${RANGE#*:} -> $PORT/udp"
      ;;
    down)
      for _t in iptables ip6tables; do
        command -v "$_t" >/dev/null 2>&1 || continue
        $_t -t nat -D PREROUTING -p udp -j $_CH 2>/dev/null
        $_t -t nat -F $_CH 2>/dev/null
        $_t -t nat -X $_CH 2>/dev/null
      done
      ok "ปิด NAT hopping แล้ว"
      ;;
    *) printf 'ใช้: hy nat up|down\n' ;;
  esac
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

cmd_update() {
  _tmp="$0.new"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 10 -o "$_tmp" "$RAW/hysteria1/menu.sh" 2>/dev/null \
      || wget -q -O "$_tmp" "$RAW/hysteria1/menu.sh" 2>/dev/null
  else
    wget -q -O "$_tmp" "$RAW/hysteria1/menu.sh"
  fi
  if [ ! -s "$_tmp" ]; then
    bad "ดาวน์โหลดสคริปอัปเดตไม่สำเร็จ (ตรวจอินเทอร์เน็ต)"
    rm -f "$_tmp"
    return 1
  fi
  case $(head -n 1 "$_tmp") in
    '#!'*) ;;
    *) bad "ไฟล์อัปเดตไม่ถูกต้อง - ไม่ได้อัปเดต"; rm -f "$_tmp"; return 1 ;;
  esac
  _v=$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$_tmp" | head -n1); [ -z "$_v" ] && _v="?"
  chmod 755 "$_tmp" && mv -f "$_tmp" "$0"
  H1_ETC="$ETC" "$0" render >/dev/null 2>&1 && reload
  ok "อัปเดตตัวจัดการ hy เรียบร้อย (v$VERSION -> v$_v) - รัน hy อีกครั้งเพื่อใช้เวอร์ชันใหม่"
}

cmd_uninstall() {
  systemctl disable --now "$SVC" hysteria1-expire.timer hysteria1-nat.service >/dev/null 2>&1
  rm -f "$UNIT/hysteria1.service" "$UNIT/hysteria1-expire.service" "$UNIT/hysteria1-expire.timer" "$UNIT/hysteria1-nat.service"
  systemctl daemon-reload >/dev/null 2>&1
  cmd_nat down >/dev/null 2>&1
  rm -rf "$ETC" /usr/local/bin/hysteria1
  ok "ถอนติดตั้ง Hysteria1 แล้ว"
  rm -f "$0" 2>/dev/null
}

cmd_menu() {
  while :; do
    ui_head
    printf '  %s[01]%s 🚀 เพิ่มผู้ใช้งาน\n' "$C" "$N"
    printf '  %s[02]%s 🗑️  ลบผู้ใช้งาน\n' "$C" "$N"
    printf '  %s[03]%s 👥 ดูรายชื่อผู้ใช้\n' "$C" "$N"
    printf '  %s[04]%s 🔑 เปลี่ยนรหัสผ่าน\n' "$C" "$N"
    printf '  %s[05]%s 📅 ตั้งวันหมดอายุ\n' "$C" "$N"
    printf '  %s[06]%s 📲 ดูคอนฟิก client (Hysteria v1)\n' "$C" "$N"
    printf '  %s[07]%s 💚 สถานะบริการ\n' "$C" "$N"
    printf '  %s[08]%s 📜 ดู log ล่าสุด\n' "$C" "$N"
    printf '  %s[09]%s 💾 สำรองข้อมูล\n' "$C" "$N"
    printf '  %s[10]%s 🔄 รีสตาร์ทบริการ\n' "$C" "$N"
    printf '  %s[11]%s 🌐 จัดการพอร์ต Hopping\n' "$C" "$N"
    printf '  %s[12]%s ⬆️  อัปเดตสคริป\n' "$C" "$N"
    printf '  %s[13]%s 🧹 ถอนติดตั้ง\n' "$C" "$N"
    printf '  %s[14]%s 🌍 ตั้ง DNS 8.8.8.8 + 1.1.1.1\n' "$C" "$N"
    printf '  %s[15]%s 🟢 ดูผู้ใช้ออนไลน์\n' "$C" "$N"
    printf '  %s[16]%s 🔎 เปิด/ปิดติดตามรายบัญชี (ตอนนี้: %s)\n' "$C" "$N" "${TRACK:-off}"
    printf '  %s[00]%s ↩ กลับ\n' "$C" "$N"
    printf '%s\n' "$BAR"
    printf '  🔎 เลือกเมนู ? : '; read -r _x
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
      11) cmd_nat_menu ;;
      12) cmd_update ;;
      13) cmd_uninstall; return ;;
      14) cmd_dns up ;;
      15) cmd_online ;;
      16) if [ "$TRACK" = on ]; then cmd_track off; else cmd_track on; fi ;;
      0|00) return ;;
      *) : ;;
    esac
    printf '\n  %sกด ENTER เพื่อกลับเมนู...%s' "$D" "$N"; read -r _dummy
  done
}

cmd_nat_menu() {
  while :; do
    ui_head
    printf '  %s1%s %s•%s เปิด Hopping (ช่วง %s -> %s/udp)\n' "$C" "$N" "$Y" "$N" "${RANGE:-?}" "$PORT"
    printf '  %s2%s %s•%s ปิด Hopping\n' "$C" "$N" "$Y" "$N"
    printf '  %s0%s %s•%s กลับ\n' "$C" "$N" "$Y" "$N"
    printf '%s\n' "$BAR"
    printf '  🔎 เลือกเมนู ? : '; read -r _x
    case $_x in
      1) cmd_nat up ;;
      2) cmd_nat down ;;
      0) return ;;
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
  online|on) cmd_online ;;
  online-count) cmd_online_count ;;
  online-tsv)   tracked_devices ;;
  track)    shift; cmd_track "$@" ;;
  backup)   cmd_backup ;;
  restart)  reload; [ -n "$RANGE" ] && systemctl restart hysteria1-nat.service >/dev/null 2>&1; cmd_health ;;
  start)    systemctl start "$SVC"; [ -n "$RANGE" ] && systemctl start hysteria1-nat.service ;;
  stop)     systemctl stop "$SVC"; [ -n "$RANGE" ] && systemctl stop hysteria1-nat.service ;;
  status)   systemctl status "$SVC" --no-pager ;;
  nat)      shift; cmd_nat "$@" ;;
  dns)      shift; cmd_dns "$@" ;;
  update|att) cmd_update ;;
  uninstall) cmd_uninstall ;;
  menu|'')  cmd_menu ;;
  *) printf 'การใช้งาน: hy {render|health|add|list|del|passwd|setexp|expire|client|log|online|online-count|online-tsv|track|backup|restart|start|stop|status|nat|dns|update|uninstall|menu}\n' ;;
esac
