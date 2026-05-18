#!/bin/bash

# ====================================================
# 作者: 人生若只如初见
# Release、Standard、Snapshot、Staging
# 支持以下协议矩阵一键自动安装
#  【1】 . 安装 VLESS-REALITY-Vision
#  【2】 . 安装 VLESS-REALITY-xhttp
#  【3】 . 安装 VLESS-WS-TLS
#  【4】 . 安装 VLESS-gRPC-TLS
#  【5】 . 安装 VLESS-XHTTP-TLS
#  【6】 . 安装 Trojan-WS-TLS
#  【7】 . 安装 Trojan-gRPC-TLS
#  【8】 . 安装 VMess-WS-TLS
#  【9】 . 安装 VMess-gRPC-TLS
#   修改功能：
#   2026/05/01：1、域名检测。2、信息查询功能。3、优化菜单。
#   2026/05/02：1、增加二维码展示功能。
#   2026/05/05：1、修复Trojan协议的二维码。2、修复caddy检查安装。
#   2026/05/07：1、增加VLESS-REALITY-xhttp协议。2、修复当前协议判断，更详细。
#   2026/05/08：增加各种验证、排错、去掉apt lock暴力解决，修改安全性配置。
#   2026/05/09：优化代码，增加安装过程中可能出现的错误提示。
#   2026/05/10：增加BBR安装菜单，增加防火墙智能策略，修复可能出现的错误提示，优化代码。
#   2026/05/15：合并gen_vless_reality,gen_vless_reality_xhttp函数为gen_vless_reality_unified函数，优化代码。
#   2026/05/17：修复check_current_protocol函数。
# ====================================================
# 终端颜色定义
Font_Black="\033[30m"   # 黑色
Font_Red="\033[31m"     # 红色
Font_Green="\033[32m"   # 绿色
Font_Yellow="\033[33m"  # 黄色
Font_Blue="\033[34m"    # 蓝色
Font_Magenta="\033[35m" # 洋红色/紫色
Font_Cyan="\033[36m"    # 青色
Font_White="\033[37m"   # 白色
Font_Suffix="\033[0m"   # 重置颜色/颜色结尾

# 架构检测，如果不支持，直接不运行
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)   XRAY_ARCH="64" ;;
    aarch64)  XRAY_ARCH="arm64" ;;
    armv7l)   XRAY_ARCH="arm32-v7a" ;;
    armv8l)   XRAY_ARCH="arm64" ;;
    *)        echo -e "${Font_Red}不支持的架构: ${ARCH}${Font_Suffix}"; exit 1 ;;
esac

echo -e "${Font_Cyan}检测到系统架构: ${ARCH} (${XRAY_ARCH})${Font_Suffix}"

# ------------- 严格模式 + 错误追踪 -------------
set -e
set -o pipefail
# 捕获错误，打印行号和出错命令
trap 'echo -e "\n${Font_Red}[ERROR] 脚本在第 $LINENO 行执行失败！\n出错命令: $BASH_COMMAND${Font_Suffix}"' ERR

# ------------- 全局变量定义区域 SRTART -------------
# 变量初始化
is_core="xray"
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
PRESET_DOMAIN="vcc.myvpsworld.top" #如果为空，安装过程中手动输入
XRAY_VERSION="26.5.3"   #最新版 latest
CADDY_VERSION="2.11.2"
FIX_VER=1 #1，锁定。0，最新版#

# Reality 伪装域名配置（随机选择）
REALITY_DEST_OPTIONS=(
    "www.microsoft.com"
    "www.apple.com"
    "www.amazon.com"
    "www.cloudflare.com"
    "www.bing.com"
)
# ------------- 全局变量定义区域 END -------------

# ------------- 自定义函数区域 SRTART -------------
# 自定义函数：随机选择函数
get_random_dest() {
    local idx=$((RANDOM % ${#REALITY_DEST_OPTIONS[@]}))
    echo "${REALITY_DEST_OPTIONS[$idx]}"
}
# 自定义函数：检查当前 user root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${Font_Red}必须以 root 权限运行此脚本！${Font_Suffix}"
        exit 1
    fi
}

check_command() {
    if ! "$@"; then
        echo -e "${Font_Red}[ERROR] 命令执行失败: $*${Font_Suffix}"
        echo -e "${Font_Red}请查看上方错误信息，脚本已停止执行。${Font_Suffix}"
        journalctl -u xray --no-pager -n 50 2>/dev/null || true
        journalctl -u caddy --no-pager -n 50 2>/dev/null || true
        exit 1
    fi
    return 0
}

setup_xray_user() {
    useradd -r -s /bin/false -U xray 2>/dev/null || true
    mkdir -p "$conf_dir"
    chown -R xray:xray "$conf_dir" 2>/dev/null || true
}

# 自定义函数：TLS 类协议公共准备（减少少量重复）
common_tls_setup() {
    install_caddy
}

restart_service() {
    local svc=$1
    systemctl restart "$svc"
    if ! systemctl is-active --quiet "$svc"; then
        echo -e "${Font_Red}[ERROR] $svc 启动失败${Font_Suffix}"
        systemctl status "$svc" --no-pager
        exit 1
    fi
}

#自定义函数：JSON 校验函数
check_json() {
    local file=$1

    if ! command -v python3 &>/dev/null; then
        echo -e "${Font_Yellow}[WARN] 未安装 python3，跳过 JSON 校验${Font_Suffix}"
        return 0
    fi

    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
        echo -e "${Font_Red}[ERROR] config.json 格式错误：$file${Font_Suffix}"
        python3 -m json.tool "$file" || true
        exit 1
    fi
}

#自定义函数：端口检测函数
check_port() {
    local port=$1

    if ss -tulnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${Font_Red}[ERROR] 端口 $port 已被占用${Font_Suffix}"
        ss -tulnp | grep ":$port "
        exit 1
    fi
}

#自定义函数：Caddy 配置检查函数
check_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo -e "${Font_Red}[ERROR] Caddy 未安装${Font_Suffix}"
        exit 1
    fi

    # 检查配置语法
    caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${Font_Red}[ERROR] Caddyfile 语法错误${Font_Suffix}"
        caddy validate --config /etc/caddy/Caddyfile
        exit 1
    fi
}
#自定义函数：服务端口存活检查函数
check_service_alive() {
    local port=$1
    local name=$2

    # 1. xray 是否运行（必须）
    if ! systemctl is-active --quiet xray; then
        echo -e "${Font_Red}[ERROR] xray 未运行${Font_Suffix}"
        exit 1
    fi

    # 2. TCP 实际可用性（唯一关键判断）
    if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "${Font_Red}[ERROR] $name TCP 不可达: $port${Font_Suffix}"
        exit 1
    fi

    echo -e "${Font_Green}[OK] $name 服务正常 ($port)${Font_Suffix}"
}

#自定义函数：TCP检查
check_external_tcp() {
    local host=$1
    local port=$2

    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${Font_Green}[OK] 外网TCP可达：$host:$port${Font_Suffix}"
    else
        echo -e "${Font_Red}[ERROR] 外网不可达：$host:$port${Font_Suffix}"
        exit 1
    fi
}

#  自定义函数：依赖检查函数
check_dependencies() {
    echo -e "${Font_Cyan}>>> 检查系统依赖...${Font_Suffix}"
    local deps=(curl openssl wget qrencode host base64 socat tar unzip vnstat gnupg2 dnsutils)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            apt-get install -y "$dep" -qq
        fi
    done
}

# 自定义函数：强制开启防火墙函数
enable_firewall() {
    echo -e "${Font_Cyan}>>> 配置安全防火墙...${Font_Suffix}"
    
    # 确保安装了 ufw
    apt-get install -y ufw -qq

    # 【自动识别】获取当前 sshd 实际监听的端口
    local ssh_port=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n1)
    
    # 如果没识别到（极少数情况），则尝试从配置文件读取，最后默认 22
    if [[ -z "$ssh_port" ]]; then
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    fi

    echo -e "${Font_Yellow}检测到当前 SSH 端口为: ${ssh_port}${Font_Suffix}"

    # 设置默认策略
    ufw default allow outgoing
    ufw default deny incoming

    # 【关键】放行识别到的 SSH 端口，并开启防爆破限速
    ufw limit "${ssh_port}/tcp" comment 'SSH-Port-Auto-Detected'

    # 放行业务端口
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp

    # 强制激活
    echo "y" | ufw enable
    
    echo -e "${Font_Green}[OK] 防火墙已启动，已自动放行 SSH 端口 ${ssh_port}。${Font_Suffix}"
}


