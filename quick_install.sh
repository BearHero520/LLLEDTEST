#!/bin/bash

# UGREEN LED 控制器 - 一键安装脚本
# 版本: 4.0.0
# 简化重构版

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLEDTEST"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"
LOG_DIR="/var/log/llled"
CONFIG_DIR="$INSTALL_DIR/config"

# ============================================
# 版本号定义（单一来源）
# ============================================
VERSION="4.0.1"
LLLED_VERSION="$VERSION"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}UGREEN LED 控制器安装工具 v${VERSION}${NC}"
echo -e "${CYAN}================================${NC}"
echo

# 日志函数
log_install() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INSTALL] $1" | tee -a "$LOG_DIR/install.log"
}

# 清理旧版本
cleanup_old_version() {
    log_install "清理旧版本..."
    systemctl stop ugreen-led-monitor.service 2>/dev/null || true
    systemctl disable ugreen-led-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/ugreen-led-monitor.service 2>/dev/null || true
    rm -f /usr/local/bin/LLLED 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    if [[ -d "$INSTALL_DIR" ]]; then
        backup_dir="/tmp/llled-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        if [[ -d "$INSTALL_DIR/config" ]]; then
            cp -r "$INSTALL_DIR/config" "$backup_dir/" 2>/dev/null || true
            echo "配置已备份到: $backup_dir"
        fi
        rm -rf "$INSTALL_DIR"
    fi
}

# 安装依赖
install_dependencies() {
    log_install "安装必要依赖..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y wget curl i2c-tools smartmontools util-linux hdparm -qq
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl i2c-tools smartmontools util-linux hdparm -q
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y wget curl i2c-tools smartmontools util-linux hdparm -q
    else
        echo -e "${YELLOW}警告: 未检测到包管理器，请手动安装依赖${NC}"
    fi
    
    modprobe i2c-dev 2>/dev/null
}

# 下载文件
download_files() {
    log_install "下载必要文件..."
    mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
    mkdir -p "$LOG_DIR"
    cd "$INSTALL_DIR"
    
    files=(
        "ugreen_led_controller.sh"
        "ugreen_leds_cli"
        "scripts/led_daemon.sh"
        "config/led_config.conf"
        "config/global_config.conf"
        "config/disk_mapping.conf"
        "systemd/ugreen-led-monitor.service"
    )
    
    for file in "${files[@]}"; do
        echo -n "下载: $file ... "
        if wget -q "${GITHUB_RAW_URL}/${file}" -O "$file" 2>/dev/null || \
           curl -fsSL "${GITHUB_RAW_URL}/${file}" -o "$file" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            log_install "警告: 无法下载 $file"
        fi
    done
    
    chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null
    
    # 更新 global_config.conf 中的版本号（确保版本号统一）
    if [[ -f "$INSTALL_DIR/config/global_config.conf" ]]; then
        sed -i "s/^LLLED_VERSION=.*/LLLED_VERSION=\"$VERSION\"/" "$INSTALL_DIR/config/global_config.conf" 2>/dev/null || \
        sed -i "s/^LLLED_VERSION=.*/LLLED_VERSION=\"$VERSION\"/" "$INSTALL_DIR/config/global_config.conf" 2>/dev/null || true
        sed -i "s/^VERSION=.*/VERSION=\"\$LLLED_VERSION\"/" "$INSTALL_DIR/config/global_config.conf" 2>/dev/null || true
        log_install "已更新 global_config.conf 中的版本号为: $VERSION"
    fi
}

