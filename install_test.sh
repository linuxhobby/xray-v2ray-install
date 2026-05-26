#!/bin/bash

# ====================== 统一颜色管理 =======================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
NC='\033[0m'

# ====================== 协议配置中心（核心数据驱动）======================
# 格式: "编号|协议全称|network|inbound_proto|显示名称|是否需要密码(1=是)|端口|生成函数"
declare -A PROTOCOL_CONFIG
PROTOCOL_CONFIG[1]="1|REALITY-Vision|tcp|vless|REALITY-Vision|0|443|gen_vless_reality_unified vision"
PROTOCOL_CONFIG[2]="2|REALITY-xHTTP|xhttp|vless|REALITY-xHTTP|0|443|gen_vless_reality_unified xhttp"
PROTOCOL_CONFIG[3]="3|VLESS-WS-TLS|ws|vless|VLESS-WS-TLS|0|10001|gen_vless_ws"
PROTOCOL_CONFIG[4]="4|VLESS-gRPC-TLS|grpc|vless|VLESS-gRPC-TLS|0|10002|gen_vless_grpc"
PROTOCOL_CONFIG[5]="5|VLESS-XHTTP-TLS|xhttp|vless|VLESS-XHTTP-TLS|0|10003|gen_vless_xhttp"
PROTOCOL_CONFIG[6]="6|Trojan-WS-TLS|ws|trojan|Trojan-WS-TLS|1|10004|gen_trojan_ws"
PROTOCOL_CONFIG[7]="7|Trojan-gRPC-TLS|grpc|trojan|Trojan-gRPC-TLS|1|10005|gen_trojan_grpc"
PROTOCOL_CONFIG[8]="8|VMess-WS-TLS|ws|vmess|VMess-WS-TLS|0|10006|gen_vmess_ws"
PROTOCOL_CONFIG[9]="9|VMess-gRPC-TLS|grpc|vmess|VMess-gRPC-TLS|0|10007|gen_vmess_grpc"


# ====================== 架构检测，如果不支持，直接不运行 ======================
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)   XRAY_ARCH="64" ;;
    aarch64)  XRAY_ARCH="arm64" ;;
    armv7l)   XRAY_ARCH="arm32-v7a" ;;
    armv8l)   XRAY_ARCH="arm64" ;;
    *)        echo -e "${RED}不支持的架构: ${ARCH}${NC}"; exit 1 ;;
esac
echo -e "${CYAN}检测到系统架构: ${ARCH} (${XRAY_ARCH})${NC}"

# # ====================== 严格模式 + 错误追踪 ======================
set -e
set -o pipefail
# 捕获错误，打印行号和出错命令
trap 'echo -e "\n${RED}[ERROR] 脚本在第 $LINENO 行执行失败！\n出错命令: $BASH_COMMAND${NC}"' ERR

# ------------- 全局变量定义区域 SRTART -------------
is_core="xray"
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
PRESET_DOMAIN="cc.myvpsworld.top" #如果为空，安装过程中手动输入
XRAY_VERSION="26.5.3"   #最新版 latest
CADDY_VERSION="2.11.2"
FIX_VER=1 #1，锁定。0，最新版#

# Reality 伪装域名配置（随机选择）
REALITY_DEST_OPTIONS=(
    "www.microsoft.com"          # 微软，极稳定
    "www.apple.com"              # 苹果，极稳定
    "www.bing.com"               # 微软搜索，直连很好
    "www.cloudflare.com"         # Cloudflare
    "www.amazon.com"             # 亚马逊
    "www.adobe.com"              # Adobe
    "www.oracle.com"             # Oracle
    "www.ibm.com"                # IBM
    "www.cisco.com"              # Cisco
)

# ------------- 全局变量定义区域 END；自定义函数区域 SRTART -------------
# 自定义函数：随机选择函数
get_random_dest() {
    local idx=$((RANDOM % ${#REALITY_DEST_OPTIONS[@]}))
    echo "${REALITY_DEST_OPTIONS[$idx]}"
}
# 自定义函数：检查当前 user root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}必须以 root 权限运行此脚本！${NC}"
        exit 1
    fi
}

# 自定义函数：错误信息检查（519修改）
check_command() {
    local cmd=("$@")
    if ! "${cmd[@]}"; then
        echo -e "${RED}[ERROR] 命令执行失败: ${cmd[*]}${NC}" >&2
        echo -e "${RED}输出日志：${NC}" >&2
        journalctl -u xray -x --no-pager -n 100 2>/dev/null | tail -100 || true
        journalctl -u caddy -x --no-pager -n 100 2>/dev/null | tail -100 || true
        return 1
    fi
}

# 自定义函数：IP检测（519新增）
get_local_ip() {
    local ip
    local timeout=5
    local services=(
        "https://4.ipw.cn"
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://icanhazip.com"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -4 -s --connect-timeout $timeout --max-time $((timeout+2)) "$service" 2>/dev/null | tr -d '[:space:]')
        
        # 验证是否是合法的IPv4
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # 都失败，尝试从本地网络获取
    local_ip=$(hostname -I | awk '{print $1}')
    if [[ -n "$local_ip" ]]; then
        echo "$local_ip"
        return 0
    fi
    
    echo "获取失败"
    return 1
}

# 自定义函数：建立xray用户和权限（519修改）
setup_xray_user() {
    if ! id xray &>/dev/null; then
        useradd -r -s /bin/false -U xray || {
            echo -e "${RED}[ERROR] 创建xray用户失败${NC}" >&2
            return 1
        }
    fi
    
    mkdir -p "$conf_dir" || {
        echo -e "${RED}[ERROR] 创建目录 $conf_dir 失败${NC}" >&2
        return 1
    }
    
    if ! chown -R xray:xray "$conf_dir"; then
        echo -e "${RED}[ERROR] 设置目录权限失败${NC}" >&2
        return 1
    fi
}

# 自定义函数：TLS 类协议公共准备（减少少量重复）
common_tls_setup() {
    install_caddy
}

restart_service() {
    local svc=$1
    systemctl restart "$svc"
    if ! systemctl is-active --quiet "$svc"; then
        echo -e "${RED}[ERROR] $svc 启动失败${NC}"
        systemctl status "$svc" --no-pager
        exit 1
    fi
}

#自定义函数：JSON 校验函数
check_json() {
    local file=$1

    if ! command -v python3 &>/dev/null; then
        echo -e "${YELLOW}[WARN] 未安装 python3，跳过 JSON 校验${NC}"
        return 0
    fi

    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] config.json 格式错误：$file${NC}"
        python3 -m json.tool "$file" || true
        exit 1
    fi
}

#自定义函数：端口检测函数（519修改）
check_port() {
    local port=$1
    
    # 先用netstat，再用ss，再用lsof
    if command -v ss &>/dev/null; then
        if ss -tlnp 2>/dev/null | grep -E ":\s*$port\s" >/dev/null; then
            echo -e "${RED}[ERROR] 端口 $port 已被占用：${NC}" >&2
            ss -tlnp | grep -E ":\s*$port\s"
            return 1
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -E ":\s*$port\s" >/dev/null; then
            echo -e "${RED}[ERROR] 端口 $port 已被占用：${NC}" >&2
            netstat -tlnp | grep -E ":\s*$port\s"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARN] 无法检查端口 $port (ss/netstat不可用)${NC}"
    fi
}

#自定义函数：Caddy 配置检查函数
check_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo -e "${RED}[ERROR] Caddy 未安装${NC}"
        exit 1
    fi

    # 检查配置语法
    if ! caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Caddyfile 语法错误${NC}"
        caddy validate --config /etc/caddy/Caddyfile
        exit 1
    fi
}
#自定义函数：服务端口存活检查函数（519修改）
check_service_alive() {
    local port=$1
    local name=$2
    
    if [[ "$name" == *REALITY* ]]; then
        echo -e "${YELLOW}Reality 协议 → 跳过本地端口检查${NC}"
        return 0
    fi
    
    if ! systemctl is-active --quiet xray; then
        echo -e "${RED}[ERROR] xray 未运行${NC}" >&2
        return 1
    fi
    
    # 尝试TCP连接（支持多种方式）
    local connected=false
    
    if command -v nc &>/dev/null; then
        timeout 5 nc -z 127.0.0.1 "$port" &>/dev/null && connected=true
    elif bash --version >/dev/null 2>&1; then
        timeout 5 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" &>/dev/null && connected=true
    elif command -v telnet &>/dev/null; then
        timeout 5 telnet 127.0.0.1 "$port" </dev/null &>/dev/null && connected=true
    fi
    
    if [[ "$connected" == true ]]; then
        echo -e "${GREEN}[OK] $name 服务正常 ($port)${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] $name TCP 不可达: $port${NC}" >&2
        return 1
    fi
}