# 自定义函数：时区检查函数
check_and_set_timezone() {
    local current_tz=$(timedatectl | grep "Time zone" | awk '{print $3}' 2>/dev/null || date +%Z)
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    echo -e "${Font_Cyan}当前系统时间: ${Font_Green}${current_time}${Font_Suffix}"
    echo -e "   当前时区 : ${Font_Green}${current_tz}${Font_Suffix}"

    if [[ "$current_tz" == "Asia/Shanghai" ]]; then
        echo -e "${Font_Green}   状态确认 : 已是 Asia/Shanghai 时区，无需修改。${Font_Suffix}"
    else
        echo -e "${Font_Yellow}   建议提示 : 当前非上海时区，建议修改以确保日志时间准确。${Font_Suffix}"
        read -p ">>> 是否修改时区为 Asia/Shanghai？(y/N): " change_tz
        if [[ "$change_tz" == "y" || "$change_tz" == "Y" ]]; then
            timedatectl set-timezone Asia/Shanghai 2>/dev/null || (rm -f /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime)
            echo -e "${Font_Green}[OK] 时区已成功修改为 Asia/Shanghai，当前时间: $(date "+%Y-%m-%d %H:%M:%S")${Font_Suffix}"
        fi
    fi
}

# 自定义函数：开启BBR
enable_bbr() {
    echo -e "${Font_Cyan}>>> 检查并开启 BBR 网络加速...${Font_Suffix}"
    
    # 1. 判断当前是否已经开启 BBR
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${Font_Green}[INFO] BBR 加速已在运行中，无需重复开启。${Font_Suffix}"
    else
        echo -e "${Font_Yellow}[ACTION] 正在写入 BBR配置...${Font_Suffix}"
        
        # 2. 备份 sysctl.conf 以防万一
        cp /etc/sysctl.conf /etc/sysctl.conf.bak
        
        # 3. 写入内核参数
        # 使用 sed 确保如果文件中已有相关项则修改，没有则追加，避免重复堆叠
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        
        # 4. 生效配置
        sysctl -p >/dev/null 2>&1
        
        # 5. 最终验证
        if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
            echo -e "${Font_Green}[OK] BBR 加速已成功开启！${Font_Suffix}"
        else
            echo -e "${Font_Red}[ERROR] BBR 开启失败，请检查内核是否支持。${Font_Suffix}"
        fi
    fi
}
# ------------- 自定义函数区域 END -------------

# ------------- BBR 管理子菜单 START -------------
# BBR 管理子菜单
menu_bbr() {
    clear
    # 1. 获取内核版本
    local kernel_version=$(uname -r)
    # 2. 获取当前拥塞控制算法
    local current_algo=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}' 2>/dev/null || echo "未知")
    
    # 3. 判定 BBRv3 兼容性 (内核 >= 6.4)
    local v3_support="${Font_Red}不支持 v3${Font_Suffix}"
    local ver_main=$(echo $kernel_version | cut -d. -f1)
    local ver_sub=$(echo $kernel_version | cut -d. -f2)
    if [ "$ver_main" -gt 6 ] || { [ "$ver_main" -eq 6 ] && [ "$ver_sub" -ge 4 ]; }; then
        v3_support="${Font_Green}支持 v3${Font_Suffix}"
    fi

    # 4. 判定显示状态
    local bbr_status
    if [[ "$current_algo" == "bbr" ]]; then
        bbr_status="${Font_Green}运行中 (BBR/v1/v3)${Font_Suffix}"
    elif [[ "$current_algo" == "bbrplus" ]]; then
        bbr_status="${Font_Green}运行中 (BBRplus)${Font_Suffix}"
    else
        bbr_status="${Font_Red}未开启 ($current_algo)${Font_Suffix}"
    fi

    echo -e "${Font_Magenta}======================= BBR 网络加速管理 ======================${Font_Suffix}"
    echo -e "   当前内核 : ${Font_Cyan}${kernel_version}${Font_Suffix} ($v3_support)"
    echo -e "   当前状态 : ${bbr_status}"
    echo -e "   当前算法 : ${Font_Cyan}${current_algo}${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "  【1】 . 开启 BBR 原版 (v1 - 最稳定)"
    echo -e "  【2】 . 开启 BBRv3 (需内核 6.4+)"
    echo -e "  【3】 . 开启 BBRplus (需更换内核，${Font_Red}有风险${Font_Suffix})"
    echo -e "  【4】 . 关闭 BBR (恢复系统默认 cubic)"
    echo -e "  【q】 . 返回主菜单"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    read -p "请选择: " bbr_num

    case "$bbr_num" in
        1|2) # v1 和 v3 在操作上是统一的，取决于内核版本
            enable_bbr_native
            read -p "按回车键继续..."; menu_bbr ;;
        3) install_bbr_plus; read -p "按回车键继续..."; menu_bbr ;;
        4) disable_bbr; read -p "按回车键继续..."; menu_bbr ;;
        q|Q) main_menu ;;
        *) menu_bbr ;;
    esac
}

