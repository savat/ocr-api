#!/bin/sh
VERSION="1.2.0"
ETC="${ZP_ETC:-/etc/zivpn}"
DRY="${ZP_DRY:-0}"
CONF="$ETC/manager.conf"
DB="$ETC/users.db"
CFG="$ETC/config.json"
UNIT=/etc/systemd/system

conf() { [ -r "$CONF" ] && sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF" | head -n1; }
HOST=$(conf HOST); PORT=$(conf PORT); RANGE=$(conf RANGE); OBFS=$(conf OBFS); TRACK=$(conf TRACK); GRACE=$(conf GRACE)
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
  printf '            🚀 %sตัวจัดการ ZIVPN%s  %s(เวอร์ชัน %s)%s\n' "$B" "$N" "$D" "$VERSION" "$N"
  printf '%s\n' "$BAR"
}
ok()  { printf '  %s✅%s %s\n' "$G" "$N" "$*"; }
bad() { printf '  %s❌%s %s\n' "$R" "$N" "$*" >&2; }

jesc() { printf '%s' "$1" | sed 's/["\\]//g'; }
now()  { date +%s; }
dfmt() { [ -z "$1" ] || [ "$1" = 0 ] && { printf 'ไม่หมดอายุ'; return; }; date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$1"; }

db_normalize() {
  [ -f "$DB" ] || { : >"$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null; return 0; }
  [ -w "$DB" ] || return 0
  _tmp="$DB.norm.$$"; : >"$_tmp"
  while IFS= read -r _line || [ -n "$_line" ]; do
    [ -z "$_line" ] && continue
    case "$_line" in
      *\|*)
        IFS='|' read -r _nu _np _ne _ns _nl <<EOF
$_line
EOF
        [ -z "$_nu" ] && continue
        [ -z "$_ns" ] && _ns=active
        case $_nl in ''|*[!0-9]*) _nl=0 ;; esac
        printf '%s|%s|%s|%s|%s\n' "$_nu" "${_np:-$_nu}" "${_ne:-0}" "$_ns" "$_nl" >>"$_tmp"
        ;;
      *)
        IFS=: read -r _nu _np _ne <<EOF
$_line
EOF
        [ -z "$_nu" ] && continue
        printf '%s|%s|%s|active|0\n' "$_nu" "${_np:-$_nu}" "${_ne:-0}" >>"$_tmp"
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

db_parse() {
  _nu=""; _np=""; _ne=""; _ns=active; _nl=0
  case "$1" in
    *\|*)
      IFS='|' read -r _nu _np _ne _ns _nl <<EOF
$1
EOF
      [ -z "$_ns" ] && _ns=active
      case $_nl in ''|*[!0-9]*) _nl=0 ;; esac
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
    _auth=$(printf '{\n    "mode": "external",\n    "config": {\n      "cmd": "%s/auth.sh"\n    }\n  }' "$ETC")
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
    bad "ZIVPN เริ่มใหม่ไม่ได้ - ย้อนกลับไปใช้ค่าเดิมแล้ว ⏪"
    [ -f "$CFG.bak" ] && cp -f "$CFG.bak" "$CFG"
    systemctl restart zivpn.service >/dev/null 2>&1
    return 1
  fi
}

count() { [ -r "$DB" ] && grep -c . "$DB" 2>/dev/null || printf '0'; }

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

write_auth() {
  cat >"$ETC/auth.sh" <<'AUTHEOF'
#!/bin/sh
AUTHV=5
ETC=${ZP_ETC:-/etc/zivpn}
now=$(date +%s)
u=$(awk -F'|' -v p="$2" -v t="$now" '$2==p && ($4=="" || $4=="active") && ($3=="" || $3==0 || $3>t){print $1; exit}' "$ETC/users.db" 2>/dev/null)
[ -n "$u" ] || { echo invalid; exit 1; }
ip=${1%:*}; ip=${ip#[}; ip=${ip%]}
if [ -s "$ETC/blocked" ] && awk -F'|' -v u="$u" -v i="$ip" -v t="$now" '$2==u && $3==i && $1>t{f=1} END{exit !f}' "$ETC/blocked"; then
  echo invalid; exit 1
fi
printf '%s|%s|%s|%s|%s\n' "$now" "$1" "$u" "$3" "$4" >>"$ETC/sessions"
echo "$u"
exit 0
AUTHEOF
  chmod 700 "$ETC/auth.sh"; : >>"$SESS"; chmod 600 "$SESS"
}

set_track() {
  if grep -q '^TRACK=' "$CONF" 2>/dev/null; then sed -i "s/^TRACK=.*/TRACK='$1'/" "$CONF"; else printf "TRACK='%s'\n" "$1" >>"$CONF"; fi
  TRACK=$1
}

cmd_track() {
  case "$1" in
    on)
      write_auth; set_track on; render
      if reload; then
        limiter_units on
        ok "🔎 เปิดการติดตามรายบัญชีแล้ว - ให้ลูกค้าเชื่อมต่อใหม่ แล้วดู: m online"
        printf '  %s💡 ถ้าลูกค้าเชื่อมต่อไม่ได้ ให้สั่ง: m track off%s\n' "$D" "$N"
      else
        set_track off; render; reload; bad "ZIVPN เริ่มด้วยโหมดติดตามผู้ใช้ไม่ได้ - ย้อนกลับแล้ว"; return 1
      fi ;;
    off) set_track off; limiter_units off; render; reload && ok "🔕 ปิดการติดตามรายบัญชีแล้ว (กลับไปโหมดรหัสผ่าน)"
         awk -F'|' '$5+0>0{f=1} END{exit !f}' "$DB" 2>/dev/null && printf '  %s⚠️  ตอนนี้ระบบจำกัดเครื่องจะไม่ทำงาน (เปิดใหม่ด้วย: m track on)%s\n' "$Y" "$N" ;;
    *)   printf '  🔎 การติดตามรายบัญชี: %s\n  ใช้: m track on (เปิด) | m track off (ปิด)\n' "${TRACK:-off}" ;;
  esac
}