#自定义函数：TCP检查
check_external_tcp() {
    local host=$1
    local port=$2

    if [[ "${protocol_type:-}" == *REALITY* ]]; then
        echo -e "${YELLOW}Reality 协议 → 跳过外网检查${NC}"
        return 0
    fi

    if timeout 4 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}[OK] 外网TCP可达：$host:$port${NC}"
    else
        echo -e "${RED}[ERROR] 外网不可达：$host:$port${NC}"
        exit 1
    fi
}

#  自定义函数：依赖检查函数（519修改）
check_dependencies() {
    echo -e "${CYAN}>>> 检查系统依赖...${NC}"
    
    # 基础依赖
    local base_deps=(curl openssl wget tar unzip)
    
    # 可选依赖
    local optional_deps=(qrencode vnstat gnupg2)
    
    # 先更新apt缓存
    apt-get update -qq || {
        echo -e "${RED}[ERROR] apt-get update 失败${NC}" >&2
        return 1
    }
    
    local failed=0
    for dep in "${base_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            if ! apt-get install -y "$dep" -qq; then
                echo -e "${RED}[ERROR] 安装 $dep 失败${NC}" >&2
                failed=$((failed + 1))
            fi
        fi
    done
    
    # 可选依赖安装失败只警告
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            if ! apt-get install -y "$dep" -qq 2>/dev/null; then
                echo -e "${YELLOW}[WARN] 安装可选依赖 $dep 失败${NC}"
            fi
        fi
    done
    
    if [ $failed -gt 0 ]; then
        echo -e "${RED}[ERROR] 有 $failed 个基础依赖安装失败${NC}" >&2
        return 1
    fi
}

# 自定义函数：强制开启防火墙函数
enable_firewall() {
    echo -e "${CYAN}>>> 配置防火墙...${NC}"

    if [[ "${SKIP_FIREWALL}" == "true" ]]; then
        echo -e "${YELLOW}已跳过防火墙配置。${NC}"
        return 0
    fi

    # 智能检测及安装逻辑
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu 系列优先使用 ufw
        if ! command -v ufw >/dev/null 2>&1; then
            echo -e "${CYAN}未检测到 ufw，正在安装...${NC}"
            apt-get update -y && apt-get install -y ufw
        fi
        
        # 配置 ufw
        ufw --force reset >/dev/null 2>&1
        ufw default allow outgoing
        ufw default deny incoming
        
        local ssh_port
        ssh_port=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | cut -d: -f2 | head -n1)
        [[ -z "$ssh_port" ]] && ssh_port=$(grep -E '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        
        ufw limit "$ssh_port/tcp" comment 'SSH'
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 443/udp
        
        echo "y" | ufw enable >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
        echo -e "${GREEN}[OK] ufw 配置完成（SSH端口: ${ssh_port}）${NC}"

    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL/Fedora 系列优先使用 firewalld
        local pkg_manager
        pkg_manager=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
        
        if ! command -v firewall-cmd >/dev/null 2>&1; then
            echo -e "${CYAN}未检测到 firewalld，正在安装...${NC}"
            $pkg_manager install -y firewalld
        fi
        
        systemctl enable --now firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=443/udp
        firewall-cmd --reload
        echo -e "${GREEN}[OK] firewalld 配置完成${NC}"
    else
        echo -e "${RED}[ERROR] 未知的操作系统类型，无法自动安装防火墙。${NC}"
        return 1
    fi
}

# 自定义函数：时区检查函数
check_and_set_timezone() {
    local current_tz
    current_tz=$(timedatectl | grep "Time zone" | awk '{print $3}' 2>/dev/null || date +%Z)
    
    local current_time
    current_time=$(date "+%Y-%m-%d %H:%M:%S")

    echo -e "${CYAN}当前系统时间: ${GREEN}${current_time}${NC}"
    echo -e "   当前时区 : ${GREEN}${current_tz}${NC}"

    if [[ "$current_tz" == "Asia/Shanghai" ]]; then
        echo -e "${GREEN}   状态确认 : 已是 Asia/Shanghai 时区，无需修改。${NC}"
    else
        echo -e "${YELLOW}   建议提示 : 当前非上海时区，建议修改以确保日志时间准确。${NC}"
        read -r -p ">>> 是否修改时区为 Asia/Shanghai？(y/N): " change_tz
        if [[ "$change_tz" == "y" || "$change_tz" == "Y" ]]; then
            timedatectl set-timezone Asia/Shanghai 2>/dev/null || (rm -f /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime)
            echo -e "${GREEN}[OK] 时区已成功修改为 Asia/Shanghai，当前时间: $(date "+%Y-%m-%d %H:%M:%S")${NC}"
        fi
    fi
}


