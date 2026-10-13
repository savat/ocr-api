#!/bin/sh
# ZIVPN manager  (ติดตั้งเป็นคำสั่ง: m)
# ผู้ใช้ = รหัสผ่านใน config.json (auth.mode = passwords)
# ข้อมูล: $ETC/manager.conf , $ETC/users.db , $ETC/config.json
# users.db รับทั้ง  name:pass:exp  (เก่า) และ  name|pass|exp|status  (มาตรฐาน)
# เรียกจาก install.sh:  m render | m health | m add | m expire | m nat up|down | m backup
VERSION="1.1.0"
ETC="${ZP_ETC:-/etc/zivpn}"
DRY="${ZP_DRY:-0}"
CONF="$ETC/manager.conf"
DB="$ETC/users.db"
CFG="$ETC/config.json"
UNIT=/etc/systemd/system

# อ่านค่าจาก manager.conf แบบปลอดภัย (ไม่ source เพราะ obfs มี backtick ได้)
conf() { [ -r "$CONF" ] && sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF" | head -n1; }
HOST=$(conf HOST); PORT=$(conf PORT); RANGE=$(conf RANGE); OBFS=$(conf OBFS); TRACK=$(conf TRACK)
SESS="$ETC/sessions"
PORT=${PORT:-5667}
OBFS=${OBFS:-zivpn}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  E=$(printf '\033'); R="$E[1;31m"; G="$E[1;32m"; Y="$E[1;33m"; C="$E[1;36m"; B="$E[1m"; D="$E[2m"; N="$E[0m"
else
  E=""; R=""; G=""; Y=""; C=""; B=""; D=""; N=""
fi
BAR="════════════════════════════════════════════════════"
ui_head() {
  printf '%s\n' "$BAR"
  printf '                 🚀 %sZIVPN MANAGER%s  %s%s%s\n' "$B" "$N" "$D" "v$VERSION" "$N"
  printf '%s\n' "$BAR"
}
ok()  { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
bad() { printf '  %s✘%s %s\n' "$R" "$N" "$*" >&2; }

jesc() { printf '%s' "$1" | sed 's/["\\]//g'; }
now()  { date +%s; }
dfmt() { [ -z "$1" ] || [ "$1" = 0 ] && { printf 'ไม่หมดอายุ'; return; }; date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$1"; }

# users.db รองรับ 2 รูปแบบ:  name:pass:exp  (เก่า) และ  name|pass|exp|status  (มาตรฐาน)
# normalize: ทำให้เป็น pipe format เดียวกันหมด ก่อนคำสั่งทุกตัว
db_normalize() {
  [ -f "$DB" ] || { : >"$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null; return 0; }
  [ -w "$DB" ] || return 0
  _tmp="$DB.norm.$$"; : >"$_tmp"
  while IFS= read -r _line || [ -n "$_line" ]; do
    [ -z "$_line" ] && continue
    case "$_line" in
      *\|*)
        IFS='|' read -r _nu _np _ne _ns <<EOF
$_line
EOF
        [ -z "$_nu" ] && continue
        [ -z "$_ns" ] && _ns=active
        printf '%s|%s|%s|%s\n' "$_nu" "${_np:-$_nu}" "${_ne:-0}" "$_ns" >>"$_tmp"
        ;;
      *)
        IFS=: read -r _nu _np _ne <<EOF
$_line
EOF
        [ -z "$_nu" ] && continue
        printf '%s|%s|%s|active\n' "$_nu" "${_np:-$_nu}" "${_ne:-0}" >>"$_tmp"
        ;;
    esac
  done < "$DB"
  if cmp -s "$DB" "$_tmp"; then
    rm -f "$_tmp"
  else
    chmod 600 "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$DB"
    chmod 600 "$DB" 2>/dev/null
  fi
}

# อ่าน 1 บรรทัด -> _nu _np _ne _ns (รองรับทั้ง : และ |)
db_parse() {
  _nu=""; _np=""; _ne=""; _ns=active
  case "$1" in
    *\|*)
      IFS='|' read -r _nu _np _ne _ns <<EOF
$1
EOF
      [ -z "$_ns" ] && _ns=active
      ;;
    *)
      IFS=: read -r _nu _np _ne <<EOF
$1
EOF
      ;;
  esac
}