_since() {
  _t=$(systemctl show -p ActiveEnterTimestamp zivpn.service 2>/dev/null | sed 's/^[^=]*=//')
  _s=$(printf '%s' "$_t" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+-[0-9]+-[0-9]+$/){print $i" "$(i+1); exit}}')
  [ -n "$_s" ] && printf '%s' "$_s" || date -d '-1 hour' '+%Y-%m-%d %H:%M:%S'
}

addr_events() {
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

tracked_online() {
  [ "$TRACK" = on ] && [ -s "$SESS" ] || return 0
  if [ -r /proc/net/nf_conntrack ] || command -v conntrack >/dev/null 2>&1; then
    _live=$(ct_list | cut -f1 | sort -u)
  else
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

cmd_online_tsv() {
  tracked_online | awk -F'\t' '{ split($2,a,":"); k=$1 SUBSEP a[1]; if (!(k in seen)) { seen[k]=1; n[$1]++; ip[$1]=a[1] } } END { for (u in n) printf "%s\t%d\t%s\n", u, n[u], ip[u] }' | sort
}

cmd_online() {
  ui_head
  ensure_ct
  _trk=$(tracked_online | sort)
  if [ -n "$_trk" ]; then
    printf '  %sผู้ใช้                 การเชื่อมต่อ  ไอพี%s\n' "$B" "$N"
    printf '%s\n' "$_trk" | awk -F'\t' '{ n[$1]++; split($2,a,":"); ip[$1]=a[1] } END { for (u in n) printf "%s\t%d\t%s\n", u, n[u], ip[u] }' | sort \
      | while IFS="$(printf '\t')" read -r _u _c _ip; do printf '  %-18s %-12s %s\n' "$_u" "$_c" "$_ip"; done
    printf '  %s🟢 ออนไลน์ %s บัญชี%s\n' "$D" "$(printf '%s\n' "$_trk" | cut -f1 | sort -u | grep -c .)" "$N"
    return 0
  fi
  _out=$(online_list)
  if [ -z "$_out" ]; then
    printf '  %s😴 ยังไม่มีอุปกรณ์ออนไลน์ในขณะนี้%s\n' "$D" "$N"
    if [ ! -r /proc/net/nf_conntrack ] && ! command -v conntrack >/dev/null 2>&1; then
      printf '  %s(เพิ่งเปิดการติดตาม - รอสักครู่แล้วลองใหม่; เครื่องที่เงียบอาจยังไม่ส่งแพ็กเก็ต)%s\n' "$D" "$N"
    fi
    return 0
  fi
  printf '  %sไอพีลูกค้า                                 การเชื่อมต่อ%s\n' "$B" "$N"
  printf '%s\n' "$_out" | while IFS="$(printf '\t')" read -r _ip _c; do
    printf '  %-40s %s\n' "$_ip" "$_c"
  done
  printf '  %s🟢 ออนไลน์ %s อุปกรณ์ (นับตามไอพี)%s\n' "$D" "$(printf '%s\n' "$_out" | grep -c .)" "$N"
  printf '  %s💡 แยกรายบัญชีไม่ได้ - เปิดด้วย: m track on%s\n' "$D" "$N"
}

lim_text() { if [ "${1:-0}" -gt 0 ] 2>/dev/null; then printf '%s เครื่อง' "$1"; else printf 'ไม่จำกัด'; fi; }

cmd_add() {
  _n=$1; _w=$2; _d=$3; _l=$4
  [ -z "$_n" ] && { printf '👤 ชื่อผู้ใช้: '; read -r _n; }
  [ -z "$_n" ] && { bad "ยกเลิก"; return 1; }
  if db_has "$_n"; then bad "มีผู้ใช้ $_n อยู่แล้ว"; return 1; fi
  [ -z "$_w" ] && { printf '🔑 รหัสผ่าน (เว้นว่าง = ใช้ชื่อผู้ใช้): '; read -r _w; [ -z "$_w" ] && _w=$_n; }
  if [ -z "$_d" ]; then printf '📅 อายุ (วัน, 0 = ไม่หมดอายุ) [30]: '; read -r _d; [ -z "$_d" ] && _d=30; fi
  case $_d in *[!0-9]*) _d=30 ;; esac
  if [ -z "$_l" ]; then
    if [ -t 0 ]; then printf '📱 จำกัดจำนวนเครื่อง (0 = ไม่จำกัด) [0]: '; read -r _l; [ -z "$_l" ] && _l=0; else _l=0; fi
  fi
  case $_l in ''|*[!0-9]*) _l=0 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  printf '%s|%s|%s|active|%s\n' "$_n" "$_w" "$_exp" "$_l" >> "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  [ "$_l" -gt 0 ] && [ "$TRACK" != on ] && printf '  %s⚠️  บันทึกค่าจำกัดแล้ว แต่ยังไม่บังคับใช้ (การติดตามผู้ใช้ปิดอยู่ - เปิดด้วย: m track on)%s\n' "$Y" "$N"
  ok "➕ เพิ่มผู้ใช้ $_n แล้ว (รหัสผ่าน: $_w, หมดอายุ: $(dfmt "$_exp"), จำกัด: $(lim_text "$_l"))"
}

cmd_del() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf '🗑️  ชื่อผู้ใช้ที่จะลบ: '; read -r _n; }
  [ -z "$_n" ] && return 1
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  awk -F'|' -v n="$_n" '$1 != n' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "🗑️  ลบผู้ใช้ $_n แล้ว"
}

cmd_passwd() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  printf '🔑 รหัสผ่านใหม่: '; read -r _w
  [ -z "$_w" ] && { bad "ยกเลิก"; return 1; }
  awk -F'|' -v n="$_n" -v w="$_w" 'BEGIN{OFS="|"} $1==n{$2=w} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB"
  render; reload; ok "🔑 เปลี่ยนรหัสผ่าน $_n แล้ว"
}