# 统筹开启内核原生 BBR (包含 v1/v3)
enable_bbr_native() {
    echo -e "${Font_Cyan}>>> 正在配置内核 BBR 参数...${Font_Suffix}"
    
    # 修复：确保文件存在，防止 sed 报错
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1
    echo -e "${Font_Green}[OK] BBR 指令已发送。如果内核版本 >= 6.4，将自动以 v3 运行。${Font_Suffix}"
}

# 开启 BBRplus
install_bbr_plus() {
    echo -e "${Font_Red}警告：开启 BBRplus 需要下载第三方内核并重启服务器！${Font_Suffix}"
    echo -e "${Font_Yellow}注意：在 Debian 12+ / Ubuntu 24+ 上更换旧内核可能导致无法开机，请务必确认有 VNC 访问权限。${Font_Suffix}"
    read -p "确定要继续吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        # 替换为目前仍然有效的全能加速脚本
        wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
    fi
}

# 关闭 BBR
disable_bbr() {
    echo -e "${Font_Cyan}>>> 正在恢复默认拥塞控制算法 (cubic)...${Font_Suffix}"
    
    # 修复：确保文件存在
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1
    echo -e "${Font_Yellow}[OK] BBR 已关闭。${Font_Suffix}"
}

# ------------- BBR 管理子菜单 START -------------
# --- 1. 环境准备模块 ---
preparation_stack() {
    check_root
    setup_xray_user

    # === 时区处理（改为可选，不再强制）===
    check_and_set_timezone

    echo -e "${Font_Cyan}>>> 正在处理 apt 锁...${Font_Suffix}"
    apt-get -o DPkg::Lock::Timeout=180 update --allow-releaseinfo-change -qq || true
    dpkg --configure -a

    # 调用防火墙策略函数
    enable_firewall
    
    # 调用开启BBR函数
    enable_bbr
    
    # 调用依赖检查函数
    check_dependencies

    systemctl enable vnstat --now 2>/dev/null || true

    # ==================== Xray 安装 ====================
    # 安装 Xray（安全方式：先下载再执行）
    if ! command -v xray &> /dev/null || [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo -e "${Font_Cyan}>>> 正在安装 Xray v${XRAY_VERSION}...${Font_Suffix}"
        TMP_SCRIPT=$(mktemp)
        check_command curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$TMP_SCRIPT"
        
        # -------------------------------------------------------
        # 关键点：设置此变量后，官方脚本将只安装文件，不再报错启动
        export XRAY_INSTALL_SKIP_START=1 
        # -------------------------------------------------------

        check_command bash "$TMP_SCRIPT" install --version ${XRAY_VERSION}
        rm -f "$TMP_SCRIPT"
        check_command ln -sf /usr/local/bin/xray /usr/bin/xray
        
        # 仅开启自启，不触发启动命令
        systemctl enable xray >/dev/null 2>&1 || true
        
        echo -e "${Font_Green}[OK] Xray v${XRAY_VERSION} 安装完成（已屏蔽无效启动告警）${Font_Suffix}"
    fi

    # 创建 systemd 服务（仅创建，不启动）
    if [ ! -f "/etc/systemd/system/xray.service" ]; then
        cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config ${config_path}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${conf_dir}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable xray

    echo -e "${Font_Green}[OK] 环境准备完成（Xray 服务已启用，等待配置生成后启动）${Font_Suffix}"
}

# --- 1.5. Caddy 安装函数（完全保留）---
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        echo -e "${Font_Cyan}正在安装 Caddy v${CADDY_VERSION}...${Font_Suffix}"
        
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list

        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        
        check_command apt-get update -qq
        check_command apt-get install caddy=${CADDY_VERSION} -y || check_command apt-get install caddy -y

        if [ "$FIX_VER" -eq 1 ] && command -v caddy &> /dev/null; then
            apt-mark hold caddy
        fi

        if ! command -v caddy &> /dev/null; then
            echo -e "${Font_Red}[X] Caddy 安装失败！${Font_Suffix}"
            exit 1
        fi
        echo -e "${Font_Green}[OK] Caddy 安装成功${Font_Suffix}"
    fi
    mkdir -p /etc/caddy
}