# 自定义函数：开启BBR
enable_bbr() {
    echo -e "${CYAN}>>> 检查并开启 BBR 网络加速...${NC}"
    
    # 1. 判断当前是否已经开启 BBR
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        echo -e "${GREEN}[INFO] BBR 加速已在运行中，无需重复开启。${NC}"
    else
        echo -e "${YELLOW}[ACTION] 正在配置 BBR 参数...${NC}"
        
        # 确保 sysctl.conf 文件存在
        [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf
        
        # 2. 备份 sysctl.conf (仅在文件存在时备份)
        [ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf /etc/sysctl.conf.bak
        
        # 3. 写入内核参数
        # 先清理可能存在的旧配置，防止重复写入
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        
        # 写入新配置
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        
        # 4. 生效配置
        sysctl -p >/dev/null 2>&1
        
        # 5. 最终验证
        if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
            echo -e "${GREEN}[OK] BBR 加速已成功开启！${NC}"
        else
            echo -e "${RED}[ERROR] BBR 开启失败，请检查系统内核版本是否支持 (建议 4.9+)。${NC}"
        fi
    fi
}

# ------------- 自定义函数区域 END；BBR 管理子菜单 START -------------
# BBR 管理子菜单
menu_bbr() {
    clear
    # 1. 获取内核版本
    local kernel_version
    kernel_version=$(uname -r)
    
    local current_algo
    current_algo=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}' 2>/dev/null || echo "未知")
    
    local ver_main
    ver_main=$(echo "$kernel_version" | cut -d. -f1)
    
    local ver_sub
    ver_sub=$(echo "$kernel_version" | cut -d. -f2)
    # 2. 获取当前拥塞控制算法
    local current_algo
    current_algo=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}' 2>/dev/null || echo "未知")
    
    # 3. 判定 BBRv3 兼容性 (内核 >= 6.4)
    local v3_support
    v3_support="${RED}不支持 v3${NC}"
    
    local ver_main
    ver_main=$(echo "$kernel_version" | cut -d. -f1)
    
    local ver_sub
    ver_sub=$(echo "$kernel_version" | cut -d. -f2)
    if [ "$ver_main" -gt 6 ] || { [ "$ver_main" -eq 6 ] && [ "$ver_sub" -ge 4 ]; }; then
        v3_support="${GREEN}支持 v3${NC}"
    fi

    # 4. 判定显示状态
    local bbr_status
    if [[ "$current_algo" == "bbr" ]]; then
        bbr_status="${GREEN}运行中 (BBR/v1/v3)${NC}"
    elif [[ "$current_algo" == "bbrplus" ]]; then
        bbr_status="${GREEN}运行中 (BBRplus)${NC}"
    else
        bbr_status="${RED}未开启 ($current_algo)${NC}"
    fi

    echo -e "${MAGENTA}======================= BBR 网络加速管理 ======================${NC}"
    echo -e "   当前内核 : ${CYAN}${kernel_version}${NC} ($v3_support)"
    echo -e "   当前状态 : ${bbr_status}"
    echo -e "   当前算法 : ${CYAN}${current_algo}${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"
    echo -e "  【1】 . 开启 BBR 原版 (v1 - 最稳定)"
    echo -e "  【2】 . 开启 BBRv3 (需内核 6.4+)"
    echo -e "  【3】 . 开启 BBRplus (需更换内核，${RED}有风险${NC})"
    echo -e "  【4】 . 关闭 BBR (恢复系统默认 cubic)"
    echo -e "  【q】 . 返回主菜单"
    echo -e "${MAGENTA}===========================================================${NC}"
    read -r -p "请选择: " bbr_num

    case "$bbr_num" in
        1|2) # v1 和 v3 在操作上是统一的，取决于内核版本
            enable_bbr_native
            read -r -p "按回车键继续..."; menu_bbr ;;
        3) install_bbr_plus; read -r -p "按回车键继续..."; menu_bbr ;;
        4) disable_bbr; read -r -p "按回车键继续..."; menu_bbr ;;
        q|Q) main_menu ;;
        *) menu_bbr ;;
    esac
}

# 统筹开启内核原生 BBR (包含 v1/v3)
enable_bbr_native() {
    echo -e "${CYAN}>>> 正在配置内核 BBR 参数...${NC}"
    
    # 修复：确保文件存在，防止 sed 报错
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}[OK] BBR 指令已发送。如果内核版本 >= 6.4，将自动以 v3 运行。${NC}"
}

# 开启 BBRplus
install_bbr_plus() {
    echo -e "${RED}警告：开启 BBRplus 需要下载第三方内核并重启服务器！${NC}"
    echo -e "${YELLOW}注意：在 Debian 12+ / Ubuntu 24+ 上更换旧内核可能导致无法开机，请务必确认有 VNC 访问权限。${NC}"
    read -r -p "确定要继续吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        # 替换为目前仍然有效的全能加速脚本
        wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
    fi
}

# 关闭 BBR
disable_bbr() {
    echo -e "${CYAN}>>> 正在恢复默认拥塞控制算法 (cubic)...${NC}"
    
    # 修复：确保文件存在
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1
    echo -e "${YELLOW}[OK] BBR 已关闭。${NC}"
}

# ------------- BBR 管理子菜单 START -------------
# --- 1. 环境准备模块 ---
preparation_stack() {
    check_root
    setup_xray_user

    # === 时区处理（改为可选，不再强制）===
    check_and_set_timezone

    echo -e "${CYAN}>>> 正在处理 apt 锁...${NC}"
    apt-get -o DPkg::Lock::Timeout=180 update --allow-releaseinfo-change -qq || true
    dpkg --configure -a
    
    # 调用防火墙策略函数
    enable_firewall
    # 调用依赖检查函数
    check_dependencies
    # 调用开启BBR函数
    enable_bbr

    systemctl enable vnstat --now 2>/dev/null || true

    # ==================== Xray 安装 ====================
    # 安装 Xray（安全方式：先下载再执行）
    if ! command -v xray &> /dev/null || [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo -e "${CYAN}>>> 正在安装 Xray v${XRAY_VERSION}...${NC}"
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
        
        echo -e "${GREEN}[OK] Xray v${XRAY_VERSION} 安装完成（已屏蔽无效启动告警）${NC}"
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

    echo -e "${GREEN}[OK] 环境准备完成（Xray 服务已启用，等待配置生成后启动）${NC}"
}

# --- 1.5. Caddy 安装函数（完全保留）---
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        echo -e "${CYAN}正在安装 Caddy v${CADDY_VERSION}...${NC}"
        
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list

        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        
        check_command apt-get update -qq
        check_command apt-get install caddy=${CADDY_VERSION} -y || check_command apt-get install caddy -y

        if [ "$FIX_VER" -eq 1 ] && command -v caddy &> /dev/null; then
            apt-mark hold caddy
        fi

        if ! command -v caddy &> /dev/null; then
            echo -e "${RED}[X] Caddy 安装失败！${NC}"
            exit 1
        fi
        echo -e "${GREEN}[OK] Caddy 安装成功${NC}"
    fi
    mkdir -p /etc/caddy
}