db_has() {
  awk -F'|' -v u="$1" '$1==u{found=1} END{exit !found}' "$DB" 2>/dev/null
}

render() {
  [ "$DRY" = 1 ] && return 0
  _t=$(now); _plist=""
  if [ -r "$DB" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
      [ -z "$_line" ] && continue
      db_parse "$_line"
      [ -z "$_np" ] && continue
      [ "$_ns" != active ] && continue
      if [ -n "$_ne" ] && [ "$_ne" != 0 ] && [ "$_ne" -le "$_t" ] 2>/dev/null; then continue; fi
      _plist="$_plist\"$(jesc "$_np")\","
    done < "$DB"
  fi
  _plist=$(printf '%s' "$_plist" | sed 's/,$//')
  [ -z "$_plist" ] && _plist='"zi"'
  if [ "$TRACK" = on ] && [ -x "$ETC/auth.sh" ]; then
    _auth=$(printf '{\n    "mode": "command",\n    "command": "%s/auth.sh"\n  }' "$ETC")
  else
    _auth=$(printf '{\n    "mode": "passwords",\n    "config": [%s]\n  }' "$_plist")
  fi
  _new=$(printf '{\n  "listen": ":%s",\n  "cert": "%s/zivpn.crt",\n  "key": "%s/zivpn.key",\n  "obfs": "%s",\n  "auth": %s\n}' \
    "$PORT" "$ETC" "$ETC" "$(jesc "$OBFS")" "$_auth")
  [ -f "$CFG" ] && [ "$(cat "$CFG")" = "$_new" ] && return 0
  [ -f "$CFG" ] && cp -f "$CFG" "$CFG.bak" 2>/dev/null
  printf '%s\n' "$_new" > "$CFG.new" && chmod 600 "$CFG.new" && mv -f "$CFG.new" "$CFG"
  chmod 600 "$CFG" 2>/dev/null
}

reload() {
  [ "$DRY" = 1 ] && return 0
  systemctl restart zivpn.service >/dev/null 2>&1
  sleep 1
  if ! systemctl is-active --quiet zivpn.service; then
    bad "ZIVPN เริ่มใหม่ไม่ได้ - ย้อนกลับไปใช้ค่าเดิม"
    [ -f "$CFG.bak" ] && cp -f "$CFG.bak" "$CFG"
    systemctl restart zivpn.service >/dev/null 2>&1
    return 1
  fi
}

count() { [ -r "$DB" ] && grep -c . "$DB" 2>/dev/null || printf '0'; }

# ---- การดูผู้ใช้ออนไลน์ ----------------------------------------------------
# ZIVPN log ทุกการเชื่อมต่อเป็น id="user" เหมือนกันหมด (ไม่ใช่ชื่อบัญชี/รหัสผ่าน)
# จึงแยก "รายบัญชี" จาก log ไม่ได้ -> นับเป็น "อุปกรณ์ออนไลน์" ตาม IP ลูกค้าแทน
#  แหล่ง 1: conntrack  = flow UDP ที่ server ตอบกลับจากพอร์ต $PORT (รวม port hopping)
#  แหล่ง 2: journal    = บรรทัด log ของ zivpn ใน 2 นาทีล่าสุดที่มี addr
# ผลลัพธ์: ip<TAB>จำนวน flow
# เปิดการติดตาม conntrack (กฎนับเฉย ๆ ไม่มี target ไม่กระทบ firewall)
# เครื่องที่ไม่มี NAT/ufw จะไม่มี /proc/net/nf_conntrack จนกว่าจะมีกฎที่ใช้ conntrack
ensure_ct() {
  [ "$DRY" = 1 ] && return 0
  command -v iptables >/dev/null 2>&1 || return 0
  iptables -w -C INPUT -p udp --dport "$PORT" -m conntrack --ctstate NEW,ESTABLISHED 2>/dev/null && return 0
  modprobe nf_conntrack 2>/dev/null
  iptables -w -I INPUT -p udp --dport "$PORT" -m conntrack --ctstate NEW,ESTABLISHED 2>/dev/null
  return 0
}

ct_list() {
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
    END { for (k in n) printf "%s\t%d\n", k, n[k] }'
}

jr_list() {
  command -v journalctl >/dev/null 2>&1 || return 0
  journalctl -u zivpn.service --since "$(date -d '-2 min' '+%Y-%m-%d %H:%M:%S')" --no-pager -o cat 2>/dev/null \
    | sed -n 's/.*"addr"[ ]*:[ ]*"\([^"]*\)".*/\1/p' \
    | sed 's/:[0-9]*$//; s/^\[//; s/\]$//' | sort | uniq -c \
    | awk '{ printf "%s\t%d\n", $2, $1 }'
}

online_list() {
  { ct_list; jr_list; } | awk -F'\t' '
    NF>=2 { if (!($1 in n) || $2+0 > n[$1]) n[$1]=$2+0 }
    END { for (k in n) printf "%s\t%d\n", k, n[k] }' | sort
}

# ---- ติดตามรายบัญชี (m track on) -------------------------------------------
# ใช้โหมด auth แบบ command: zivpn เรียก auth.sh พร้อม addr + รหัสผ่านที่ลูกค้าพิมพ์
# สคริปต์ตรวจกับ users.db แล้วจดว่า addr นี้คือบัญชีไหนลง $SESS (epoch|addr|user)
write_auth() {
  cat >"$ETC/auth.sh" <<'AUTHEOF'
#!/bin/sh
# เรียกโดย zivpn:  auth.sh ADDR PASSWORD [sent recv]
ETC=/etc/zivpn
now=$(date +%s)
u=$(awk -F'|' -v p="$2" -v t="$now" '$2==p && ($4=="" || $4=="active") && ($3=="" || $3==0 || $3>t){print $1; exit}' "$ETC/users.db" 2>/dev/null)
[ -n "$u" ] || { echo invalid; exit 1; }
printf '%s|%s|%s\n' "$now" "$1" "$u" >>"$ETC/sessions"
echo "$u"
exit 0
AUTHEOF
  chmod 700 "$ETC/auth.sh"; : >>"$SESS"; chmod 600 "$SESS"
}

set_track() { # $1 = on|off
  if grep -q '^TRACK=' "$CONF" 2>/dev/null; then sed -i "s/^TRACK=.*/TRACK='$1'/" "$CONF"; else printf "TRACK='%s'\n" "$1" >>"$CONF"; fi
  TRACK=$1
}

cmd_track() {
  case "$1" in
    on)
      write_auth; set_track on; render
      if reload; then
        ok "เปิดการติดตามรายบัญชีแล้ว - ให้ลูกค้าเชื่อมต่อใหม่ แล้วดู: m online"
        printf '  %sถ้าลูกค้าเชื่อมต่อไม่ได้ ให้สั่ง: m track off%s\n' "$D" "$N"
      else
        set_track off; render; reload; bad "ZIVPN เริ่มด้วยโหมด command ไม่ได้ - ย้อนกลับแล้ว"; return 1
      fi ;;
    off) set_track off; render; reload && ok "ปิดการติดตามรายบัญชีแล้ว (กลับไปโหมดรหัสผ่าน)" ;;
    *)   printf '  การติดตามรายบัญชี: %s\n  ใช้: m track on | m track off\n' "${TRACK:-off}" ;;
  esac
}