cmd_setexp() {
  _n=$1; _d=$2
  [ -z "$_n" ] && { cmd_list; printf 'ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  if [ -z "$_d" ]; then printf '📅 อายุใหม่ (วัน, 0 = ไม่หมดอายุ): '; read -r _d; fi
  case $_d in ''|*[!0-9]*) bad "จำนวนวันไม่ถูกต้อง"; return 1 ;; esac
  _exp=0; [ "$_d" -gt 0 ] && _exp=$(( $(now) + _d * 86400 ))
  awk -F'|' -v n="$_n" -v e="$_exp" 'BEGIN{OFS="|"} $1==n{$3=e} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB" || { bad "บันทึกวันหมดอายุไม่สำเร็จ"; return 1; }
  chmod 600 "$DB" 2>/dev/null
  if render && reload; then ok "📅 ตั้งวันหมดอายุ $_n เป็น $(dfmt "$_exp") แล้ว"; else bad "บันทึกแล้ว แต่โหลดบริการใหม่ไม่สำเร็จ"; return 1; fi
}

fw() {
  [ "$DRY" = 1 ] && return 0
  command -v iptables >/dev/null 2>&1 || return 0
  iptables -w "$@" 2>/dev/null
}

ct_live() {
  _ct=${ZP_CT:-/proc/net/nf_conntrack}
  if [ -r "$_ct" ]; then cat "$_ct" 2>/dev/null
  elif command -v conntrack >/dev/null 2>&1; then conntrack -L -p udp 2>/dev/null
  else return 0; fi | awk -v P="$PORT" -v MIN="$1" -v MAX="$2" '
    /(^| )udp / && !/UNREPLIED/ {
      ip=""; c=0; sp=""; rp=""; rem=-1
      for (i=1;i<=NF;i++) {
        if ($i=="udp" && rem<0) rem=$(i+2)+0
        if ($i ~ /^src=/ && ip=="") ip=substr($i,5)
        if ($i ~ /^sport=/) { c++; if (c==1) sp=substr($i,7); if (c==2) rp=substr($i,7) }
      }
      if (rp==P && ip!="" && ip!="127.0.0.1" && rem>=MIN && rem<=MAX) print ip ":" sp
    }'
}

limiter_kill() {
  _kip=${1%:*}; _kport=${1##*:}
  fw -I INPUT 1 -p udp -s "$_kip" --sport "$_kport" --dport "$PORT" -m comment --comment zivpn-kill -j DROP
  printf '%s|%s|%s\n' "$(( $2 + 120 ))" "$_kip" "$_kport" >>"$ETC/kills"
}

limiter_unkill() {
  [ -s "$ETC/kills" ] || return 0
  _kt="$ETC/kills.$$"; : >"$_kt"
  while IFS='|' read -r _ku _kip _kport; do
    [ -z "$_ku" ] && continue
    if [ "$_ku" -le "$1" ] 2>/dev/null; then
      fw -D INPUT -p udp -s "$_kip" --sport "$_kport" --dport "$PORT" -m comment --comment zivpn-kill -j DROP
    else
      printf '%s|%s|%s\n' "$_ku" "$_kip" "$_kport" >>"$_kt"
    fi
  done <"$ETC/kills"
  mv -f "$_kt" "$ETC/kills"
}

limiter_units() {
  [ "$DRY" = 1 ] && return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  case "$1" in
    on)
      cat >"$UNIT/zivpn-limiter.service" <<EOF
[Unit]
Description=ZIVPN - device limit check

[Service]
Type=oneshot
ExecStart=${ZP_SELF:-/usr/local/bin/m} limiter
EOF
      cat >"$UNIT/zivpn-limiter.timer" <<EOF
[Unit]
Description=ZIVPN - device limit check every 15 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=15s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
      systemctl daemon-reload >/dev/null 2>&1
      systemctl enable --now zivpn-limiter.timer >/dev/null 2>&1 ;;
    off)
      systemctl disable --now zivpn-limiter.timer >/dev/null 2>&1
      limiter_unkill 99999999999
      rm -f "$ETC/blocked" "$ETC/limiter.state" "$ETC/kills" ;;
  esac
}

cmd_limiter() {
  [ "$TRACK" = on ] || return 0
  [ -s "$SESS" ] || return 0
  _now=$(now); _LS="$ETC/limiter.state"; _BL="$ETC/blocked"; _LG="$ETC/limiter.log"
  limiter_unkill "$_now"
  if [ -s "$_BL" ]; then awk -F'|' -v t="$_now" '$1>t' "$_BL" >"$_BL.$$"; mv -f "$_BL.$$" "$_BL"; fi
  _TO=$(cat /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream 2>/dev/null)
  case $_TO in ''|*[!0-9]*) _TO=120 ;; esac
  _g=${GRACE:-30}; _MIN=$(( _TO - _g )); [ "$_MIN" -lt 1 ] && _MIN=1
  _live="$ETC/.live.$$"; _join="$ETC/.join.$$"; _ns="$ETC/.state.$$"; : >"$_ns"
  ct_live "$_MIN" "$_TO" >"$_live"
  if [ ! -s "$_live" ]; then rm -f "$_live" "$_join" "$_ns"; : >"$_LS"; return 0; fi
  awk -F'|' 'NR==FNR{live[$0]=1; next} ($2 in live){u[$2]=$3; t[$2]=$1} END{for(a in u){ip=a; sub(/:[0-9]*$/,"",ip); print u[a] "|" ip "|" a "|" t[a]}}' "$_live" "$SESS" >"$_join"
  awk -F'|' '$5+0>0 && ($4=="" || $4=="active"){print $1 "|" $5}' "$DB" | while IFS='|' read -r _u _lim; do
    _ips=$(awk -F'|' -v u="$_u" '$1==u{ if(!($2 in f) || $4<f[$2]) f[$2]=$4 } END{for(i in f) print f[i] "|" i}' "$_join" | sort -t'|' -k1,1n)
    [ -n "$_ips" ] || continue
    _cnt=$(printf '%s\n' "$_ips" | grep -c .)
    [ "$_cnt" -gt "$_lim" ] || continue
    _c=$(awk -F'|' -v u="$_u" '$1==u{print $2; exit}' "$_LS" 2>/dev/null); _c=$(( ${_c:-0} + 1 ))
    if [ "$_c" -lt "${LIMIT_STRIKES:-4}" ]; then printf '%s|%s\n' "$_u" "$_c" >>"$_ns"; continue; fi
    printf '%s\n' "$_ips" | tail -n +$(( _lim + 1 )) | while IFS='|' read -r _ft _eip; do
      [ -z "$_eip" ] && continue
      printf '%s|%s|%s\n' "$(( _now + 900 ))" "$_u" "$_eip" >>"$_BL"
      awk -F'|' -v u="$_u" -v i="$_eip" '$1==u && $2==i{print $3}' "$_join" | while read -r _a; do
        limiter_kill "$_a" "$_now"
      done
      printf '%s|ตัดการเชื่อมต่อ|%s|%s\n' "$_now" "$_u" "$_eip" >>"$_LG"
    done
  done
  mv -f "$_ns" "$_LS"; rm -f "$_live" "$_join"
  [ -f "$_LG" ] && [ "$(wc -l <"$_LG")" -gt 600 ] && { tail -n 300 "$_LG" >"$_LG.t" && mv -f "$_LG.t" "$_LG"; }
  return 0
}