# --- 域名解析检测（优化版）---
check_domain() {
    local domain=""
    while true; do
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -r -p "请输入您的解析域名后回车 [默认域名: $PRESET_DOMAIN]: " domain
            domain=${domain:-$PRESET_DOMAIN}
        else
            read -r -p "请输入您的解析域名: " domain
        fi

        if [[ -z "$domain" ]]; then continue; fi

        local local_ipv4
        local_ipv4=$(get_local_ip)
        
        if [[ -z "$local_ipv4" ]]; then
            echo -e "${RED}[ERROR] 获取本机 IP 失败${NC}"
            exit 1
        fi
        
        local local_ipv6
        local_ipv6=$(curl -6 -s --connect-timeout 5 ip.sb || echo "")
        
        local resolved_ips
        resolved_ips=$(dig +short "$domain" A 2>/dev/null)
        
        echo -e "${CYAN}本机 IPv4: $local_ipv4${NC}"
        echo -e "${CYAN}本机 IPv6: $local_ipv6${NC}"
        if [[ -n "$resolved_ips" ]]; then
            echo -e "${CYAN}域名解析地址:${NC}\n$resolved_ips"
        else
            echo -e "${YELLOW}警告: 未能获取该域名的解析记录。${NC}"
        fi

        local pass=0
        for rip in $resolved_ips; do
            if [[ -n "$local_ipv4" && "$rip" == "$local_ipv4" ]] || [[ -n "$local_ipv6" && "$rip" == "$local_ipv6" ]]; then
                pass=1
                break
            fi
        done

        if [[ $pass -eq 1 ]]; then
            echo -e "${GREEN}检测通过：域名已正确解析到本机 IP。${NC}"
            echo "$domain" > /tmp/domain
            export domain
            break
        else
            echo -e "${RED}错误: 域名解析地址与本机 IP 不符！${NC}"
            echo -e "${YELLOW}1. 重新输入 | 2. 强制跳过 (适合已开启 CDN 的域名)${NC}"
            read -r -p "请选择: " retry_choice
            [[ "$retry_choice" == "2" ]] && break
        fi
    done
}

# --- 查看当前协议（优化版）---
check_current_protocol() {
    if [[ ! -f $config_path ]]; then
        echo -e "${RED}错误: 未检测到配置文件 ($config_path)，请先安装协议。${NC}"
        read -r -p "按回车键返回主菜单"
        return
    fi

    echo -e "${MAGENTA}--- 当前协议详细信息 ---${NC}"
    
    local uuid
    uuid=$(grep -m1 '"id":' $config_path | grep -oP '(?<="id": ")[^"]+' || grep -m1 '"password":' $config_path | grep -oP '(?<="password": ")[^"]+')
    
    local network
    network=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+')
    
    local ip
    ip=$(curl -4 -s --connect-timeout 5 ip.sb || curl -s http://ipv4.icanhazip.com)
    
    local domain=""
    if [[ -f "/etc/caddy/Caddyfile" ]]; then
        domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
    fi
    [[ -z "$domain" ]] && domain=$(grep -oP '(?<="serverNames": \[")[^"]+' $config_path | head -n1)
    [[ -z "$domain" ]] && domain=$ip

    # === 修复后的判断逻辑 ===
    if grep -q "realitySettings" $config_path; then
        local pub_key
        pub_key=$(cat ${conf_dir}/pub.key 2>/dev/null || echo "未找到公钥文件")
        
        local short_id
        short_id=$(grep -m1 '"shortIds":' $config_path | grep -oP '(?<="shortIds": \[").*(?="])' | cut -d'"' -f1)
        
        local sni
        sni=$(grep -m1 '"serverNames":' $config_path | grep -oP '(?<="serverNames": \[").*(?="])' | cut -d'"' -f1)
        
        if grep -q "xhttpSettings" $config_path; then
            local path
            path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
            show_protocol_info "REALITY-xHTTP" "$uuid" "$sni" "$pub_key" "$short_id" "$path"
        else
            show_protocol_info "REALITY-Vision" "$uuid" "$sni" "$pub_key" "$short_id"
        fi

    elif [[ "$network" == "ws" ]]; then
        local path
        path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        
        if grep -q '"protocol": "trojan"' $config_path; then
            show_protocol_info "Trojan-WS" "$uuid" "$domain" "$path"
        elif grep -q '"protocol": "vmess"' $config_path; then
            export DOMAIN="$domain"
            export UUID="$uuid"
            export WPATH="$path"
            show_vmess_ws_info
        else
            show_protocol_info "VLESS-WS" "$uuid" "$domain" "$path"
        fi

    elif [[ "$network" == "grpc" ]]; then
        local serviceName
        serviceName=$(grep -m1 '"serviceName":' $config_path | grep -oP '(?<="serviceName": ")[^"]+')
        
        if grep -q '"protocol": "trojan"' $config_path; then
            show_protocol_info "Trojan-gRPC" "$uuid" "$domain" "$serviceName"
        elif grep -q '"protocol": "vmess"' $config_path; then
            export DOMAIN="$domain"
            export UUID="$uuid"
            export WPATH="$serviceName"
            show_vmess_grpc_info
        else
            show_protocol_info "VLESS-gRPC" "$uuid" "$domain" "$serviceName"
        fi

    elif [[ "$network" == "xhttp" ]]; then
        local path
        path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        show_protocol_info "VLESS-XHTTP" "$uuid" "$domain" "$path"

    else
        echo -e "${RED}未能识别协议类型。${NC}"
    fi
    
    echo -e "${YELLOW}-----------------------------------------------------------${NC}"
    read -r -p "按回车键返回主菜单"
}
# ------------------------------------------------ 核心协议模块 ------------------------------------------------
gen_vless_reality_unified() {
    local mode="$1"

    # ==================== 公共初始化 ====================
    echo -e "${CYAN}正在配置 VLESS-REALITY-${mode^}...${NC}"

    local flow=""
    local network="tcp"
    local extra_settings=""
    local path=""

    if [ "$mode" = "xhttp" ]; then
        network="xhttp"
        path=$(openssl rand -hex 6)
        extra_settings='"xhttpSettings": {"path": "/'"$path"'", "mode": "auto"},'
    else
        flow=', "flow": "xtls-rprx-vision"'
    fi

    local config_path="/usr/local/etc/xray/config.json"
    local conf_dir="/usr/local/etc/xray"
    mkdir -p "$conf_dir"

    # Xray 二进制路径
    local xray_bin="/usr/local/bin/xray"
    if [ ! -f "$xray_bin" ]; then
        xray_bin=$(command -v xray)
    fi

    # 生成必要参数
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)

    local keys
    keys=$("$xray_bin" x25519 2>/dev/null)

    local priv_key
    priv_key=$(echo "$keys" | awk -F': ' '/Private/ {print $2}' | tr -d ' ')

    local pub_key
    pub_key=$(echo "$keys" | awk -F': ' '/Public/ {print $2}' | tr -d ' ')

    local short_id
    short_id=$(openssl rand -hex 8)

    local dest_server
    dest_server=$(get_random_dest || echo "www.microsoft.com")

    echo -e "${CYAN}本次 Reality 伪装站点：${GREEN}$dest_server${NC}"
    echo "$pub_key" > "${conf_dir}/pub.key" 2>/dev/null || true

    # ==================== 生成 Xray 配置 ====================
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

    # ==================== 后续统一处理 ====================
    check_json "$config_path"
    systemctl daemon-reload
    restart_service xray

    echo -e "${YELLOW}Reality 协议启动完成，跳过端口可达性检查${NC}"

    # 显示配置信息
    if [ "$mode" = "vision" ]; then
        show_protocol_info "REALITY-Vision" "$uuid" "$dest_server" "$pub_key" "$short_id"
    else
        show_protocol_info "REALITY-xHTTP" "$uuid" "$dest_server" "$pub_key" "$short_id" "$path"
    fi
}