_since() { # เวลาเริ่ม service รูปแบบ "YYYY-MM-DD HH:MM:SS" (เวลาท้องถิ่น) ใช้กับ journalctl --since
  _t=$(systemctl show -p ActiveEnterTimestamp zivpn.service 2>/dev/null | sed 's/^[^=]*=//')
  _s=$(printf '%s' "$_t" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+-[0-9]+-[0-9]+$/){print $i" "$(i+1); exit}}')
  [ -n "$_s" ] && printf '%s' "$_s" || date -d '-1 hour' '+%Y-%m-%d %H:%M:%S'
}

addr_events() { # addr (ip:port) ที่ connected แล้วยังไม่ disconnected
  command -v journalctl >/dev/null 2>&1 || return 0
  journalctl -u zivpn.service --since "$(_since)" --no-pager -o cat 2>/dev/null | awk '
    /client (connected|disconnected)/ {
      if (match($0, /"addr"[ ]*:[ ]*"[^"]*"/)) {
        t=substr($0,RSTART,RLENGTH); sub(/^"addr"[ ]*:[ ]*"/,"",t); sub(/"$/,"",t)
        if ($0 ~ /client connected/) c[t]=1; else delete c[t]
      }
    }
    END { for (k in c) print k }'
}

tracked_online() { # user<TAB>ip:port
  [ "$TRACK" = on ] && [ -s "$SESS" ] || return 0
  if [ -r /proc/net/nf_conntrack ] || command -v conntrack >/dev/null 2>&1; then
    _live=$(ct_list | cut -f1 | sort -u)
  else
    # ไม่มี conntrack -> ใช้ log ที่มี addr ใน 30 นาทีล่าสุด (ลูกค้าเงียบนานจะหลุดหลัง 30 นาที)
    _live=$(journalctl -u zivpn.service --since "30 minutes ago" --no-pager -o cat 2>/dev/null \
      | grep -oE '"addr"[ ]*:[ ]*"[^"]*"' | grep -oE '[0-9.]+:[0-9]+' | sed 's/:[0-9]*$//' | sort -u)
  fi
  addr_events | while read -r _a; do
    _ip=${_a%:*}
    printf '%s\n' "$_live" | grep -qxF "$_ip" || continue
    _u=$(awk -F'|' -v a="$_a" -v p="$_ip:" '$2==a{u=$3} index($2,p)==1{l=$3} END{print (u!="") ? u : l}' "$SESS")
    printf '%s\t%s\n' "${_u:-?}" "$_a"
  done
}