cmd_fp() {
  if [ ! -s "$SESS" ]; then printf '  📭 ยังไม่มีข้อมูล (ต้องเปิด m track on และให้ลูกค้าเชื่อมต่อก่อน)\n'; return 0; fi
  printf '  %sผู้ใช้              ไอพี               อัป/ดาวน์ที่แอปประกาศ (Mbps)   ครั้ง%s\n' "$B" "$N"
  tail -n 2000 "$SESS" | awk -F'|' 'NF>=5 && $3!="" { a=$2; sub(/:[0-9]*$/,"",a); k=$3 "|" a "|" $4 "|" $5; n[k]++ } END { for (k in n) print k "|" n[k] }' | sort | awk -F'|' '{ printf "  %-16s %-18s %9.1f / %-9.1f %8d\n", $1, $2, $3/125000, $4/125000, $5 }'
  printf '  %s💡 ถ้า 2 เครื่องของบัญชีเดียวกันมีค่าอัป/ดาวน์ต่างกัน ใช้เป็นลายนิ้วมือเครื่องได้%s\n' "$D" "$N"
}

cmd_grace() {
  _g=$1
  if [ -z "$_g" ]; then
    printf '  ⏱️  เวลาผ่อนผันตอนนี้: %s วินาที\n' "${GRACE:-30}"
    printf '  ตั้งใหม่ (5-300 วินาที): '; read -r _g
  fi
  case $_g in ''|*[!0-9]*) bad "ค่าไม่ถูกต้อง"; return 1 ;; esac
  if [ "$_g" -lt 5 ] || [ "$_g" -gt 300 ]; then bad "ต้องอยู่ระหว่าง 5-300 วินาที"; return 1; fi
  if grep -q '^GRACE=' "$CONF" 2>/dev/null; then sed -i "s/^GRACE=.*/GRACE='$_g'/" "$CONF"; else printf "GRACE='%s'\n" "$_g" >>"$CONF"; fi
  GRACE=$_g
  ok "⏱️  ตั้งเวลาผ่อนผันเป็น $_g วินาทีแล้ว (เครื่องเดิมที่เงียบเกินเวลานี้จะไม่นับเป็นเครื่องที่ใช้อยู่)"
}

cmd_setlimit() {
  _n=$1; _l=$2
  [ -z "$_n" ] && { cmd_list; printf '👤 ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  if [ -z "$_l" ]; then printf '📱 จำนวนเครื่องที่ใช้ได้พร้อมกัน (0 = ไม่จำกัด): '; read -r _l; fi
  case $_l in ''|*[!0-9]*) bad "จำนวนเครื่องไม่ถูกต้อง"; return 1 ;; esac
  awk -F'|' -v n="$_n" -v l="$_l" 'BEGIN{OFS="|"} $1==n{$5=l} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB" || { bad "บันทึกไม่สำเร็จ"; return 1; }
  chmod 600 "$DB" 2>/dev/null
  ok "📱 ตั้งจำกัดเครื่องของ $_n เป็น $(lim_text "$_l") แล้ว"
  [ "$_l" -gt 0 ] && [ "$TRACK" != on ] && printf '  %s⚠️  ยังไม่บังคับใช้ เพราะการติดตามผู้ใช้ปิดอยู่ (เปิดด้วย: m track on)%s\n' "$Y" "$N"
}

cmd_list() {
  ui_head
  if [ ! -s "$DB" ]; then printf '  %s📭 ยังไม่มีผู้ใช้งาน%s\n' "$D" "$N"; return; fi
  printf '  %sผู้ใช้              รหัสผ่าน           หมดอายุ             เครื่อง     สถานะ%s\n' "$B" "$N"
  while IFS='|' read -r _n _w _e _s _l; do
    [ -z "$_n" ] && continue
    _st="${G}ใช้งาน${N}"
    if [ "$_s" != active ]; then _st="${Y}ปิดใช้งาน${N}"
    elif [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$(now)" ] 2>/dev/null; then _st="${R}หมดอายุ${N}"; fi
    _ed=$(dfmt "$_e"); case $_ed in ไม่หมดอายุ) _ed="$_ed          " ;; *) _ed="$_ed  " ;; esac
    case $_l in ''|0|*[!0-9]*) _ld="ไม่จำกัด   " ;; *) _ld=$(printf '%-9s' "$_l") ;; esac
    printf '  %-16s %-16s %s %s %b\n' "$_n" "$_w" "$_ed" "$_ld" "$_st"
  done < "$DB"
  printf '  %s👥 รวม %s ผู้ใช้%s\n' "$D" "$(count)" "$N"
}