# ==================== 【新】TLS 协议统一函数（用于 3~9）====================
########原旧函数#########
gen_vless_ws() {
    check_domain
    domain="$(cat /tmp/domain 2>/dev/null || echo "")"
    [[ -z "$domain" ]] && {
        echo "[ERROR] domain 为空"
        exit 1
    }
    install_caddy
    
    common_tls_setup
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local path
    path=$(openssl rand -hex 6)
    local port=10001
    check_port $port

    echo -e "${CYAN}正在配置 VLESS-WS-TLS (Caddy 反代)...${NC}"

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
    echo -e "${CYAN}请稍等，生成中...${NC}"
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
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local serviceName
    serviceName=$(openssl rand -hex 4)
    local port=10002
    check_port $port

    echo -e "${CYAN}正在配置 VLESS-gRPC-TLS...${NC}"

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
    echo -e "${CYAN}请稍等，生成中...${NC}"
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
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local path
    path=$(openssl rand -hex 6)
    local port=10003
    check_port $port

    echo -e "${CYAN}正在配置 VLESS-XHTTP-TLS...${NC}"

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
    echo -e "${CYAN}请稍等，生成中...${NC}"
    sleep 2
    check_service_alive $port "VLESS-XHTTP"
    check_external_tcp "$domain" 443        
    show_protocol_info "VLESS-XHTTP" "$uuid" "$domain" "$path"
}
# 协议 6 
gen_trojan_ws() {
    check_domain
    local domain
    domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${RED}[ERROR] domain 为空，请检查域名配置${NC}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    local pass
    pass=$(openssl rand -hex 8)
    
    local path
    path=$(openssl rand -hex 8)
    local port=10004

    echo -e "${CYAN}正在配置 Trojan-WS-TLS...${NC}"

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
    
    echo -e "${CYAN}请稍等，验证服务状态中...${NC}"
    sleep 3
    
    check_service_alive $port "Trojan-WS"
    check_external_tcp "$domain" 443
    
    # === 关键修复：必须严格使用 "Trojan-WS"（大写 WS）===
    show_protocol_info "Trojan-WS" "$pass" "$domain" "$path"
}

# 协议 7 安装 Trojan-gRPC-TLS
gen_trojan_grpc() {
    check_domain
    local domain
    domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${RED}[ERROR] domain 为空，请检查域名配置${NC}"
        exit 1
    }
    
    install_caddy 
    common_tls_setup
    
    # === 密码处理（统一变量名）===
    local uuid
    pass=$(openssl rand -hex 8)

    local serviceName
    serviceName=$(openssl rand -hex 8)
    local port=10005
    check_port $port

    echo -e "${CYAN}正在配置 Trojan-gRPC-TLS...${NC}"

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
    
    echo -e "${CYAN}请稍等，验证服务状态中...${NC}"
    sleep 3
    
    check_service_alive $port "Trojan-gRPC"
    check_external_tcp "$domain" 443
    
    # === 关键：必须用 "Trojan-gRPC"（和 show_protocol_info case 严格匹配）===
    show_protocol_info "Trojan-gRPC" "$uuid" "$domain" "$serviceName"
}