# 检测LED并生成映射配置
detect_and_configure() {
    log_install "检测LED并生成映射配置..."
    
    local UGREEN_CLI="$INSTALL_DIR/ugreen_leds_cli"
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_install "错误: LED控制程序不可用"
        return 1
    fi
    
    # 检测可用LED - 使用 all -status 获取实际存在的LED
    local detected_disk_leds=()
    local all_status
    all_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    
    if [[ -n "$all_status" ]]; then
        # 从 all -status 输出中解析硬盘LED
        while IFS= read -r line; do
            # 匹配格式: disk1: status = off, ...
            if [[ "$line" =~ ^disk([0-9]+): ]]; then
                local disk_num="${BASH_REMATCH[1]}"
                detected_disk_leds+=("disk$disk_num")
            fi
        done <<< "$all_status"
    else
        # 备用方法：逐个检测，但遇到连续失败就停止
        log_install "无法获取all状态，使用逐个检测方法..."
        local fail_count=0
        for i in {1..8}; do
            local status_output
            status_output=$("$UGREEN_CLI" "disk$i" -status 2>&1)
            local exit_code=$?
            
            # 检查是否真的存在（不是错误信息）
            if [[ $exit_code -eq 0 ]] && [[ -n "$status_output" ]] && \
               ! echo "$status_output" | grep -qi "error\|not found\|invalid"; then
                detected_disk_leds+=("disk$i")
                fail_count=0  # 重置失败计数
            else
                ((fail_count++))
                # 连续3个失败就停止检测
                if [[ $fail_count -ge 3 ]]; then
                    log_install "连续检测失败，停止LED检测（已检测到 ${#detected_disk_leds[@]} 个）"
                    break
                fi
            fi
        done
    fi
    
    # 生成LED映射配置
    cat > "$INSTALL_DIR/config/led_config.conf" << EOF
# UGREEN LED 控制器配置文件
# 版本: ${VERSION}
# 生成时间: $(date)

# I2C 设备配置
I2C_BUS=1
I2C_DEVICE_ADDR=0x3a

# 系统LED映射
POWER_LED=0
NETDEV_LED=1

# 硬盘LED映射
EOF
    
    local led_id=2
    for led_name in "${detected_disk_leds[@]}"; do
        local disk_num=${led_name#disk}
        echo "DISK${disk_num}_LED=$led_id" >> "$INSTALL_DIR/config/led_config.conf"
        echo "${led_name}=$led_id" >> "$INSTALL_DIR/config/led_config.conf"
        ((led_id++))
    done
    
    cat >> "$INSTALL_DIR/config/led_config.conf" << 'EOF'

# 颜色配置 (RGB值 0-255)
POWER_COLOR="128 128 128"
NETWORK_COLOR_DISCONNECTED="255 0 0"
NETWORK_COLOR_CONNECTED="0 255 0"
NETWORK_COLOR_INTERNET="0 0 255"
DISK_COLOR_HEALTHY="255 255 255"
DISK_COLOR_STANDBY="200 200 200"
DISK_COLOR_UNHEALTHY="255 0 0"
DISK_COLOR_NO_DISK="0 0 0"

# 亮度配置
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=32
HIGH_BRIGHTNESS=128

# 检测间隔
DISK_CHECK_INTERVAL=30
NETWORK_CHECK_INTERVAL=60
SYSTEM_LED_UPDATE_INTERVAL=60
EOF
    
    # 验证检测结果：LED数量应该与实际硬盘数量匹配
    # 先检测实际硬盘数量
    local actual_disk_count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([a-z]+)[[:space:]]+([0-9]+:[0-9]+:[0-9]+:[0-9]+) ]]; then
            local disk_name="${BASH_REMATCH[1]}"
            local disk_device="/dev/$disk_name"
            local transport=$(lsblk -d -n -o TRAN "$disk_device" 2>/dev/null || echo "")
            if [[ "$transport" == "sata" ]]; then
                ((actual_disk_count++))
            fi
        fi
    done < <(lsblk -S -x hctl -o name,hctl 2>/dev/null)
    
    # 如果检测到的LED数量明显多于实际硬盘数量，进行修正
    if [[ ${#detected_disk_leds[@]} -gt $actual_disk_count ]] && [[ $actual_disk_count -gt 0 ]]; then
        log_install "警告: 检测到 ${#detected_disk_leds[@]} 个LED，但只有 $actual_disk_count 个SATA硬盘"
        log_install "修正LED数量以匹配实际硬盘数量"
        # 只保留前 N 个LED（N = 实际硬盘数量）
        detected_disk_leds=("${detected_disk_leds[@]:0:$actual_disk_count}")
    fi
    
    log_install "检测到 ${#detected_disk_leds[@]} 个硬盘LED: ${detected_disk_leds[*]}"
    if [[ $actual_disk_count -gt 0 ]]; then
        log_install "实际SATA硬盘数量: $actual_disk_count"
    fi
    
    # 生成硬盘映射
    generate_disk_mapping "${detected_disk_leds[@]}"
}

# 生成硬盘映射
generate_disk_mapping() {
    local disk_leds=("$@")
    log_install "生成硬盘映射配置..."
    
    cat > "$INSTALL_DIR/config/disk_mapping.conf" << EOF
# 硬盘映射配置文件
# 版本: ${VERSION}
# 生成时间: $(date)

EOF
    
    local disk_index=0
    while IFS= read -r line; do
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^([a-z]+)[[:space:]]+([0-9]+:[0-9]+:[0-9]+:[0-9]+)[[:space:]]*(.*)$ ]]; then
            local disk_name="${BASH_REMATCH[1]}"
            local hctl="${BASH_REMATCH[2]}"
            local serial="${BASH_REMATCH[3]:-unknown}"
            local disk_device="/dev/$disk_name"
            
            # 检查是否为SATA设备
            local transport=$(lsblk -d -n -o TRAN "$disk_device" 2>/dev/null || echo "")
            if [[ "$transport" == "sata" && $disk_index -lt ${#disk_leds[@]} ]]; then
                local led_name="${disk_leds[$disk_index]}"
                local model=$(lsblk -dno model "$disk_device" 2>/dev/null || echo "Unknown")
                local size=$(lsblk -dno size "$disk_device" 2>/dev/null || echo "Unknown")
                
                echo "HCTL_MAPPING[$disk_device]=\"$hctl|$led_name|$serial|$model|$size\"" >> "$INSTALL_DIR/config/disk_mapping.conf"
                log_install "映射: $disk_device -> $led_name (HCTL: $hctl)"
                ((disk_index++))
            fi
        fi
    done < <(lsblk -S -x hctl -o name,hctl,serial 2>/dev/null)
    
    log_install "硬盘映射生成完成，映射了 $disk_index 个硬盘"
}

# 安装systemd服务
install_service() {
    log_install "安装systemd服务..."
    
    if [[ -f "$INSTALL_DIR/systemd/ugreen-led-monitor.service" ]]; then
        cp "$INSTALL_DIR/systemd/ugreen-led-monitor.service" /etc/systemd/system/
    else
        cat > /etc/systemd/system/ugreen-led-monitor.service << EOF
[Unit]
Description=UGREEN LED Monitor Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/scripts/led_daemon.sh _daemon_process
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    systemctl daemon-reload
    systemctl enable ugreen-led-monitor.service
    log_install "Systemd服务已安装并启用"
}

# 创建命令链接
create_command_link() {
    log_install "创建命令链接..."
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    chmod +x "$INSTALL_DIR/ugreen_led_controller.sh"
}

# 启动服务
start_service() {
    log_install "启动后台服务..."
    systemctl start ugreen-led-monitor.service
    sleep 2
    
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        echo -e "${GREEN}✓ 服务启动成功${NC}"
        log_install "服务启动成功"
    else
        echo -e "${YELLOW}⚠ 服务启动可能失败，请检查日志${NC}"
        log_install "警告: 服务启动可能失败"
    fi
}

# 主安装流程
main() {
    cleanup_old_version
    install_dependencies
    download_files
    
    if ! detect_and_configure; then
        echo -e "${RED}LED检测失败，但将继续安装${NC}"
    fi
    
    install_service
    create_command_link
    start_service
    
    echo
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🎉 安装完成！                        ║${NC}"
    echo -e "${CYAN}║                                        ║${NC}"
    echo -e "${CYAN}║  使用命令: sudo LLLED                  ║${NC}"
    echo -e "${CYAN}║  服务状态: systemctl status ugreen-led-monitor.service${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo
}

main "$@"