cmd_online_count() {
  ensure_ct
  _t=$(tracked_online)
  if [ -n "$_t" ]; then printf '%s\n' "$_t" | cut -f2 | sed 's/:[0-9]*$//' | sort -u | grep -c .; else online_list | grep -c .; fi
}

cmd_online_tsv() { # user<TAB>จำนวนเครื่อง(IP ไม่ซ้ำ)<TAB>IP (สำหรับ panel: ตัวกรองดูออนไลน์รายบัญชี)
  tracked_online | awk -F'\t' '{ split($2,a,":"); k=$1 SUBSEP a[1]; if (!(k in seen)) { seen[k]=1; n[$1]++; ip[$1]=a[1] } } END { for (u in n) printf "%s\t%d\t%s\n", u, n[u], ip[u] }' | sort
}

cmd_online() {
  ui_head
  ensure_ct
  _trk=$(tracked_online | sort)
  if [ -n "$_trk" ]; then
    printf '  %s%-18s %-6s %s%s\n' "$B" "USER" "CONN" "IP" "$N"
    printf '%s\n' "$_trk" | awk -F'\t' '{ n[$1]++; split($2,a,":"); ip[$1]=a[1] } END { for (u in n) printf "%s\t%d\t%s\n", u, n[u], ip[u] }' | sort \
      | while IFS="$(printf '\t')" read -r _u _c _ip; do printf '  %-18s %-6s %s\n' "$_u" "$_c" "$_ip"; done
    printf '  %sออนไลน์ %s บัญชี%s\n' "$D" "$(printf '%s\n' "$_trk" | cut -f1 | sort -u | grep -c .)" "$N"
    return 0
  fi
  _out=$(online_list)
  if [ -z "$_out" ]; then
    printf '  %sยังไม่มีอุปกรณ์ออนไลน์ในขณะนี้%s\n' "$D" "$N"
    if [ ! -r /proc/net/nf_conntrack ] && ! command -v conntrack >/dev/null 2>&1; then
      printf '  %s(เพิ่งเปิดการติดตาม - รอสักครู่แล้วลองใหม่; เครื่องที่เงียบอาจยังไม่ส่งแพ็กเก็ต)%s\n' "$D" "$N"
    fi
    return 0
  fi
  printf '  %s%-40s %s%s\n' "$B" "IP ลูกค้า" "FLOW" "$N"
  printf '%s\n' "$_out" | while IFS="$(printf '\t')" read -r _ip _c; do
    printf '  %-40s %s\n' "$_ip" "$_c"
  done
  printf '  %sออนไลน์ %s อุปกรณ์ (นับตาม IP)%s\n' "$D" "$(printf '%s\n' "$_out" | grep -c .)" "$N"
  printf '  %s* แยกรายบัญชีไม่ได้ - เปิดด้วย: m track on%s\n' "$D" "$N"
}