# 协议 8，安装 VMess-WS-TLS 【广泛兼容/传统方案】
gen_vmess_ws() {
    check_domain
    local domain
    domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${RED}[ERROR] domain 为空，请检查域名配置${NC}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    # === UUID 与路径 ===
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    
    local path
    path=$(openssl rand -hex 8)
    local port=10006

    echo -e "${CYAN}正在配置 VMess-WS-TLS...${NC}"

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
    
    echo -e "${CYAN}请稍等，验证服务状态中...${NC}"
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
    local domain
    domain=$(cat /tmp/domain 2>/dev/null || echo "")
    [[ -z "$domain" ]] && {
        echo -e "${RED}[ERROR] domain 为空，请检查域名配置${NC}"
        exit 1
    }
    
    install_caddy
    common_tls_setup
    
    # === UUID 与 ServiceName ===
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)   # 直接自动生成
    
    local serviceName
    serviceName=$(openssl rand -hex 8)
    local port=10007                           # 使用独立高位端口

    echo -e "${CYAN}正在配置 VMess-gRPC-TLS...${NC}"

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
    
    echo -e "${CYAN}请稍等，验证服务状态中...${NC}"
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
    local protocol_type=$1
    local uuid=$2
    local extra1=$3
    local extra2=$4
    local extra3=$5
    local extra4=$6

    local ip
    ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name
    ps_name="${protocol_type}_${extra1}_$(date +%Y%m%d)"
    local link=""

    echo -e "\n${GREEN}${protocol_type} 安装成功！${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"

    # ==================== 通用信息 ====================
    echo -e "${CYAN}地址 (Address)  : ${GREEN}$ip${NC}"
    echo -e "${CYAN}端口 (Port)     : ${GREEN}443${NC}"
    echo -e "${CYAN}UUID / 密码     : ${GREEN}$uuid${NC}"

    case "$protocol_type" in
        "REALITY-Vision")
            # 修正版：确保UUID正确插入
            link="vless://${uuid}@${ip}:443?security=reality&encryption=none&pbk=${extra2}&headerType=none&fp=chrome&flow=xtls-rprx-vision&sni=${extra1}&sid=${extra3}&type=tcp#${ps_name}"
            echo -e "${CYAN}流控 (Flow)     : ${GREEN}xtls-rprx-vision${NC}"
            echo -e "${CYAN}安全 (Security) : ${GREEN}reality${NC}"
            echo -e "${CYAN}SNI / 伪装域名  : ${GREEN}$extra1${NC}"
            echo -e "${CYAN}Public Key      : ${GREEN}$extra2${NC}"
            echo -e "${CYAN}Short ID        : ${GREEN}$extra3${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}tcp${NC}"
            ;;

        "REALITY-xHTTP")
            link="vless://${uuid}@${ip}:443?security=reality&encryption=none&pbk=${extra2}&headerType=none&fp=chrome&type=xhttp&path=%2F${extra4}&sni=${extra1}&sid=${extra3}#${ps_name}"
            echo -e "${CYAN}安全 (Security) : ${GREEN}reality${NC}"
            echo -e "${CYAN}SNI / 伪装域名  : ${GREEN}$extra1${NC}"
            echo -e "${CYAN}Public Key      : ${GREEN}$extra2${NC}"
            echo -e "${CYAN}Short ID        : ${GREEN}$extra3${NC}"
            echo -e "${CYAN}路径 (Path)     : ${GREEN}/$extra4${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}xhttp${NC}"
            ;;

        "VLESS-WS")
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=ws&host=$extra1&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=http/1.1#$ps_name"
            echo -e "${CYAN}安全 (Security) : ${GREEN}tls${NC}"
            echo -e "${CYAN}路径 (Path)     : ${GREEN}/$extra2${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}ws${NC}"
            ;;

        "VLESS-gRPC")
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=grpc&host=$extra1&serviceName=$extra2&sni=$extra1&fp=chrome&alpn=h2#$ps_name"
            echo -e "${CYAN}安全 (Security) : ${GREEN}tls${NC}"
            echo -e "${CYAN}ServiceName     : ${GREEN}$extra2${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}grpc${NC}"
            ;;

        "VLESS-XHTTP")
            link="vless://$uuid@$extra1:443?encryption=none&security=tls&type=xhttp&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=h2%2Chttp%2F1.1#$ps_name"
            echo -e "${CYAN}安全 (Security) : ${GREEN}tls${NC}"
            echo -e "${CYAN}路径 (Path)     : ${GREEN}/$extra2${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}xhttp${NC}"
            ;;

        "Trojan-WS")
            link="trojan://$uuid@$extra1:443?security=tls&type=ws&host=$extra1&path=%2F$extra2&sni=$extra1&fp=chrome&alpn=http/1.1#$ps_name"
            echo -e "${CYAN}安全 (Security) : ${GREEN}tls${NC}"
            echo -e "${CYAN}路径 (Path)     : ${GREEN}/$extra2${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}ws${NC}"
            ;;

        "Trojan-gRPC")
            link="trojan://$uuid@$extra1:443?security=tls&type=grpc&host=$extra1&serviceName=$extra2&sni=$extra1&fp=chrome&alpn=h2#$ps_name"
            echo -e "${CYAN}安全 (Security) : ${GREEN}tls${NC}"
            echo -e "${CYAN}ServiceName     : ${GREEN}$extra2${NC}"
            echo -e "${CYAN}传输类型        : ${GREEN}grpc${NC}"
            ;;

        "VMess-WS"|"VMess-gRPC")
            # VMess 使用专用函数显示
            if [[ "$protocol_type" == "VMess-WS" ]]; then
                export DOMAIN="$extra1"
                export UUID="$uuid"
                export WPATH="$extra2"
                show_vmess_ws_info
                return 0
            else
                export DOMAIN="$extra1"
                export UUID="$uuid"
                export WPATH="$extra2"
                show_vmess_grpc_info
                return 0
            fi
            ;;
    esac

    echo -e "${MAGENTA}-----------------------------------------------------------${NC}"
    echo -e "${RED}完整分享链接:${NC}"
    echo "$link"
    show_qr_code "$link"
    echo -e "${MAGENTA}===========================================================${NC}"
}

#合并所有show代码结束

show_qr_code() {
    local link=$1
    if command -v qrencode &> /dev/null; then
        echo -e "${CYAN}手机客户端扫描二维码:${NC}"
        echo "$link" | qrencode -t utf8
    else
        echo -e "${RED}提示: qrencode 未安装，无法生成二维码。${NC}"
    fi
}