cmd_expire() {
  ensure_ct
  [ -f "$SESS" ] && [ "$(wc -l <"$SESS")" -gt 3000 ] && { tail -n 2000 "$SESS" >"$SESS.t" && mv -f "$SESS.t" "$SESS"; chmod 600 "$SESS"; }
  [ -r "$DB" ] || return 0
  _t=$(now); _tmp="$DB.$$"; _rm=0
  while IFS='|' read -r _n _w _e _s _l; do
    [ -z "$_n" ] && continue
    if [ -n "$_e" ] && [ "$_e" != 0 ] && [ "$_e" -lt "$_t" ] 2>/dev/null; then _rm=$((_rm + 1)); continue; fi
    printf '%s|%s|%s|%s|%s\n' "$_n" "$_w" "$_e" "${_s:-active}" "${_l:-0}" >> "$_tmp"
  done < "$DB"
  if [ "$_rm" -gt 0 ]; then mv -f "$_tmp" "$DB"; chmod 600 "$DB" 2>/dev/null; render; reload; fi
  rm -f "$_tmp"
}

cmd_nat() {
  _act=$1
  [ -z "$RANGE" ] && return 0
  _if=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  [ -z "$_if" ] && _if=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  [ -z "$_if" ] && { bad "🌐 หาการ์ดเครือข่าย (เส้นทางเริ่มต้น) ไม่เจอ"; return 1; }
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
    ok "💾 สำรองข้อมูลแล้ว: $_f"
  else
    bad "สำรองข้อมูลไม่สำเร็จ"
    return 1
  fi
}

cmd_health() {
  _st=$(systemctl is-active zivpn.service 2>/dev/null); [ -z "$_st" ] && _st="ไม่ทราบสถานะ"
  [ "$_st" = active ] && _stt="ทำงานอยู่" || _stt="$_st"
  printf '  💚 บริการ zivpn : %b%s%b\n' "$([ "$_st" = active ] && printf '%s' "$G" || printf '%s' "$R")" "$_stt" "$N"
  printf '  🔌 พอร์ต UDP : %s/udp\n' "$PORT"
  [ -n "$RANGE" ] && printf '  🔀 สลับพอร์ต (hopping) : %s -> %s\n' "$RANGE" "$PORT"
  printf '  🔒 รหัสอำพราง (Obfs) : %s\n' "$OBFS"
  _ug=$(systemctl is-active zivpn-udpgw.service 2>/dev/null)
  if [ "$_ug" = active ]; then _ugt="ทำงานอยู่"; _ugc=$G
  elif command -v ss >/dev/null 2>&1 && ss -lntH 2>/dev/null | grep -E '[:.]7300[[:space:]]' >/dev/null; then _ugt="ทำงานอยู่ (โดยบริการอื่น)"; _ugc=$G
  else _ugt="ไม่ทำงาน"; _ugc=$R; fi
  printf '  🎮 udpgw พอร์ต 7300 : %b%s%b\n' "$_ugc" "$_ugt" "$N"
  printf '  👥 ผู้ใช้ทั้งหมด : %s\n' "$(count)"
  if command -v journalctl >/dev/null 2>&1; then
    printf '  🟢 ออนไลน์ : %s\n' "$(online_list | grep -c .)"
  fi
  [ -n "$HOST" ] && printf '  🌐 ที่อยู่เซิร์ฟเวอร์ : %s\n' "$HOST"
}

cmd_uninstall() {
  systemctl disable --now zivpn.service zivpn-expire.timer zivpn-limiter.timer zivpn-nat.service zivpn-udpgw.service >/dev/null 2>&1
  limiter_unkill 99999999999
  cmd_nat down >/dev/null 2>&1
  rm -f "$UNIT/zivpn.service" "$UNIT/zivpn-expire.service" "$UNIT/zivpn-expire.timer" "$UNIT/zivpn-limiter.service" "$UNIT/zivpn-limiter.timer" "$UNIT/zivpn-nat.service" "$UNIT/zivpn-udpgw.service"
  systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$ETC" /usr/local/bin/zivpn
  ok "🧹 ถอนติดตั้ง ZIVPN แล้ว"
  rm -f "$0" 2>/dev/null
}

pause() { printf '\n  %s↵ กด ENTER เพื่อกลับ...%s' "$D" "$N"; read -r _dummy; }

rule() { printf '%s%s%s\n' "$D" "──────────────────────────────────────────────────" "$N"; }

status_bar() {
  _sv=$(systemctl is-active zivpn.service 2>/dev/null)
  if [ "$_sv" = active ]; then _svt="${G}ทำงาน${N}"; else _svt="${R}หยุด${N}"; fi
  if [ "$TRACK" = on ]; then _tk="${G}เปิด${N}"; else _tk="${R}ปิด${N}"; fi
  printf '  💚 บริการ: %b    👥 ผู้ใช้: %s    🔎 ติดตาม: %b\n' "$_svt" "$(count)" "$_tk"
  rule
}

item() { printf '  %s[%s]%s %s\n' "$C" "$1" "$N" "$2"; [ -n "$3" ] && printf '      %s%s%s\n' "$D" "$3" "$N"; }

cmd_renew() {
  _n=$1; _d=$2
  [ -z "$_n" ] && { cmd_list; printf '👤 ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  _cur=$(awk -F'|' -v n="$_n" '$1==n{print $3; exit}' "$DB")
  case $_cur in ''|*[!0-9]*) _cur=0 ;; esac
  [ "$_cur" = 0 ] && { printf '  ℹ️  บัญชี %s ไม่มีวันหมดอายุอยู่แล้ว (ถ้าอยากกำหนดวัน ใช้ ตั้งวันหมดอายุ)\n' "$_n"; return 0; }
  if [ -z "$_d" ]; then printf '➕ ต่ออายุเพิ่มกี่วัน: '; read -r _d; fi
  case $_d in ''|*[!0-9]*|0) bad "จำนวนวันไม่ถูกต้อง"; return 1 ;; esac
  _t=$(now); _base=$_cur; [ "$_cur" -le "$_t" ] && _base=$_t
  _exp=$(( _base + _d * 86400 ))
  awk -F'|' -v n="$_n" -v e="$_exp" 'BEGIN{OFS="|"} $1==n{$3=e} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB" || { bad "บันทึกไม่สำเร็จ"; return 1; }
  chmod 600 "$DB" 2>/dev/null
  render; reload
  ok "➕ ต่ออายุ $_n เพิ่ม $_d วัน - หมดอายุใหม่: $(dfmt "$_exp")"
}