# --- 域名解析检测（完全保留）---
check_domain() {
    local domain=""
    while true; do
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -p "请输入您的解析域名后回车 [默认域名: $PRESET_DOMAIN]: " domain
            domain=${domain:-$PRESET_DOMAIN}
        else
            read -p "请输入您的解析域名: " domain
        fi

        if [[ -z "$domain" ]]; then continue; fi

        local local_ipv4=$(curl -4 -s --connect-timeout 5 ip.sb || echo "")
        local local_ipv6=$(curl -6 -s --connect-timeout 5 ip.sb || echo "")
        local resolved_ips=$(dig +short "$domain" A 2>/dev/null)
        if [[ -z "$local_ipv4" ]]; then
            echo -e "${Font_Red}[ERROR] 获取本机 IP 失败${Font_Suffix}"
            exit 1
        fi
        
        echo -e "${Font_Cyan}本机 IPv4: $local_ipv4${Font_Suffix}"
        echo -e "${Font_Cyan}本机 IPv6: $local_ipv6${Font_Suffix}"
        if [[ -n "$resolved_ips" ]]; then
            echo -e "${Font_Cyan}域名解析地址:${Font_Suffix}\n$resolved_ips"
        else
            echo -e "${Font_Yellow}警告: 未能获取该域名的解析记录。${Font_Suffix}"
        fi

        local pass=0
        for rip in $resolved_ips; do
            if [[ -n "$local_ipv4" && "$rip" == "$local_ipv4" ]] || [[ -n "$local_ipv6" && "$rip" == "$local_ipv6" ]]; then
                pass=1
                break
            fi
        done

        if [[ $pass -eq 1 ]]; then
            echo -e "${Font_Green}检测通过：域名已正确解析到本机 IP。${Font_Suffix}"
            echo "$domain" > /tmp/domain
            export domain
            break
        else
            echo -e "${Font_Red}错误: 域名解析地址与本机 IP 不符！${Font_Suffix}"
            echo -e "${Font_Yellow}1. 重新输入 | 2. 强制跳过 (适合已开启 CDN 的域名)${Font_Suffix}"
            read -p "请选择: " retry_choice
            [[ "$retry_choice" == "2" ]] && break
        fi
    done
}