# === 完完整整地补回被删除的 VMess 展现函数，保持你原本的风格定义变量和输出 ===
show_vmess_ws_info() {
    local ip
    ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name
    ps_name="VMess_WS_${DOMAIN}_$(date +%Y%m%d)"
    
    local vmess_json
    vmess_json=$(cat <<EOF
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
    local b64_link
    b64_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"

    echo -e "${GREEN}VMess-WS-TLS 安装成功！${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"
    echo -e "${CYAN}域名:${NC} $DOMAIN"
    echo -e "${CYAN}UUID:${NC} $UUID"
    echo -e "${CYAN}路径:${NC} /$WPATH"
    echo -e "${RED}分享链接:${NC}"
    echo "$b64_link"
    show_qr_code "$b64_link"
    echo -e "${MAGENTA}===========================================================${NC}"
}

show_vmess_grpc_info() {
    local ip
    ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的IP")
    local ps_name
    ps_name="VMess_gRPC_${DOMAIN}_$(date +%Y%m%d)"
    
    local vmess_json
    vmess_json=$(cat <<EOF
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
    local b64_link
    b64_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"

    echo -e "${GREEN}VMess-gRPC-TLS 安装成功！${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"
    echo -e "${CYAN}域名:${NC} $DOMAIN"
    echo -e "${CYAN}UUID:${NC} $UUID"
    echo -e "${CYAN}服务名:${NC} $WPATH"
    echo -e "${RED}分享链接:${NC}"
    echo "$b64_link"
    show_qr_code "$b64_link"
    echo -e "${MAGENTA}===========================================================${NC}"
}

show_usage() {
    echo -e "${MAGENTA}--- 流量统计看板 ---${NC}"
    if ! command -v vnstat &> /dev/null; then
        echo -e "${YELLOW}检测到 vnstat 未安装，正在尝试安装...${NC}"
        apt-get update && apt-get install -y vnstat
        systemctl enable vnstat --now
    fi
    if command -v vnstat &> /dev/null; then
        vnstat -d && vnstat -m
    else
        echo -e "${RED}错误: vnstat 不可用。${NC}"
    fi
    read -r -p "按回车键返回主菜单"
}

# ==================== 彻底卸载功能（已优化） ====================
uninstall_all() {
    echo -e "${RED}⚠️ 警告：此操作将彻底卸载 Xray + Caddy 并清理所有配置和日志！${NC}"
    read -r -p "确定要继续吗？(y/N): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消卸载。${NC}"
        read -r -p "按回车键返回主菜单" dummy
        return
    fi

    echo -e "${CYAN}>>> 开始执行彻底卸载...${NC}"

    # 停止服务
    echo -e "${YELLOW}[1/7] 停止 Xray 和 Caddy 服务...${NC}"
    systemctl stop xray caddy 2>/dev/null || true
    systemctl disable xray caddy 2>/dev/null || true
    echo -e "${GREEN}    ✓ 服务已停止并禁用${NC}"

    # 调用官方彻底卸载脚本
    echo -e "${YELLOW}[2/7] 调用 Xray 官方卸载脚本...${NC}"
    if ! command -v curl &>/dev/null; then
        echo -e "${RED}    ✗ curl 未安装，无法下载卸载脚本${NC}"
        return 1
    fi

    local script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
    local script_content
    script_content=$(curl -s --max-time 10 --retry 3 "$script_url") || {
        echo -e "${RED}    ✗ 下载 Xray 卸载脚本失败${NC}"
        return 1
    }

    # 简单的安全检查（确保不是HTML错误页）
    if echo "$script_content" | grep -q "<!DOCTYPE\|<html"; then
        echo -e "${RED}    ✗ 下载的文件似乎是HTML而非脚本${NC}"
        return 1
    fi

    bash <(echo "$script_content") remove --purge
    echo -e "${GREEN}    ✓ Xray 官方卸载完成${NC}"

    # 清理 Caddy
    echo -e "${YELLOW}[3/7] 清理 Caddy 程序和配置...${NC}"
    apt-get purge -y caddy 2>/dev/null || true
    echo -e "${GREEN}    ✓ Caddy 程序已卸载${NC}"

    echo -e "${YELLOW}[4/7] 清理 Caddy 配置文件和日志...${NC}"
    rm -rf /etc/caddy 2>/dev/null && echo -e "${GREEN}    ✓ /etc/caddy (Caddy配置目录)${NC}"
    rm -rf /var/log/caddy 2>/dev/null && echo -e "${GREEN}    ✓ /var/log/caddy (Caddy日志目录)${NC}"
    rm -rf /root/.config/caddy 2>/dev/null && echo -e "${GREEN}    ✓ /root/.config/caddy (Caddy用户配置)${NC}"
    rm -rf /usr/share/caddy 2>/dev/null && echo -e "${GREEN}    ✓ /usr/share/caddy (Caddy共享文件)${NC}"

    # 额外深度清理（防止残留）
    echo -e "${YELLOW}[5/7] 深度清理 Xray 残留文件...${NC}"
    rm -rf /usr/local/bin/xray 2>/dev/null && echo -e "${GREEN}    ✓ /usr/local/bin/xray (Xray二进制文件)${NC}"
    rm -rf /usr/local/etc/xray 2>/dev/null && echo -e "${GREEN}    ✓ /usr/local/etc/xray (Xray配置目录)${NC}"
    rm -rf /usr/local/share/xray 2>/dev/null && echo -e "${GREEN}    ✓ /usr/local/share/xray (Xray共享文件)${NC}"
    rm -rf /var/log/xray 2>/dev/null && echo -e "${GREEN}    ✓ /var/log/xray (Xray日志目录)${NC}"
    rm -rf /etc/systemd/system/xray.service 2>/dev/null && echo -e "${GREEN}    ✓ /etc/systemd/system/xray.service (Xray服务文件)${NC}"
    rm -rf /etc/systemd/system/xray@*.service 2>/dev/null && echo -e "${GREEN}    ✓ /etc/systemd/system/xray@*.service (Xray实例服务)${NC}"

    echo -e "${YELLOW}[6/7] 清理 Caddy APT 源和证书...${NC}"
    rm -rf /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null && echo -e "${GREEN}    ✓ /etc/apt/sources.list.d/caddy-stable.list (Caddy APT源)${NC}"
    rm -rf /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null && echo -e "${GREEN}    ✓ /usr/share/keyrings/caddy-stable-archive-keyring.gpg (Caddy GPG密钥)${NC}"
    rm -rf ~/.acme.sh 2>/dev/null && echo -e "${GREEN}    ✓ ~/.acme.sh (SSL证书工具)${NC}"

    # 删除 xray 用户（可选，谨慎）
    echo -e "${YELLOW}[7/7] 删除 xray 系统用户...${NC}"
    userdel -r xray 2>/dev/null && echo -e "${GREEN}    ✓ xray 用户已删除${NC}" || echo -e "${YELLOW}    ! xray 用户不存在或删除失败${NC}"

    systemctl daemon-reload
    echo -e "${GREEN}✅ 彻底卸载完成！系统已清理干净。${NC}"
    read -r -p "按回车键返回主菜单"
}

# ------------------------------------------------ 菜单部分代码 ------------------------------------------------
# 1. 显示系统状态
show_status() {
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${RED}====================== 脚本环境信息 =======================${NC}"
    echo -e "${RED}   作者：${NC}${BLUE}人生若只如初见，更新：2026/05/20   ${NC}"
    echo -e "${RED}   名称：${NC}${BLUE}xray 一键安装脚本    ${NC}"
    echo -e "${RED}   版本号：${NC}${BLUE}v1.0.05.20.00.42（Release）    ${NC}"
    echo -e "${RED}   适用环境：${NC}${BLUE}Debian12/13、Ubuntu25/26    ${NC}"
    echo -e "${RED}   当前系统：${NC}${GREEN}$OS_NAME    ${NC}"

    echo -e "${MAGENTA}---------------------- 系统状态检查 -----------------------${NC}"
    # 1、vnstat 流量统计状态
    if command -v vnstat &> /dev/null && systemctl is-active --quiet vnstat; then
        echo -e "   流量统计 : ${GREEN}监控中... ✅${NC}"
    elif command -v vnstat &> /dev/null; then
        echo -e "   流量统计 : ${YELLOW}已安装但未启动${NC}"
    else
        echo -e "   流量统计 : ${RED}未安装 ❌ ${NC}"
    fi
    
    # 2、BBR 状态
    local bbr_status
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        bbr_status="${GREEN}运行中... ✅${NC}"
    else
        bbr_status="${RED}未开启 ❌ ${NC}"
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
        echo -e "   Xray 服务: ${GREEN}运行中... ✅${NC}"
    elif [[ "$xray_installed" == true ]]; then
        echo -e "   Xray 服务: ${YELLOW}已安装但未运行${NC}"
    else
        echo -e "   Xray 服务: ${RED}未安装 ❌ ${NC}"
    fi 

    # 4、当前安装的协议及展示信息判定
    local current_proto="未配置 ❌"
    local show_domain="无"
    local is_reality=false
    local is_tls=false
    local current_port="未知"
    if [[ -f $config_path ]]; then
        current_proto="未知"
        if grep -q "realitySettings" $config_path; then
            current_port=443
            is_reality=true
            if grep -q '"network": "xhttp"' $config_path; then current_proto="VLESS-REALITY-xhttp"
            elif grep -q "xtls-rprx-vision" $config_path; then current_proto="VLESS-REALITY-Vision"
            else current_proto="VLESS-REALITY"; fi
            show_domain=$(grep -m1 '"dest":' $config_path | grep -oP '(?<="dest": ")[^"]+' | cut -d':' -f1 || echo "未知")
        else
            current_port=443
            is_tls=true
            if grep -q '"protocol": "trojan"' $config_path; then
                if grep -q '"network": "ws"' $config_path; then current_proto="Trojan-WS-TLS"
                elif grep -q '"network": "grpc"' $config_path; then current_proto="Trojan-gRPC-TLS"; fi
            elif grep -q '"protocol": "vmess"' $config_path; then
                if grep -q '"network": "ws"' $config_path; then current_proto="VMess-WS-TLS"
                elif grep -q '"network": "grpc"' $config_path; then current_proto="VMess-gRPC-TLS"; fi
            elif grep -q '"protocol": "vless"' $config_path; then
                local net=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+' || echo "")
                case "${net,,}" in
                    ws)    current_proto="VLESS-WS-TLS" ;;
                    grpc)  current_proto="VLESS-gRPC-TLS" ;;
                    xhttp) current_proto="VLESS-XHTTP-TLS" ;;
                    *)     current_proto="VLESS-${net^^}" ;;
                esac
            fi
        fi
        [[ -z "$show_domain" ]] && show_domain=$(grep -oP '(?<="serverNames": \[")[^"]+' $config_path | head -n1 || echo "未知")
    fi
    if [[ "$is_tls" == true ]]; then
        [[ -f "/etc/caddy/Caddyfile" ]] && show_domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
        if command -v caddy &>/dev/null && systemctl is-active --quiet caddy; then echo -e "   Caddy服务: ${GREEN}运行中... ✅${NC}"
        elif command -v caddy &>/dev/null; then echo -e "   Caddy服务: ${YELLOW}已安装但未运行 ⚠️${NC}"
        else echo -e "   Caddy服务: ${RED}未安装 ❌${NC}"; fi
    fi
    echo -e "   当前协议 : ${GREEN}${current_proto}${NC}"
    [[ "$is_reality" == true ]] && echo -e "   伪装域名 : ${GREEN}${show_domain}${NC}"
    [[ "$is_tls" == true ]] && echo -e "   当前域名 : ${GREEN}${show_domain}${NC}"
    echo -e "   本机 IP  : ${GREEN}$(get_local_ip)${NC}"
    echo -e "   服务端口 : ${GREEN}${current_port}${NC}" 
}