cmd_toggle() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf '👤 ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  _s=$(awk -F'|' -v n="$_n" '$1==n{print $4; exit}' "$DB")
  if [ -z "$_s" ] || [ "$_s" = active ]; then _new=disabled; else _new=active; fi
  awk -F'|' -v n="$_n" -v s="$_new" 'BEGIN{OFS="|"} $1==n{$4=s} {print}' "$DB" > "$DB.$$" && mv -f "$DB.$$" "$DB" || { bad "บันทึกไม่สำเร็จ"; return 1; }
  chmod 600 "$DB" 2>/dev/null
  render; reload
  if [ "$_new" = active ]; then ok "▶️  เปิดบัญชี $_n แล้ว"; else ok "⏸️  ปิดบัญชี $_n แล้ว (เชื่อมต่อใหม่ไม่ได้)"; fi
}

cmd_detail() {
  _n=$1
  [ -z "$_n" ] && { cmd_list; printf '👤 ชื่อผู้ใช้: '; read -r _n; }
  db_has "$_n" || { bad "ไม่พบผู้ใช้ $_n"; return 1; }
  IFS='|' read -r _u _w _e _s _l <<EOF
$(awk -F'|' -v n="$_n" '$1==n{print; exit}' "$DB")
EOF
  case $_e in ''|*[!0-9]*) _e=0 ;; esac
  case $_l in ''|*[!0-9]*) _l=0 ;; esac
  [ -z "$_s" ] && _s=active
  rule
  printf '  👤 ชื่อผู้ใช้      : %s\n' "$_u"
  printf '  🔑 รหัสผ่าน       : %s\n' "$_w"
  if [ "$_e" = 0 ]; then printf '  📅 หมดอายุ        : ไม่หมดอายุ\n'
  else
    _left=$(( (_e - $(now)) / 86400 ))
    printf '  📅 หมดอายุ        : %s (เหลือ %s วัน)\n' "$(dfmt "$_e")" "$_left"
  fi
  printf '  📱 จำกัดเครื่อง    : %s\n' "$(lim_text "$_l")"
  if [ "$_s" = active ]; then printf '  🔘 สถานะ          : %sใช้งาน%s\n' "$G" "$N"; else printf '  🔘 สถานะ          : %sปิดใช้งาน%s\n' "$Y" "$N"; fi
  if [ -s "$SESS" ]; then
    _ipn=$(awk -F'|' -v n="$_u" -v t="$(( $(now) - 86400 ))" '$3==n && $1>=t{a=$2; sub(/:[0-9]*$/,"",a); s[a]=1} END{c=0; for(k in s) c++; print c}' "$SESS")
    printf '  🌐 IP ที่ใช้ใน 24 ชม.: %s\n' "${_ipn:-0}"
    printf '  %s🕒 เชื่อมต่อล่าสุด:%s\n' "$B" "$N"
    awk -F'|' -v n="$_u" '$3==n{print $1 "|" $2}' "$SESS" | tail -n 5 | while IFS='|' read -r _ts _ad; do
      printf '      %s  %s\n' "$(dfmt "$_ts")" "$_ad"
    done
  else
    printf '  %s(ยังไม่มีประวัติการเชื่อมต่อ - ต้องเปิดการติดตามผู้ใช้)%s\n' "$D" "$N"
  fi
  rule
}

cmd_blocked() {
  _t=$(now)
  printf '  %s🚫 ที่ถูกบล็อกอยู่ตอนนี้%s\n' "$B" "$N"
  if [ -s "$ETC/blocked" ] && [ -n "$(awk -F'|' -v t="$_t" '$1>t' "$ETC/blocked")" ]; then
    awk -F'|' -v t="$_t" '$1>t{ printf "      %-16s %-18s อีก %d นาที\n", $2, $3, ($1 - t) / 60 + 1 }' "$ETC/blocked"
  else
    printf '      ✅ ไม่มี\n'
  fi
  printf '  %s📜 ประวัติการตัดล่าสุด%s\n' "$B" "$N"
  if [ -s "$ETC/limiter.log" ]; then
    tail -n 10 "$ETC/limiter.log" | while IFS='|' read -r _lt _la _lu _li; do
      printf '      %s  %s  %s\n' "$(dfmt "$_lt")" "$_lu" "$_li"
    done
  else
    printf '      ✅ ยังไม่เคยมีการตัด\n'
  fi
}

cmd_unblock() {
  _n=$1
  if [ ! -s "$ETC/blocked" ]; then printf '  ✅ ไม่มีรายการที่ถูกบล็อก\n'; return 0; fi
  if [ -z "$_n" ]; then
    cmd_blocked
    printf '  ชื่อผู้ใช้ที่จะปลดบล็อก (พิมพ์ all = ทั้งหมด, เว้นว่าง = ยกเลิก): '; read -r _n
  fi
  [ -z "$_n" ] && return 1
  if [ "$_n" = all ]; then : >"$ETC/blocked"
  else awk -F'|' -v n="$_n" '$2!=n' "$ETC/blocked" >"$ETC/blocked.$$" && mv -f "$ETC/blocked.$$" "$ETC/blocked"; fi
  limiter_unkill 99999999999
  rm -f "$ETC/limiter.state"
  ok "🔓 ปลดบล็อก $_n แล้ว"
}

cmd_logs() {
  command -v journalctl >/dev/null 2>&1 || { bad "ไม่พบ journalctl"; return 1; }
  journalctl -u zivpn.service -n 25 --no-pager -o cat 2>/dev/null | cut -c1-160
}

