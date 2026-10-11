# ออโต้สคริป โดย หลวงพี่

สคริปต์บริหารจัดการเซิร์ฟเวอร์ VPN/SSH แบบครบวงจร (ติดตั้ง จัดการผู้ใช้ จำกัดการเชื่อมต่อ ฯลฯ)
โฮสต์ไฟล์ทั้งหมดอยู่บน GitHub นี้ และสคริปต์จะดึงไฟล์จาก `raw.githubusercontent.com/savat/ocr-api/main` โดยอัตโนมัติ

---

## คำสั่งติดตั้ง

> ต้องรันบน VPS ที่เป็น **root** และเป็น **x86_64 (amd64)** เท่านั้น

```bash
# เข้าเป็น root
sudo -i

# เตรียมเครื่องมือ
apt-get update -y && apt-get install -y wget curl

# ดาวน์โหลดและรันตัวติดตั้ง
wget https://raw.githubusercontent.com/savat/ocr-api/main/install.sh -O install.sh
chmod +x install.sh && ./install.sh
```

ขั้นตอน:
1. รันคำสั่งด้านบน สคริปต์จะเริ่มทำงานทันที (ไม่ต้องใช้ Key)
2. สคริปต์จะตั้งค่า `sources.list`, ติดตั้งแพ็กเกจที่จำเป็น แล้วดึง `autoscript.sh` มาติดตั้งต่อ
3. เมื่อเสร็จ พิมพ์คำสั่ง `menu` เพื่อเปิดเมนูจัดการ

```bash
menu
```

---

## ระบบปฏิบัติการที่รองรับ

สคริปต์อ่านรหัสจาก `/etc/os-release` และใช้ **codename จริง** ของเครื่อง (ไม่ล็อกเลขเวอร์ชันตายตัว)

| ระบบ | เวอร์ชันที่รองรับ | หมายเหตุ |
| --- | --- | --- |
| Ubuntu | 18.04 (bionic) ขึ้นไป รวม 20.04 / 22.04 / 24.04 / 25.04 / 25.10 / 26.04 | ใช้ `archive.ubuntu.com` |
| Debian | 9 (stretch) / 10 (buster) | ใช้ `archive.debian.org` + `[trusted=yes]` (EOL) |
| Debian | 11 (bullseye) | ใช้ mirror + `security.debian.org` |
| Debian | 12 (bookworm) / 13 (trixie) ขึ้นไป | ใช้ mirror + `security.debian.org` (มี `non-free-firmware`) |

- **สถาปัตยกรรม:** x86_64 / amd64 เท่านั้น (ไบนารีที่ใช้เป็น ELF 64-bit)
- OS อื่น (CentOS, AlmaLinux, Rocky, Alpine ฯลฯ) จะถูกปฏิเสธ

---

## โปรโตคอล / บริการที่รองรับ

| # | บริการ | รายละเอียด |
| --- | --- | --- |
| 01 | Apache2 | เว็บเซิร์ฟเวอร์ (ใช้ทำ payload / redirect) |
| 02 | OpenSSH | SSH มาตรฐาน + เพิ่มพอร์ตเองได้ |
| 03 | Squid Proxy | HTTP Proxy (พอร์ต 3128 / 8080 / 8000 / 8799) |
| 04 | Dropbear | SSH น้ำหนักเบา (พอร์ต 109 / 143 / ปรับได้) |
| 05 | OpenVPN | VPN ผ่าน UDP/TCP (พอร์ต 1194) |
| 06 | Proxy SOCKS | SOCKS SSH / SOCKS OpenVPN |
| 07 | SSL Tunnel | SSH over TLS ด้วย stunnel (พอร์ต 443 / ปรับได้) |
| 08 | SSLH Multiplex | แชร์พอร์ตเดียวให้หลายโปรโตคอล (443) |
| 09 | Chisel | TCP/UDP tunnel ผ่าน HTTP |
| 10 | V2Ray | VMess / WebSocket (VLESS) |
| 11 | Trojan-Go | Trojan (TLS) |
| 12 | Webmin | แผงจัดการระบบผ่านเว็บ |
| 13 | BadVPN (UDPGW) | UDP over TCP สำหรับเกม (พอร์ต 7300) |
| 14 | ZIVPN (UDP) | UDP tunnel สำหรับแอป ZIVPN (พอร์ต 5667/udp + UDP port hopping) |
| - | SlowDNS | SSH/SSL/DROP/SOCKS ผ่าน DNS (พอร์ต 53/udp) |
| - | Shadowsocks | จัดการผู้ใช้ Shadowsocks |
| - | WebSocket | SSH over WebSocket (WS) |

พอร์ตที่เปิดผ่าน UFW ให้อัตโนมัติ: `80/tcp`, `443/tcp`, `3128/tcp`, `8799/tcp`, `8080/tcp`

---

## โครงสร้างไฟล์

```
/
├── install.sh          # ตัวติดตั้งหลัก
├── autoscript.sh       # ติดตั้งแพ็กเกจ + เมนู
├── fix.sh              # (ตัวช่วย) แก้ปัญหา dpkg/apt lock
├── Install/            # ไฟล์ประกอบ (ไบนารี/แพ็กเกจ/สคริปต์)
├── Modulos/            # โมดูลเมนูทั้งหมด (51 โมดูล)
└── zivpn/              # ตัวติดตั้ง + ตัวจัดการ ZIVPN (install.sh, menu.sh)
```

## ZIVPN (UDP)

ติดตั้งผ่านเมนู: `menu` → `09 เมนูการติดตั้ง` → `14 ZIVPN`

- ผู้ใช้ ZIVPN = รหัสผ่านใน `config.json` (`auth.mode = passwords`)
- ตัวจัดการติดตั้งเป็นคำสั่ง `m` (เช่น `m add`, `m list`, `m online`, `m backup`, `m health`)
- ดูลูกค้าที่กำลังออนไลน์: `m online` (นับ `client connected`/`client disconnected`
  จาก log ของ `zivpn.service` ผ่าน journald แล้วแสดง USER / IP / จำนวน connection / เวลาล่าสุด)
- ค่าเริ่มต้น: พอร์ต `5667/udp`, UDP port hopping `6000:19999 -> 5667`
- ปลายทางอ้างอิงไบนารีจาก upstream [`zahidbd2/udp-zivpn`](https://github.com/zahidbd2/udp-zivpn)

## หมายเหตุ

- apt mirror เปลี่ยนมาใช้ทางการแล้ว: `archive.ubuntu.com` (Ubuntu), `deb.debian.org` /
  `archive.debian.org` (Debian)
- `.dec` และหน้า HTML 404 ไม่ได้อัปโหลดขึ้น repo นี้