# --- 查看当前协议（修正了语法断裂大括号）---
check_current_protocol() {
    if [[ ! -f $config_path ]]; then
        echo -e "${Font_Red}错误: 未检测到配置文件 ($config_path)，请先安装协议。${Font_Suffix}"
        read -p "按回车键返回主菜单"
        return
    fi

    echo -e "${Font_Magenta}--- 当前协议详细信息 ---${Font_Suffix}"
    
    local uuid=$(grep -m1 '"id":' $config_path | grep -oP '(?<="id": ")[^"]+' || grep -m1 '"password":' $config_path | grep -oP '(?<="password": ")[^"]+')
    local network=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+')
    
    local ip=$(curl -4 -s --connect-timeout 5 ip.sb || curl -s http://ipv4.icanhazip.com)
    local domain=""
    if [[ -f "/etc/caddy/Caddyfile" ]]; then
        domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
    fi
    [[ -z "$domain" ]] && domain=$(grep -oP '(?<="serverNames": \[")[^"]+' $config_path | head -n1)
    [[ -z "$domain" ]] && domain=$ip

    # === 修复后的判断逻辑 ===
    if grep -q "realitySettings" $config_path; then
        local pub_key=$(cat ${conf_dir}/pub.key 2>/dev/null || echo "未找到公钥文件")
        local short_id=$(grep -m1 '"shortIds":' $config_path | grep -oP '(?<="shortIds": \[").*(?="])' | cut -d'"' -f1)
        local sni=$(grep -m1 '"serverNames":' $config_path | grep -oP '(?<="serverNames": \[").*(?="])' | cut -d'"' -f1)
        
        if grep -q "xhttpSettings" $config_path; then
            local path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
            show_protocol_info "REALITY-xHTTP" "$uuid" "$sni" "$pub_key" "$short_id" "$path"
        else
            show_protocol_info "REALITY-Vision" "$uuid" "$sni" "$pub_key" "$short_id"
        fi

    elif [[ "$network" == "ws" ]]; then
        local path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        
        if grep -q '"protocol": "trojan"' $config_path; then
            show_protocol_info "Trojan-WS" "$uuid" "$domain" "$path"
        elif grep -q '"protocol": "vmess"' $config_path; then
            # VMess-WS 使用专用函数
            export DOMAIN="$domain"
            export UUID="$uuid"
            export WPATH="$path"
            show_vmess_ws_info
        else
            show_protocol_info "VLESS-WS" "$uuid" "$domain" "$path"
        fi

    elif [[ "$network" == "grpc" ]]; then
        local serviceName=$(grep -m1 '"serviceName":' $config_path | grep -oP '(?<="serviceName": ")[^"]+')
        
        if grep -q '"protocol": "trojan"' $config_path; then
            show_protocol_info "Trojan-gRPC" "$uuid" "$domain" "$serviceName"
        elif grep -q '"protocol": "vmess"' $config_path; then
            # VMess-gRPC 使用专用函数
            export DOMAIN="$domain"
            export UUID="$uuid"
            export WPATH="$serviceName"
            show_vmess_grpc_info
        else
            show_protocol_info "VLESS-gRPC" "$uuid" "$domain" "$serviceName"
        fi

    elif [[ "$network" == "xhttp" ]]; then
        local path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        show_protocol_info "VLESS-XHTTP" "$uuid" "$domain" "$path"

    else
        echo -e "${Font_Red}未能识别协议类型。${Font_Suffix}"
    fi
    
    echo -e "${Font_Yellow}-----------------------------------------------------------${Font_Suffix}"
    read -p "按回车键返回主菜单"
}
# ------------------------------------------------ 核心协议模块 ------------------------------------------------
gen_vless_reality_unified() {
    local mode=$1

    preparation_stack

    if [ "$mode" = "vision" ]; then
        echo -e "${Font_Cyan}正在配置 VLESS-REALITY-Vision...${Font_Suffix}"
        local flow=', "flow": "xtls-rprx-vision"'
        local network="tcp"
        local extra_settings=""
        local show_func="show_vless_reality_info"
    else
        echo -e "${Font_Cyan}正在配置 VLESS-REALITY-xhttp...${Font_Suffix}"
        local flow=""
        local network="xhttp"
        local path=$(openssl rand -hex 6)
        local extra_settings='"xhttpSettings": {"path": "/'$path'", "mode": "auto"},'
        local show_func="show_vless_reality_xhttp_info"
    fi

    local config_path="/usr/local/etc/xray/config.json"
    local conf_dir="/usr/local/etc/xray"
    mkdir -p "$conf_dir"

    local xray_bin="/usr/local/bin/xray"
    [[ ! -f "$xray_bin" ]] && xray_bin=$(command -v xray)

    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local keys=$("$xray_bin" x25519 2>/dev/null)
    local priv_key=$(echo "$keys" | awk -F': ' '/Private/ {print $2}' | tr -d ' ')
    local pub_key=$(echo "$keys" | awk -F': ' '/Public/ {print $2}' | tr -d ' ')
    local short_id=$(openssl rand -hex 8)
    local dest_server=$(get_random_dest || echo "www.microsoft.com")

    echo -e "${Font_Cyan}本次 Reality 伪装站点：${Font_Green}$dest_server${Font_Suffix}"
    echo "$pub_key" > "${conf_dir}/pub.key" 2>/dev/null || true

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": 443,
        "protocol": "vless",
        "settings": {
            "clients": [{ "id": "$uuid"$flow }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "$network",
            "security": "reality",
            $extra_settings
            "realitySettings": {
                "show": false,
                "dest": "$dest_server:443",
                "xver": 0,
                "serverNames": ["$dest_server"],
                "privateKey": "$priv_key",
                "shortIds": ["$short_id"]
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    check_json "$config_path"
    systemctl daemon-reload
    restart_service xray
    check_service_alive 443 "VLESS-REALITY"
    check_external_tcp "$(curl -4 -s ip.sb || true)" 443
    
    if [ "$mode" = "vision" ]; then
        show_protocol_info "REALITY-Vision" "$uuid" "$dest_server" "$pub_key" "$short_id"
    else
        show_protocol_info "REALITY-xHTTP" "$uuid" "$dest_server" "$pub_key" "$short_id" "$path"
    fi
    
}


#############协议1和协议2结束#########

# TLS 协议使用 common_tls_setup
gen_vless_ws() {
    check_domain
    domain="$(cat /tmp/domain 2>/dev/null || echo "")"
    [[ -z "$domain" ]] && {
        echo "[ERROR] domain 为空"
        exit 1
    }
    install_caddy
    
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10001
    check_port $port

    echo -e "${Font_Cyan}正在配置 VLESS-WS-TLS (Caddy 反代)...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "ws", 
            "wsSettings": { "path": "/$path" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path 127.0.0.1:$port
}" > /etc/caddy/Caddyfile

    check_caddy
    check_json "$config_path"
    restart_service caddy
    restart_service $is_core
    echo -e "${Font_Cyan}请稍等，生成中...${Font_Suffix}"
    sleep 2
    check_service_alive $port "VLESS-WS"    
    show_protocol_info "VLESS-WS" "$uuid" "$domain" "$path"

}

gen_vless_grpc() {
    check_domain
    domain="$(cat /tmp/domain 2>/dev/null || echo "")"
    [[ -z "$domain" ]] && {
        echo "[ERROR] domain 为空"
        exit 1
    }
    install_caddy
    
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local serviceName=$(openssl rand -hex 4)
    local port=10002
    check_port $port

    echo -e "${Font_Cyan}正在配置 VLESS-gRPC-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "grpc", 
            "grpcSettings": { "serviceName": "$serviceName" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}" > /etc/caddy/Caddyfile
    check_caddy
    check_json "$config_path"
    restart_service caddy
    restart_service $is_core
    echo -e "${Font_Cyan}请稍等，生成中...${Font_Suffix}"
    sleep 2
    check_service_alive $port "VLESS-gRPC"
    check_external_tcp "$domain" 443    
    show_protocol_info "VLESS-gRPC" "$uuid" "$domain" "$serviceName"
}

gen_vless_xhttp() {
    check_domain
    domain="$(cat /tmp/domain 2>/dev/null || echo "")"
    [[ -z "$domain" ]] && {
        echo "[ERROR] domain 为空"
        exit 1
    }
    install_caddy    
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10003
    check_port $port

    echo -e "${Font_Cyan}正在配置 VLESS-XHTTP-TLS...${Font_Suffix}"

    # 修改点 1：明确指定 XHTTP 的工作模式为 auto
    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "xhttp", 
            "xhttpSettings": { 
                "path": "/$path",
                "mode": "auto"
            } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # 修改点 2：优化 Caddyfile 反代参数，强制开启 h2c 并禁用响应缓冲（核心修复）
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy 127.0.0.1:$port {
        transport http {
            versions h2c
        }
        flush_interval -1
    }
}" > /etc/caddy/Caddyfile

    check_caddy
    check_json "$config_path"
    restart_service caddy
    restart_service $is_core
    echo -e "${Font_Cyan}请稍等，生成中...${Font_Suffix}"
    sleep 2
    check_service_alive $port "VLESS-XHTTP"
    check_external_tcp "$domain" 443        
    show_protocol_info "VLESS-XHTTP" "$uuid" "$domain" "$path"
}


# 协议 6 
gen_trojan_ws() {
    check_domain
    local domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${Font_Red}[ERROR] domain 为空，请检查域名配置${Font_Suffix}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    local pass
    read -p "请输入 Trojan 密码 (默认随机6位hex): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local path=$(openssl rand -hex 8)
    local port=10004

    echo -e "${Font_Cyan}正在配置 Trojan-WS-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "trojan",
        "settings": { 
            "clients": [{ "password": "$pass" }] 
        },
        "streamSettings": { 
            "network": "ws", 
            "wsSettings": { "path": "/$path" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    cat <<EOF > /etc/caddy/Caddyfile
$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path 127.0.0.1:$port
}
EOF

    check_caddy
    check_json "$config_path"
    
    restart_service caddy
    restart_service "$is_core"
    
    echo -e "${Font_Cyan}请稍等，验证服务状态中...${Font_Suffix}"
    sleep 3
    
    check_service_alive $port "Trojan-WS"
    check_external_tcp "$domain" 443
    
    # === 关键修复：必须严格使用 "Trojan-WS"（大写 WS）===
    show_protocol_info "Trojan-WS" "$pass" "$domain" "$path"
}

# 协议 7 安装 Trojan-gRPC-TLS
gen_trojan_grpc() {
    check_domain
    local domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${Font_Red}[ERROR] domain 为空，请检查域名配置${Font_Suffix}"
        exit 1
    }
    
    install_caddy 
    common_tls_setup
    
    # === 密码处理（统一变量名）===
    local uuid
    read -p "请输入 Trojan 密码 (默认随机6位hex): " uuid
    [[ -z "$uuid" ]] && uuid=$(openssl rand -hex 6)

    local serviceName=$(openssl rand -hex 8)   # 加长一点
    local port=10005
    check_port $port

    echo -e "${Font_Cyan}正在配置 Trojan-gRPC-TLS...${Font_Suffix}"

    # === Xray 配置（Trojan + gRPC）===
    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "trojan",
        "settings": { 
            "clients": [{ "password": "$uuid" }] 
        },
        "streamSettings": { 
            "network": "grpc", 
            "grpcSettings": { "serviceName": "$serviceName" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # === Caddy 配置（gRPC 必须带 h2c）===
    cat <<EOF > /etc/caddy/Caddyfile
$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}
EOF

    check_caddy
    check_json "$config_path"
    
    restart_service caddy
    restart_service "$is_core"
    
    echo -e "${Font_Cyan}请稍等，验证服务状态中...${Font_Suffix}"
    sleep 3
    
    check_service_alive $port "Trojan-gRPC"
    check_external_tcp "$domain" 443
    
    # === 关键：必须用 "Trojan-gRPC"（和 show_protocol_info case 严格匹配）===
    show_protocol_info "Trojan-gRPC" "$uuid" "$domain" "$serviceName"
}


# 协议 8，安装 VMess-WS-TLS 【广泛兼容/传统方案】
gen_vmess_ws() {
    check_domain
    local domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${Font_Red}[ERROR] domain 为空，请检查域名配置${Font_Suffix}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    # === UUID 与路径 ===
    local uuid
    read -p "请输入 VMess UUID (默认随机生成): " uuid
    [[ -z "$uuid" ]] && uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local path=$(openssl rand -hex 8)
    local port=10006

    echo -e "${Font_Cyan}正在配置 VMess-WS-TLS...${Font_Suffix}"

    # === Xray 配置 ===
    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vmess",
        "settings": { 
            "clients": [{ "id": "$uuid", "alterId": 0 }] 
        },
        "streamSettings": { 
            "network": "ws", 
            "wsSettings": { "path": "/$path" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # === Caddy 配置 ===
    cat <<EOF > /etc/caddy/Caddyfile
$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path 127.0.0.1:$port
}
EOF

    check_caddy
    check_json "$config_path"
    
    restart_service caddy
    restart_service "$is_core"
    
    echo -e "${Font_Cyan}请稍等，验证服务状态中...${Font_Suffix}"
    sleep 3
    
    check_service_alive $port "VMess-WS"
    check_external_tcp "$domain" 443
    
    # === 关键修复：调用专用 VMess 显示函数（不是 show_protocol_info）===
    # 临时导出变量供 show_vmess_ws_info 使用
    export DOMAIN="$domain"
    export UUID="$uuid"
    export WPATH="$path"
    
    show_vmess_ws_info
}

# 协议 9
gen_vmess_grpc() {
    check_domain
    local domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${Font_Red}[ERROR] domain 为空，请检查域名配置${Font_Suffix}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    # === UUID 与 ServiceName ===
    local uuid
    read -p "请输入 VMess UUID (默认随机生成): " uuid
    [[ -z "$uuid" ]] && uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local serviceName=$(openssl rand -hex 8)   # 加长一点，更安全
    local port=10007                           # 使用独立高位端口

    echo -e "${Font_Cyan}正在配置 VMess-gRPC-TLS...${Font_Suffix}"

    # === Xray 配置 ===
    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vmess",
        "settings": { 
            "clients": [{ "id": "$uuid", "alterId": 0 }] 
        },
        "streamSettings": { 
            "network": "grpc", 
            "grpcSettings": { "serviceName": "$serviceName" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # === Caddy 配置（gRPC 必须 h2c）===
    cat <<EOF > /etc/caddy/Caddyfile
$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}
EOF

    check_caddy
    check_json "$config_path"
    
    restart_service caddy
    restart_service "$is_core"
    
    echo -e "${Font_Cyan}请稍等，验证服务状态中...${Font_Suffix}"
    sleep 3
    
    check_service_alive $port "VMess-gRPC"
    check_external_tcp "$domain" 443
    
    # === 关键：调用专用 VMess-gRPC 显示函数 ===
    export DOMAIN="$domain"
    export UUID="$uuid"
    export WPATH="$serviceName"
    show_vmess_grpc_info
}

# ------------------------------------------------ 信息展示模块（完全保留）------------------------------------------------
# ==================== 【合并版】通用分享链接展示函数 ====================
show_protocol_info() {
    local protocol_type=$1   # vision / xhttp / ws / grpc / trojan 等
    local uuid=$2
    local extra1=$3
    local extra2=$4
    local extra3=$5
    local extra4=$6

    local ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name="${protocol_type}_${extra1}_$(date +%Y%m%d)"

    local link=""

case "$protocol_type" in
        "REALITY-Vision")
            # 协议1：VLESS-REALITY-Vision
            link="vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$extra1&fp=chrome&pbk=$extra2&sid=$extra3&type=tcp#$ps_name"
            ;;
        "REALITY-xHTTP")
            # 协议2：VLESS-REALITY-xhttp
            link="vless://$uuid@$ip:443?encryption=none&security=reality&sni=$extra1&fp=chrome&pbk=$extra2&sid=$extra3&type=xhttp&path=%2F$extra4#$ps_name"
            ;;
        "VLESS-XHTTP")
            # 协议5：VLESS-XHTTP-TLS (修复重点：精准指定传输类型为 xhttp 并带上 path)
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=xhttp&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=h2%2Chttp%2F1.1#$ps_name"
            ;;
        "VLESS-WS")
            # 协议3：VLESS-WS-TLS
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=ws&host=$extra1&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=http/1.1#$ps_name"
            ;;
        "VLESS-gRPC")
            # 协议4：VLESS-gRPC-TLS
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=grpc&host=$extra1&serviceName=$extra2&sni=$extra1&fp=chrome&alpn=h2#$ps_name"
            ;;
        "Trojan-WS")
            # 协议6：Trojan-WS-TLS (修复重点：Trojan 协议前缀为 trojan:// 且无 encryption 参数)
            link="trojan://$uuid@$extra1:443?security=tls&type=ws&host=$extra1&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=http/1.1#$ps_name"
            ;;
        "Trojan-gRPC")
            # 协议7：Trojan-gRPC-TLS (修复重点：Trojan 协议前缀为 trojan:// 且无 encryption 参数)
            link="trojan://$uuid@$extra1:443?security=tls&type=grpc&host=$extra1&serviceName=$extra2&sni=$extra1&fp=chrome&alpn=h2#$ps_name"
            ;;
        *)
            # 兜底通用逻辑
            link="vless://$uuid@$ip:443?encryption=none&security=tls&type=$protocol_type#$ps_name"
            ;;
    esac

    echo -e "${Font_Green}${protocol_type} 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址:${Font_Suffix} $ip"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}