cmd_add() {
  _n=$1; _w=$2; _d=$3
  [ -z "$_n" ] && { printf 'ชื่อผู้ใช้: '; read -r _n; }
  [ -z "$_n" ] && { bad "ยกเลิก"; return 1; }
  if db_has "$_n"; then bad "มีผู้ใช้ $_n อยู่แล้ว"; return 1; fi
  [ -z "$_w" ] && { printf 'รหัสผ่าน (เว้นว่าง = ใช้ชื่อผู้ใช้): '; read -r _w; [ -z "$_w" ] && _w=$_n; }
  if [ -z "$_d" ]; then printf 'อายุ (วัน, 0 = ไม่หมดอายุ) [30]: '; read -r _d; [ -z "$_d" ] && _d=30; fi
  case $_d in *[!0-9]*) _d=30 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  printf '%s|%s|%s|active\n' "$_n" "$_w" "$_exp" >> "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "เพิ่มผู้ใช้ $_n (รหัส: $_w, หมดอายุ: $(dfmt "$_exp"))"
}

cmd_del() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้ที่จะลบ: '; read -r _n; }
  [ -z "$_n" ] && return 1
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  awk -F'|' -v n="$_n" '$1 != n' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "ลบผู้ใช้ $_n แล้ว"
}

cmd_passwd() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  printf 'รหัสผ่านใหม่: '; read -r _w
  [ -z "$_w" ] && { bad "ยกเลิก"; return 1; }
  awk -F'|' -v n="$_n" -v w="$_w" 'BEGIN{OFS="|"} $1==n{$2=w} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  render; reload; ok "เปลี่ยนรหัสผ่าน $_n แล้ว"
}

cmd_setexp() {
  _n=$1; _d=$2
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  if [ -z "$_d" ]; then printf 'อายุใหม่ (วัน, 0 = ไม่หมดอายุ): '; read -r _d; fi
  case $_d in ''|*[!0-9]*) bad "จำนวนวันไม่ถูกต้อง"; return 1 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  awk -F'|' -v n="$_n" -v e="$_exp" 'BEGIN{OFS="|"} $1==n{$3=e} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB" || { bad "บันทึกวันหมดอายุไม่สำเร็จ"; return 1; }
  chmod 600 "$DB" 2>/dev/null
  if render && reload; then ok "ตั้งอายุ $_n -> $(dfmt "$_exp")"; else bad "บันทึกแล้ว แต่โหลดบริการใหม่ไม่สำเร็จ"; return 1; fi
}

cmd_list() {
  ui_head
  if [ ! -s "$DB" ]; then printf '  %sยังไม่มีผู้ใช้งาน%s\n' "$D" "$N"; return; fi
  printf '  %s%-16s %-16s %-18s %s%s\n' "$B" "USER" "PASSWORD" "EXPIRE" "STATUS" "$N"
  while IFS='|' read -r _n _w _e _s; do
    [ -z "$_n" ] && continue
    _st="${G}ok${N}"
    if [ "$_s" != active ]; then _st="${Y}ปิด${N}"
    elif [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$(now)" ] 2>/dev/null; then _st="${R}หมดอายุ${N}"; fi
    printf '  %-16s %-16s %-18s %b\n' "$_n" "$_w" "$(dfmt "$_e")" "$_st"
  done < "$DB"
  printf '  %sรวม %s ผู้ใช้%s\n' "$D" "$(count)" "$N"
}

cmd_expire() {
  ensure_ct
  [ -f "$SESS" ] && [ "$(wc -l <"$SESS")" -gt 3000 ] && { tail -n 2000 "$SESS" >"$SESS.t" && mv -f "$SESS.t" "$SESS"; chmod 600 "$SESS"; }
  [ -r "$DB" ] || return 0
  _t=$(now); _tmp="$DB.$$"; _rm=0
  while IFS='|' read -r _n _w _e _s; do
    [ -z "$_n" ] && continue
    if [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$_t" ] 2>/dev/null; then _rm=$((_rm + 1)); continue; fi
    printf '%s|%s|%s|%s\n' "$_n" "$_w" "$_e" "${_s:-active}" >> "$_tmp"
  done < "$DB"
  if [ "$_rm" -gt 0 ]; then mv -f "$_tmp" "$DB"; chmod 600 "$DB" 2>/dev/null; render; reload; fi
  rm -f "$_tmp"
}

cmd_nat() {
  _act=$1
  [ -z "$RANGE" ] && return 0
  _if=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  [ -z "$_if" ] && _if=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  [ -z "$_if" ] && { bad "หาการ์ดเครือข่าย (default route) ไม่เจอ"; return 1; }
  case $_act in
    up)
      iptables -w -t nat -N ZIVPN_DNAT 2>/dev/null
      iptables -w -t nat -F ZIVPN_DNAT
      iptables -w -t nat -A ZIVPN_DNAT -p udp --dport "$RANGE" -j DNAT --to-destination ":$PORT" || return 1
      iptables -w -t nat -C PREROUTING -i "$_if" -p udp -j ZIVPN_DNAT 2>/dev/null || \
      iptables -w -t nat -A PREROUTING -i "$_if" -p udp -j ZIVPN_DNAT
      ;;
    down)
      while iptables -w -t nat -D PREROUTING -i "$_if" -p udp -j ZIVPN_DNAT 2>/dev/null; do :; done
      iptables -w -t nat -F ZIVPN_DNAT 2>/dev/null
      iptables -w -t nat -X ZIVPN_DNAT 2>/dev/null
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
  if command -v journalctl >/dev/null 2>&1; then
    printf '  %s•%s ออนไลน์    : %s\n' "$C" "$N" "$(online_list | grep -c .)"
  fi
  [ -n "$HOST" ] && printf '  %s•%s ที่อยู่      : %s\n' "$C" "$N" "$HOST"
}