# 2. 显示菜单选项
show_menu() {
    echo -e "-----------------------------------------------------------"
    echo -e "${BLUE}  【1】 . 安装 VLESS-REALITY-Vision${NC}   ${RED}【推荐，最强隐蔽/不依赖域名】${NC}"
    echo -e "${BLUE}  【2】 . 安装 VLESS-REALITY-xhttp${NC}    ${CYAN}【最新黑科技/综合最强】${NC}"   
    echo -e "${BLUE}  【3】 . 安装 VLESS-WS-TLS${NC}           ${CYAN}【CDN兼容/标准WebSocket】${NC}"
    echo -e "${BLUE}  【4】 . 安装 VLESS-gRPC-TLS${NC}         ${CYAN}【低延迟/多路复用】${NC}"
    echo -e "${BLUE}  【5】 . 安装 VLESS-XHTTP-TLS${NC}        ${CYAN}【流式传输/防指纹】${NC}"
    echo -e "${BLUE}  【6】 . 安装 Trojan-WS-TLS${NC}          ${CYAN}【仿HTTPS/老牌稳定】${NC}"
    echo -e "${BLUE}  【7】 . 安装 Trojan-gRPC-TLS${NC}        ${CYAN}【高效转发/适合游戏】${NC}"
    echo -e "${BLUE}  【8】 . 安装 VMess-WS-TLS${NC}           ${YELLOW}【广泛兼容/传统方案】${NC}"
    echo -e "${BLUE}  【9】 . 安装 VMess-gRPC-TLS${NC}         ${YELLOW}【兼容gRPC新特性】${NC}"
    echo -e "-----------------------------------------------------------"
    echo -e "${MAGENTA}  【c】 . 查看当前协议信息与链接${NC}" 
    echo -e "${MAGENTA}  【v】 . 查看流量统计 (vnstat)${NC}"
    echo -e "${MAGENTA}  【b】 . 管理网络加速 (BBR)${NC}"
    echo -e "${GREEN}  【d】 . 卸载与清理${NC}"
    echo -e "${YELLOW}  【q】 . 退出脚本${NC}" 
    echo -e "-----------------------------------------------------------"
}

# 3. 处理用户选择
handle_menu() {
    read -r -p "请选择: " num
    if [[ -z "$num" ]]; then
        echo -e "${RED}输入不能为空，请重新输入！${NC}"
        return
    fi
    
    if [[ -n "${PROTOCOL_CONFIG[$num]}" ]]; then
        # 【修改核心】：确保只提取最后一个字段作为命令执行
        # 你的定义中第 7 个字段是真正的命令，前面的 1-6 都是配置属性
        local IFS='|'
        # 使用 read 读取数组，通过 _ 忽略前 6 个字段，将最后一个存入 cmd
        read -r _ _ _ _ _ _ cmd <<< "${PROTOCOL_CONFIG[$num]}"
        
        # 调试：如果不确定，取消下面这行的注释看看输出是什么
        # echo "DEBUG: 执行命令 -> $cmd"
        
        [[ "$num" =~ ^[1-9]$ ]] && preparation_stack
        
        # 直接执行解析出来的命令
        $cmd
        
        echo -e "${GREEN}安装完成，请按回车键返回主菜单...${NC}"
    fi
}

# 主菜单入口
main_menu() {
    clear
    show_status
    show_menu
    handle_menu
}
# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    main_menu
fi