cmd_info() {
  rule
  printf '  %s📋 ข้อมูลสำหรับตั้งค่าแอป ZIVPN%s\n' "$B" "$N"
  rule
  printf '  🌐 เซิร์ฟเวอร์ (Server) : %s\n' "${HOST:-ไม่ระบุ}"
  printf '  🔌 พอร์ต              : %s\n' "$PORT"
  [ -n "$RANGE" ] && printf '  🔀 ช่วงพอร์ต (hopping) : %s-%s\n' "${RANGE%:*}" "${RANGE#*:}"
  printf '  🔒 รหัสอำพราง (Obfs)   : %s\n' "$OBFS"
  printf '  🔑 รหัสผ่าน            : ใช้ของแต่ละบัญชี (ดูได้ที่ จัดการผู้ใช้ > ดูรายชื่อ)\n'
  rule
}

cmd_help() {
  ui_head
  printf '  %sพิมพ์ m เฉยๆ เพื่อเปิดเมนู ไม่ต้องจำคำสั่ง%s\n\n' "$B" "$N"
  printf '  %sคำสั่งลัด (ใช้เมื่อต้องการ):%s\n' "$B" "$N"
  printf '    m add ชื่อ รหัส วัน เครื่อง   เพิ่มผู้ใช้\n'
  printf '    m del ชื่อ                    ลบผู้ใช้\n'
  printf '    m list                        ดูรายชื่อ\n'
  printf '    m info ชื่อ                   ดูรายละเอียดผู้ใช้\n'
  printf '    m passwd ชื่อ                 เปลี่ยนรหัสผ่าน\n'
  printf '    m setexp ชื่อ วัน             ตั้งวันหมดอายุ (นับจากวันนี้)\n'
  printf '    m renew ชื่อ วัน              ต่ออายุเพิ่ม\n'
  printf '    m toggle ชื่อ                 เปิด/ปิดบัญชี\n'
  printf '    m setlimit ชื่อ จำนวน         จำกัดจำนวนเครื่อง (0 = ไม่จำกัด)\n'
  printf '    m online                      ดูผู้ใช้ออนไลน์\n'
  printf '    m track on|off                เปิด/ปิดการติดตามผู้ใช้\n'
  printf '    m grace วินาที                เวลาผ่อนผันเมื่อ IP เปลี่ยน\n'
  printf '    m blocked | m unblock ชื่อ    ดู/ปลดบล็อก\n'
  printf '    m health | m restart          สถานะ/รีสตาร์ทบริการ\n'
  printf '    m backup                      สำรองข้อมูล\n'
}

menu_users() {
  while :; do
    ui_head; status_bar
    printf '  %s👥 จัดการผู้ใช้%s\n\n' "$B" "$N"
    item 1 "➕ เพิ่มผู้ใช้" "สร้างบัญชีใหม่ (ตั้งชื่อ รหัสผ่าน อายุ จำนวนเครื่อง)"
    item 2 "🗑️  ลบผู้ใช้" "ลบบัญชีออกถาวร"
    item 3 "📄 ดูรายชื่อผู้ใช้" "แสดงรหัสผ่าน วันหมดอายุ จำนวนเครื่อง สถานะ"
    item 4 "🔍 ดูรายละเอียดผู้ใช้" "ข้อมูลเต็มและประวัติการเชื่อมต่อล่าสุด"
    item 5 "🔑 เปลี่ยนรหัสผ่าน" ""
    item 6 "📅 ตั้งวันหมดอายุ" "กำหนดใหม่ นับจากวันนี้"
    item 7 "⏩ ต่ออายุเพิ่ม" "บวกวันต่อจากวันหมดอายุเดิม"
    item 8 "⏸️  เปิด/ปิดบัญชี" "ปิดชั่วคราวโดยไม่ลบ"
    item 0 "↩ กลับ" ""
    rule
    printf '  👉 เลือกเมนู : '; read -r _x || return 0
    case $_x in
      1) cmd_add ;; 2) cmd_del ;; 3) cmd_list ;; 4) cmd_detail ;;
      5) cmd_passwd ;; 6) cmd_setexp ;; 7) cmd_renew ;; 8) cmd_toggle ;;
      0|00) return ;;
      *) continue ;;
    esac
    pause
  done
}

menu_limits() {
  while :; do
    ui_head; status_bar
    printf '  %s📱 จำกัดเครื่อง และผู้ใช้ออนไลน์%s\n\n' "$B" "$N"
    item 1 "📱 ตั้งจำกัดเครื่องต่อผู้ใช้" "กำหนดว่าบัญชีนี้ใช้ได้พร้อมกันกี่เครื่อง"
    item 2 "🟢 ดูผู้ใช้ออนไลน์" "ใครกำลังเชื่อมต่ออยู่ตอนนี้"
    if [ "$TRACK" = on ]; then _tt="🔎 ปิดการติดตามผู้ใช้ (ตอนนี้: เปิด)"; else _tt="🔎 เปิดการติดตามผู้ใช้ (ตอนนี้: ปิด)"; fi
    item 3 "$_tt" "ต้องเปิดไว้ ระบบจำกัดเครื่องถึงจะทำงาน"
    item 4 "⏱️  เวลาผ่อนผันเมื่อ IP เปลี่ยน" "ปัจจุบัน ${GRACE:-30} วินาที"
    item 5 "🚫 ดูรายการบล็อก และประวัติการตัด" ""
    item 6 "✅ ปลดบล็อกผู้ใช้" "ใช้เมื่อลูกค้าถูกตัดโดยไม่ตั้งใจ"
    item 7 "🧬 ดูข้อมูลลายนิ้วมือเครื่อง" "ค่าอัป/ดาวน์ที่แอปประกาศ (ไว้ตรวจสอบ)"
    item 0 "↩ กลับ" ""
    rule
    printf '  👉 เลือกเมนู : '; read -r _x || return 0
    case $_x in
      1) cmd_setlimit ;; 2) cmd_online ;;
      3) if [ "$TRACK" = on ]; then cmd_track off; else cmd_track on; fi ;;
      4) cmd_grace ;; 5) cmd_blocked ;; 6) cmd_unblock ;; 7) cmd_fp ;;
      0|00) return ;;
      *) continue ;;
    esac
    pause
  done
}