cmd_uninstall() {
  systemctl disable --now zivpn.service zivpn-expire.timer zivpn-nat.service zivpn-udpgw.service >/dev/null 2>&1
  cmd_nat down >/dev/null 2>&1
  rm -f "$UNIT/zivpn.service" "$UNIT/zivpn-expire.service" "$UNIT/zivpn-expire.timer" "$UNIT/zivpn-nat.service" "$UNIT/zivpn-udpgw.service"
  systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$ETC" /usr/local/bin/zivpn
  ok "ถอนติดตั้ง ZIVPN แล้ว"
  rm -f "$0" 2>/dev/null
}

cmd_menu() {
  while :; do
    ui_head
    printf '  %s[01]%s 🚀 เพิ่มผู้ใช้งาน\n' "$C" "$N"
    printf '  %s[02]%s 🗑️  ลบผู้ใช้งาน\n' "$C" "$N"
    printf '  %s[03]%s 👥 ดูรายชื่อผู้ใช้\n' "$C" "$N"
    printf '  %s[04]%s 🟢 ดูผู้ใช้ออนไลน์\n' "$C" "$N"
    printf '  %s[05]%s 🔑 เปลี่ยนรหัสผ่าน\n' "$C" "$N"
    printf '  %s[06]%s 📅 ตั้งวันหมดอายุ\n' "$C" "$N"
    printf '  %s[07]%s 💚 สถานะบริการ\n' "$C" "$N"
    printf '  %s[08]%s 💾 สำรองข้อมูล\n' "$C" "$N"
    printf '  %s[09]%s 🔄 รีสตาร์ทบริการ\n' "$C" "$N"
    printf '  %s[00]%s ↩ กลับ\n' "$C" "$N"
    printf '%s\n' "$BAR"
    printf '  🔎 เลือกเมนู ? : '; read -r _x
    case $_x in
      1|01) cmd_add ;;
      2|02) cmd_del ;;
      3|03) cmd_list ;;
      4|04) cmd_online ;;
      5|05) cmd_passwd ;;
      6|06) cmd_setexp ;;
      7|07) cmd_health ;;
      8|08) cmd_backup ;;
      9|09) reload && ok "รีสตาร์ทแล้ว" ;;
      0|00) return ;;
      *) : ;;
    esac
    printf '\n  %sกด ENTER เพื่อกลับเมนู...%s' "$D" "$N"; read -r _dummy
  done
}

# ปรับ users.db ให้เป็นรูปแบบเดียว (pipe) ก่อนทุกคำสั่ง
[ "$DRY" = 1 ] || db_normalize

case "${1:-menu}" in
  render)   render ;;
  health)   cmd_health ;;
  add)      shift; cmd_add "$@" ;;
  list|ls)  cmd_list ;;
  online|on) cmd_online ;;
  online-count) cmd_online_count ;;
  online-tsv)   cmd_online_tsv ;;
  track)    shift; cmd_track "$@" ;;
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
  *) printf 'การใช้งาน: m {render|health|add|list|online|online-count|online-tsv|track|del|passwd|setexp|expire|nat up|down|backup|restart|start|stop|status|uninstall|menu}\n' ;;
esac