#合并所有show代码结束

show_qr_code() {
    local link=$1
    if command -v qrencode &> /dev/null; then
        echo -e "${Font_Cyan}手机客户端扫描二维码:${Font_Suffix}"
        echo "$link" | qrencode -t utf8
    else
        echo -e "${Font_Red}提示: qrencode 未安装，无法生成二维码。${Font_Suffix}"
    fi
}

# === 完完整整地补回被删除的 VMess 展现函数，保持你原本的风格定义变量和输出 ===
show_vmess_ws_info() {
    local ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name="VMess_WS_${DOMAIN}_$(date +%Y%m%d)"
    
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${ps_name}",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "/${WPATH}",
  "tls": "tls",
  "sni": "${DOMAIN}",
  "alpn": "http/1.1"
}
EOF
)
    local b64_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"

    echo -e "${Font_Green}VMess-WS-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $DOMAIN"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $UUID"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$WPATH"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo "$b64_link"
    show_qr_code "$b64_link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_vmess_grpc_info() {
    local ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name="VMess_gRPC_${DOMAIN}_$(date +%Y%m%d)"
    
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${ps_name}",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "grpc",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "${WPATH}",
  "tls": "tls",
  "sni": "${DOMAIN}",
  "alpn": "h2"
}
EOF
)
    local b64_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"

    echo -e "${Font_Green}VMess-gRPC-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $DOMAIN"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $UUID"
    echo -e "${Font_Cyan}服务名:${Font_Suffix} $WPATH"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo "$b64_link"
    show_qr_code "$b64_link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_usage() {
    echo -e "${Font_Magenta}--- 流量统计看板 ---${Font_Suffix}"
    if ! command -v vnstat &> /dev/null; then
        echo -e "${Font_Yellow}检测到 vnstat 未安装，正在尝试安装...${Font_Suffix}"
        apt-get update && apt-get install -y vnstat
        systemctl enable vnstat --now
    fi
    if command -v vnstat &> /dev/null; then
        vnstat -d && vnstat -m
    else
        echo -e "${Font_Red}错误: vnstat 不可用。${Font_Suffix}"
    fi
    read -p "按回车键返回主菜单"
}