menu_service() {
  while :; do
    ui_head; status_bar
    printf '  %s⚙️  บริการ และสถานะ%s\n\n' "$B" "$N"
    item 1 "💚 ดูสถานะบริการ" "ZIVPN, พอร์ต, udpgw, ผู้ใช้"
    item 2 "🔄 รีสตาร์ท ZIVPN" "ลูกค้าจะหลุดแล้วต่อใหม่เองใน 2-3 วินาที"
    item 3 "▶️  เริ่ม ZIVPN" ""
    item 4 "⏹️  หยุด ZIVPN" "ลูกค้าทุกคนจะต่อไม่ได้"
    item 5 "📜 ดู log ล่าสุด" "25 บรรทัด"
    item 6 "🎮 รีสตาร์ท udpgw (7300)" ""
    item 7 "🔀 ตั้งกฎ port hopping ใหม่" "ใช้เมื่อรีบูตเครื่องแล้วลูกค้าต่อไม่ได้"
    item 0 "↩ กลับ" ""
    rule
    printf '  👉 เลือกเมนู : '; read -r _x || return 0
    case $_x in
      1) cmd_health ;;
      2) reload && ok "🔄 รีสตาร์ทบริการแล้ว" ;;
      3) systemctl start zivpn.service && ok "▶️  เริ่มบริการแล้ว" ;;
      4) systemctl stop zivpn.service && ok "⏹️  หยุดบริการแล้ว" ;;
      5) cmd_logs ;;
      6) if [ -f "$UNIT/zivpn-udpgw.service" ]; then systemctl restart zivpn-udpgw.service && ok "🎮 รีสตาร์ท udpgw แล้ว"; else printf '  ℹ️  udpgw ในเครื่องนี้ไม่ได้รันผ่านบริการของ ZIVPN\n'; fi ;;
      7) cmd_nat up && ok "🔀 ตั้งกฎ port hopping ใหม่แล้ว" ;;
      0|00) return ;;
      *) continue ;;
    esac
    pause
  done
}

menu_tools() {
  while :; do
    ui_head; status_bar
    printf '  %s🧰 สำรองข้อมูล และเครื่องมือ%s\n\n' "$B" "$N"
    item 1 "💾 สำรองข้อมูล" "บีบอัดโฟลเดอร์ตั้งค่าไว้ที่ /root"
    item 2 "🧹 ถอนติดตั้ง ZIVPN" "ลบทุกอย่างรวมถึงรายชื่อผู้ใช้"
    item 3 "📖 วิธีใช้คำสั่งลัด" ""
    item 0 "↩ กลับ" ""
    rule
    printf '  👉 เลือกเมนู : '; read -r _x || return 0
    case $_x in
      1) cmd_backup ;;
      2) printf '  ⚠️  พิมพ์ yes เพื่อยืนยันการถอนติดตั้ง: '; read -r _c
         if [ "$_c" = yes ]; then cmd_uninstall; return; else printf '  ยกเลิกแล้ว\n'; fi ;;
      3) cmd_help ;;
      0|00) return ;;
      *) continue ;;
    esac
    pause
  done
}

cmd_menu() {
  while :; do
    ui_head; status_bar
    item 1 "👥 จัดการผู้ใช้" "เพิ่ม ลบ ต่ออายุ เปลี่ยนรหัส ดูรายละเอียด"
    item 2 "📱 จำกัดเครื่อง และผู้ใช้ออนไลน์" "ตั้งจำนวนเครื่อง ดูคนออนไลน์ ปลดบล็อก"
    item 3 "⚙️  บริการ และสถานะ" "ดูสถานะ รีสตาร์ท ดู log"
    item 4 "📋 ข้อมูลสำหรับตั้งค่าแอป" "เซิร์ฟเวอร์ พอร์ต รหัสอำพราง"
    item 5 "🧰 สำรองข้อมูล และเครื่องมือ" "สำรอง ถอนติดตั้ง วิธีใช้คำสั่ง"
    item 0 "🚪 ออก" ""
    rule
    printf '  👉 เลือกเมนู : '; read -r _x || return 0
    case $_x in
      1) menu_users ;;
      2) menu_limits ;;
      3) menu_service ;;
      4) cmd_info; pause ;;
      5) menu_tools ;;
      0|00) return ;;
      *) : ;;
    esac
  done
}

[ "$DRY" = 1 ] || db_normalize
[ "$DRY" = 1 ] || { [ "$TRACK" = on ] && [ -f "$ETC/auth.sh" ] && ! grep -q 'AUTHV=5' "$ETC/auth.sh" && write_auth; }
[ "$DRY" = 1 ] || { [ "$TRACK" = on ] && [ ! -f "$UNIT/zivpn-limiter.timer" ] && limiter_units on; }

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
  setlimit) shift; cmd_setlimit "$@" ;;
  grace)    shift; cmd_grace "$@" ;;
  limiter)  cmd_limiter ;;
  fp)       cmd_fp ;;
  renew)    shift; cmd_renew "$@" ;;
  toggle)   shift; cmd_toggle "$@" ;;
  info|show) shift; cmd_detail "$@" ;;
  blocked)  cmd_blocked ;;
  unblock)  shift; cmd_unblock "$@" ;;
  logs)     cmd_logs ;;
  help|-h|--help) cmd_help ;;
  expire)   cmd_expire ;;
  nat)      shift; cmd_nat "$@" ;;
  backup)   cmd_backup ;;
  restart)  reload; cmd_health ;;
  start)    systemctl start zivpn.service ;;
  stop)     systemctl stop zivpn.service ;;
  status)   systemctl status zivpn.service --no-pager ;;
  uninstall) cmd_uninstall ;;
  menu|'')  cmd_menu ;;
  *) cmd_help ;;
esac