# ==================== 彻底卸载功能（已优化） ====================
uninstall_all() {
    echo -e "${Font_Red}⚠️ 警告：此操作将彻底卸载 Xray + Caddy 并清理所有配置和日志！${Font_Suffix}"
    read -p "确定要继续吗？(y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${Font_Green}已取消卸载。${Font_Suffix}"
        read -p "按回车键返回主菜单"
        return
    fi

    echo -e "${Font_Cyan}>>> 开始执行彻底卸载...${Font_Suffix}"

    # 停止服务
    systemctl stop xray caddy 2>/dev/null || true
    systemctl disable xray caddy 2>/dev/null || true

    # 调用官方彻底卸载脚本（推荐 --purge）
    if command -v xray &> /dev/null; then
        echo -e "${Font_Cyan}>>> 调用官方 Xray 彻底卸载脚本 (--purge)...${Font_Suffix}"
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) remove --purge
    fi

    # 清理 Caddy
    echo -e "${Font_Cyan}>>> 清理 Caddy...${Font_Suffix}"
    apt-get purge -y caddy 2>/dev/null || true
    rm -rf /etc/caddy /var/log/caddy /root/.config/caddy /usr/share/caddy 2>/dev/null

    # 额外深度清理（防止残留）
    echo -e "${Font_Cyan}>>> 深度清理残留文件...${Font_Suffix}"
    rm -rf /usr/local/bin/xray \
           /usr/local/etc/xray \
           /usr/local/share/xray \
           /var/log/xray \
           /etc/systemd/system/xray.service \
           /etc/systemd/system/xray@*.service \
           /etc/apt/sources.list.d/caddy-stable.list \
           /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
           ~/.acme.sh 2>/dev/null || true

    # 删除 xray 用户（可选，谨慎）
    userdel -r xray 2>/dev/null || true

    systemctl daemon-reload
    echo -e "${Font_Green}✅ 彻底卸载完成！系统已清理干净。${Font_Suffix}"
    read -p "按回车键返回主菜单"
}

# --- 主菜单（保留原样，仅加强调用）---
main_menu() {
    clear
    echo -e "${Font_Magenta}======================= 系统状态检查 ======================${Font_Suffix}"
    # 1、vnstat 流量统计状态
    if command -v vnstat &> /dev/null && systemctl is-active --quiet vnstat; then
        echo -e "   流量统计 : ${Font_Green}监控中 ✅${Font_Suffix}"
    elif command -v vnstat &> /dev/null; then
        echo -e "   流量统计 : ${Font_Yellow}已安装但未启动${Font_Suffix}"
    else
        echo -e "   流量统计 : ${Font_Red}未安装 ❌ ${Font_Suffix}"
    fi
    
    # 2、BBR 状态
    local bbr_status
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        bbr_status="${Font_Green}运行中 ✅${Font_Suffix}"
    else
        bbr_status="${Font_Red}未开启 ❌ ${Font_Suffix}"
    fi
    echo -e "   BBR 状态 : ${bbr_status}"  
    
    # 3、xray状态
    local xray_installed=false
    local xray_active=false

    if [ -f "/etc/systemd/system/xray.service" ] || systemctl list-unit-files | grep -q "xray.service"; then
        xray_installed=true
    fi

    if command -v xray &> /dev/null && [ -f "${config_path}" ]; then
        if systemctl is-active --quiet xray; then
            xray_active=true
        fi
    fi

    if [[ "$xray_installed" == true && "$xray_active" == true ]]; then
        echo -e "   Xray 服务: ${Font_Green}运行中 ✅${Font_Suffix}"
    elif [[ "$xray_installed" == true ]]; then
        echo -e "   Xray 服务: ${Font_Yellow}已安装但未运行${Font_Suffix}"
    else
        echo -e "   Xray 服务: ${Font_Red}未安装 ❌ ${Font_Suffix}"
    fi 
    # 4、当前安装的协议
    if [[ -f $config_path ]]; then
        local current_proto="未知"
        if grep -q "realitySettings" $config_path; then
            if grep -q '"network": "xhttp"' $config_path; then
                current_proto="VLESS-REALITY-xhttp"
            elif grep -q "xtls-rprx-vision" $config_path; then
                current_proto="VLESS-REALITY-Vision"
            else
                current_proto="VLESS-REALITY"
            fi
        elif grep -q '"protocol": "trojan"' $config_path; then
            if grep -q '"network": "ws"' $config_path; then 
                current_proto="Trojan-WS-TLS"
            elif grep -q '"network": "grpc"' $config_path; then 
                current_proto="Trojan-gRPC-TLS"
            fi
        elif grep -q '"protocol": "vmess"' $config_path; then
            if grep -q '"network": "ws"' $config_path; then 
                current_proto="VMess-WS-TLS"
            elif grep -q '"network": "grpc"' $config_path; then 
                current_proto="VMess-gRPC-TLS"
            fi
        elif grep -q '"protocol": "vless"' $config_path; then
            local net=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+' || echo "")
            case "${net,,}" in
                ws)    current_proto="VLESS-WS-TLS" ;;
                grpc)  current_proto="VLESS-gRPC-TLS" ;;
                xhttp) current_proto="VLESS-XHTTP-TLS" ;;
                *)     current_proto="VLESS-${net^^}" ;;
            esac
        fi
        echo -e "   当前协议 : ${Font_Green}${current_proto}${Font_Suffix}"
    else
        echo -e "   当前协议 : ${Font_Red}未配置 ❌ ${Font_Suffix}"
    fi
    # 5、当前IP地址
    local local_ip=$(curl -4 -s --connect-timeout 2 ip.sb || curl -s --connect-timeout 2 http://ipv4.icanhazip.com || echo "获取失败")
    echo -e "   本机 IP  : ${Font_Green}${local_ip}${Font_Suffix}"  
    
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${Font_Red}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}   作者：人生若只如初见，更新：2026/05/18   ${Font_Suffix}"
    echo -e "${Font_Red}   名称：xray 一键安装脚本    ${Font_Suffix}"
    echo -e "${Font_Red}   版本号：v1.0.05.18.13.22（Release）    ${Font_Suffix}"
    echo -e "${Font_Red}   适用环境：Debian12/13、Ubuntu25/26    ${Font_Suffix}"
    echo -e "${Font_Red}   当前系统：${Font_Suffix}${Font_Green}$OS_NAME    ${Font_Suffix}"
    echo -e "-----------------------------------------------------------"
    echo -e "${Font_Blue}  【1】 . 安装 VLESS-REALITY-Vision${Font_Suffix}   ${Font_Red}【推荐，最强隐蔽/不依赖域名】${Font_Suffix}"
    echo -e "${Font_Blue}  【2】 . 安装 VLESS-REALITY-xhttp${Font_Suffix}    ${Font_Cyan}【最新黑科技/综合最强】${Font_Suffix}"   
    echo -e "${Font_Blue}  【3】 . 安装 VLESS-WS-TLS${Font_Suffix}           ${Font_Cyan}【CDN兼容/标准WebSocket】${Font_Suffix}"
    echo -e "${Font_Blue}  【4】 . 安装 VLESS-gRPC-TLS${Font_Suffix}         ${Font_Cyan}【低延迟/多路复用】${Font_Suffix}"
    echo -e "${Font_Blue}  【5】 . 安装 VLESS-XHTTP-TLS${Font_Suffix}        ${Font_Cyan}【流式传输/防指纹】${Font_Suffix}"
    echo -e "${Font_Blue}  【6】 . 安装 Trojan-WS-TLS${Font_Suffix}          ${Font_Cyan}【仿HTTPS/老牌稳定】${Font_Suffix}"
    echo -e "${Font_Blue}  【7】 . 安装 Trojan-gRPC-TLS${Font_Suffix}        ${Font_Cyan}【高效转发/适合游戏】${Font_Suffix}"
    echo -e "${Font_Blue}  【8】 . 安装 VMess-WS-TLS${Font_Suffix}           ${Font_Yellow}【广泛兼容/传统方案】${Font_Suffix}"
    echo -e "${Font_Blue}  【9】 . 安装 VMess-gRPC-TLS${Font_Suffix}         ${Font_Yellow}【兼容gRPC新特性】${Font_Suffix}"
  
    echo -e "-----------------------------------------------------------"
    echo -e "${Font_Magenta}  【c】 . 查看当前协议信息与链接${Font_Suffix}" 
    echo -e "${Font_Magenta}  【v】 . 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Magenta}  【b】 . 管理网络加速 (BBR)${Font_Suffix}"
    echo -e "${Font_Green}  【d】 . 卸载与清理${Font_Suffix}"
    echo -e "${Font_Yellow}  【q】 . 退出脚本${Font_Suffix}" 
    echo -e "-----------------------------------------------------------"
    read -p "请选择: " num

    case "$num" in
        1) gen_vless_reality_unified "vision" ;;
        2) gen_vless_reality_unified "xhttp" ;;
        3) preparation_stack; gen_vless_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        4) preparation_stack; gen_vless_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        5) preparation_stack; gen_vless_xhttp; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        6) preparation_stack; gen_trojan_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        7) preparation_stack; gen_trojan_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        8) preparation_stack; gen_vmess_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        9) preparation_stack; gen_vmess_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        c|C) check_current_protocol; main_menu ;;
        v|V) show_usage; main_menu ;;
        b|B) menu_bbr; main_menu ;;
        d|D) uninstall_all; main_menu ;;
        q|Q) exit 0 ;;
        *) echo -e "${Font_Red}输入错误，请重新选择！${Font_Suffix}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
check_root
main_menu