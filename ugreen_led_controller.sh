#!/bin/bash

# 绿联LED控制工具 - 智能硬盘映射版 v3.0.0
# LLLED智能LED控制系统主控制器
# 项目地址: https://github.com/BearHero520/LLLEDTEST
# 版本: 3.0.0 (全功能集成版)

# 全局版本信息
VERSION="3.0.0"
PROJECT_NAME="LLLED智能LED控制系统"
LAST_UPDATE="2025-09-06"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 系统路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
LOG_DIR="/var/log/llled"

# 配置文件
GLOBAL_CONFIG="$CONFIG_DIR/global_config.conf"
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
DISK_CONFIG="$CONFIG_DIR/disk_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"

# 核心程序
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"
LED_DAEMON="$SCRIPTS_DIR/led_daemon.sh"
HCTL_SCRIPT="$SCRIPTS_DIR/smart_disk_activity_hctl.sh"

# 加载全局配置
[[ -f "$GLOBAL_CONFIG" ]] && source "$GLOBAL_CONFIG"

# 检查安装
check_installation() {
    local missing_files=()
    
    # 检查必要文件
    for file in "$UGREEN_CLI" "$LED_CONFIG" "$LED_DAEMON" "$HCTL_SCRIPT"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${RED}系统未正确安装，缺少文件:${NC}"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        echo
        echo -e "${YELLOW}请运行安装脚本: quick_install.sh${NC}"
        exit 1
    fi
    
    # 检查LED控制程序权限
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}LED控制程序无执行权限: $UGREEN_CLI${NC}"
        echo "尝试修复权限..."
        chmod +x "$UGREEN_CLI" 2>/dev/null || {
            echo -e "${RED}权限修复失败${NC}"
            exit 1
        }
    fi
    
    # 加载i2c模块
    ! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null
}

# 显示系统信息
show_system_info() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$PROJECT_NAME v$VERSION${NC}"
    echo -e "${CYAN}================================${NC}"
    echo -e "更新时间: $LAST_UPDATE"
    echo -e "安装目录: $SCRIPT_DIR"
    echo -e "配置目录: $CONFIG_DIR"
    echo -e "日志目录: $LOG_DIR"
    echo
    
    # 显示LED状态
    if [[ -x "$UGREEN_CLI" ]]; then
        local led_status
        led_status=$("$UGREEN_CLI" all -status 2>/dev/null)
        if [[ -n "$led_status" ]]; then
            echo -e "${BLUE}当前LED状态:${NC}"
            echo "$led_status"
        else
            echo -e "${YELLOW}无法获取LED状态${NC}"
        fi
    fi
    echo
}

# 获取可用LED列表
get_available_leds() {
    local all_status=$($UGREEN_CLI all -status 2>/dev/null)
    local available_leds=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
            available_leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$all_status"
    
    echo "${available_leds[@]}"
}

# 设置所有LED颜色和亮度
set_all_leds() {
    local color="$1"
    local brightness="$2"
    local mode="$3"  # -on, -off, 或留空
    
    local available_leds=($(get_available_leds))
    
    if [[ ${#available_leds[@]} -eq 0 ]]; then
        echo -e "${YELLOW}无法检测LED，使用备用方法${NC}"
        # 备用方法：尝试常见LED
        for led in power netdev disk1 disk2 disk3 disk4 disk5 disk6 disk7 disk8; do
            if [[ -n "$mode" ]]; then
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness $mode 2>/dev/null
            else
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness 2>/dev/null
            fi
        done
    else
        echo -e "${GREEN}控制 ${#available_leds[@]} 个LED: ${available_leds[*]}${NC}"
        for led in "${available_leds[@]}"; do
            if [[ -n "$mode" ]]; then
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness $mode 2>/dev/null
            else
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness 2>/dev/null
            fi
        done
    fi
}
manage_lights() {
    echo -e "${CYAN}LED灯光设置${NC}"
    echo
    echo "1. 关闭所有LED"
    echo "2. 打开所有LED" 
    echo "3. 节能模式"
    echo "4. 夜间模式"
    echo "5. 彩虹效果"
    echo "6. 自定义颜色设置"
    echo "7. 返回主菜单"
    echo
    read -p "请选择操作 (1-7): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}关闭所有LED...${NC}"
            "$SCRIPTS_DIR/turn_off_all_leds.sh"
            ;;
        2)
            echo -e "${CYAN}打开所有LED...${NC}"
            if [[ -f "$SCRIPTS_DIR/led_test.sh" ]]; then
                "$SCRIPTS_DIR/led_test.sh" --all-on
            else
                # 简单的打开所有LED
                for led in power netdev disk1 disk2 disk3 disk4; do
                    "$UGREEN_CLI" "$led" -color "255 255 255" -brightness 64 2>/dev/null
                done
            fi
            ;;
        3)
            echo -e "${CYAN}启用节能模式...${NC}"
            # 低亮度白光
            set_all_leds "255 255 255" "16" "-on"
            echo -e "${GREEN}✓ 节能模式已启用 (低亮度白光)${NC}"
            ;;
        4)
            echo -e "${CYAN}启用夜间模式...${NC}"
            # 暗红光
            set_all_leds "64 0 0" "8" "-on"
            echo -e "${GREEN}✓ 夜间模式已启用 (暗红光)${NC}"
            ;;
        5)
            echo -e "${CYAN}启动彩虹效果...${NC}"
            if [[ -x "$SCRIPTS_DIR/rainbow_effect.sh" ]]; then
                "$SCRIPTS_DIR/rainbow_effect.sh"
            else
                echo -e "${YELLOW}彩虹效果脚本不存在${NC}"
            fi
            ;;
        6)
            custom_color_setting
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 自定义颜色设置
custom_color_setting() {
    echo -e "${CYAN}自定义颜色设置${NC}"
    echo
    echo "预设颜色:"
    echo "1. 红色 (255 0 0)"
    echo "2. 绿色 (0 255 0)"
    echo "3. 蓝色 (0 0 255)"
    echo "4. 白色 (255 255 255)"
    echo "5. 黄色 (255 255 0)"
    echo "6. 紫色 (255 0 255)"
    echo "7. 青色 (0 255 255)"
    echo "8. 自定义RGB"
    echo
    read -p "请选择颜色 (1-8): " color_choice
    
    local color=""
    case $color_choice in
        1) color="255 0 0" ;;
        2) color="0 255 0" ;;
        3) color="0 0 255" ;;
        4) color="255 255 255" ;;
        5) color="255 255 0" ;;
        6) color="255 0 255" ;;
        7) color="0 255 255" ;;
        8)
            read -p "请输入RGB值 (格式: R G B, 0-255): " color
            # 验证RGB格式
            if ! [[ "$color" =~ ^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]]; then
                echo -e "${RED}RGB格式错误${NC}"
                return
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return
            ;;
    esac
    
    read -p "请输入亮度 (0-255): " brightness
    if ! [[ "$brightness" =~ ^[0-9]+$ ]] || [[ $brightness -gt 255 ]]; then
        echo -e "${RED}亮度值无效${NC}"
        return
    fi
    
    echo -e "${CYAN}设置所有LED为: $color (亮度: $brightness)${NC}"
    for led in power netdev disk1 disk2 disk3 disk4; do
        "$UGREEN_CLI" "$led" -color "$color" -brightness "$brightness" 2>/dev/null
    done
}

# 硬盘设置功能
manage_disks() {
    echo -e "${CYAN}硬盘设置${NC}"
    echo
    echo "1. 智能硬盘状态显示"
    echo "2. 实时硬盘活动监控"
    echo "3. 获取HCTL硬盘映射"
    echo "4. 显示硬盘映射"
    echo "5. 配置硬盘映射"
    echo "6. 更新HCTL映射配置"
    echo "7. 返回主菜单"
    echo
    read -p "请选择操作 (1-7): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}启动智能硬盘状态显示...${NC}"
            echo -e "${BLUE}智能硬盘活动状态监控 (HCTL版)${NC}"
            echo -e "${CYAN}正在使用HCTL智能检测硬盘...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT"
            else
                echo -e "${YELLOW}HCTL智能硬盘状态脚本不存在${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}启动实时硬盘活动监控...${NC}"
            echo "按 Ctrl+C 停止监控"
            if [[ -x "$SCRIPTS_DIR/disk_status_leds.sh" ]]; then
                "$SCRIPTS_DIR/disk_status_leds.sh"
            else
                echo -e "${YELLOW}硬盘活动监控脚本不存在${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}获取HCTL硬盘映射...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT" --update-mapping
            else
                echo -e "${YELLOW}HCTL脚本不存在${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}显示当前硬盘映射...${NC}"
            show_disk_mapping
            ;;
        5)
            echo -e "${CYAN}配置硬盘映射...${NC}"
            if [[ -x "$SCRIPTS_DIR/configure_mapping.sh" ]]; then
                "$SCRIPTS_DIR/configure_mapping.sh"
            else
                configure_disk_mapping_manual
            fi
            ;;
        6)
            echo -e "${CYAN}更新HCTL映射配置...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT" --update-mapping --save-config
                echo -e "${GREEN}✓ HCTL映射配置已更新${NC}"
            else
                echo -e "${YELLOW}HCTL脚本不存在${NC}"
            fi
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 显示硬盘映射
show_disk_mapping() {
    echo -e "${YELLOW}当前硬盘映射配置:${NC}"
    echo
    
    # 显示传统映射
    if [[ -f "$DISK_CONFIG" ]]; then
        echo -e "${BLUE}传统映射 ($DISK_CONFIG):${NC}"
        grep -E "^/dev/" "$DISK_CONFIG" 2>/dev/null || echo "  (无配置)"
        echo
    fi
    
    # 显示HCTL映射
    if [[ -f "$HCTL_CONFIG" ]]; then
        echo -e "${BLUE}HCTL映射 ($HCTL_CONFIG):${NC}"
        grep -E "^HCTL_MAPPING" "$HCTL_CONFIG" 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"?([^\"]+)\"?$ ]]; then
                local device="${BASH_REMATCH[1]}"
                local mapping="${BASH_REMATCH[2]}"
                IFS='|' read -r hctl led serial model size <<< "$mapping"
                echo "  $device -> $led (HCTL: $hctl)"
                echo "    型号: ${model:-Unknown} | 序列号: ${serial:-N/A} | 大小: ${size:-N/A}"
            fi
        done
        
        if ! grep -q "^HCTL_MAPPING" "$HCTL_CONFIG" 2>/dev/null; then
            echo "  (无HCTL映射配置)"
        fi
    else
        echo -e "${BLUE}HCTL映射: (配置文件不存在)${NC}"
    fi
}

# 手动配置硬盘映射
configure_disk_mapping_manual() {
    echo -e "${CYAN}手动配置硬盘映射${NC}"
    echo
    
    # 检测可用硬盘
    local available_disks=()
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            available_disks+=("$disk")
        fi
    done
    
    if [[ ${#available_disks[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘${NC}"
        return
    fi
    
    echo -e "${YELLOW}检测到的硬盘:${NC}"
    for i in "${!available_disks[@]}"; do
        echo "$((i+1)). ${available_disks[i]}"
    done
    echo
    
    # 可用LED
    local available_leds=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
    echo -e "${YELLOW}可用LED位置:${NC}"
    for i in "${!available_leds[@]}"; do
        echo "$((i+1)). ${available_leds[i]}"
    done
    echo
    
    # 交互式配置
    declare -A new_mapping
    for disk in "${available_disks[@]}"; do
        echo -e "${CYAN}配置硬盘: $disk${NC}"
        echo "可选LED: ${available_leds[*]}"
        read -p "请输入LED位置 (或输入 'skip' 跳过): " led_choice
        
        if [[ "$led_choice" != "skip" && " ${available_leds[*]} " =~ " $led_choice " ]]; then
            new_mapping["$disk"]="$led_choice"
            echo -e "${GREEN}✓ $disk -> $led_choice${NC}"
        else
            echo -e "${YELLOW}跳过 $disk${NC}"
        fi
        echo
    done
    
    # 保存配置
    if [[ ${#new_mapping[@]} -gt 0 ]]; then
        echo -e "${CYAN}保存新的硬盘映射配置...${NC}"
        
        # 备份原配置
        [[ -f "$DISK_CONFIG" ]] && cp "$DISK_CONFIG" "${DISK_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 写入新配置
        cat > "$DISK_CONFIG" << EOF
# 绿联LED硬盘映射配置文件
# 版本: $VERSION
# 格式: 硬盘设备=LED名称

EOF
        
        for disk in "${!new_mapping[@]}"; do
            echo "$disk=${new_mapping[$disk]}" >> "$DISK_CONFIG"
        done
        
        echo -e "${GREEN}✓ 配置已保存: $DISK_CONFIG${NC}"
    else
        echo -e "${YELLOW}未配置任何映射${NC}"
    fi
}

# 后台服务管理
manage_service() {
    echo -e "${CYAN}后台服务管理${NC}"
    echo
    echo "1. 启动后台服务"
    echo "2. 停止后台服务"
    echo "3. 重启后台服务"
    echo "4. 查看服务状态"
    echo "5. 开机自启设置"
    echo "6. 安装后台守护服务"
    echo "7. 查看服务日志"
    echo "8. 实时查看日志"
    echo "9. 返回主菜单"
    echo
    read -p "请选择操作 (1-9): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}启动后台服务...${NC}"
            if [[ -x "$LED_DAEMON" ]]; then
                "$LED_DAEMON" start
            else
                echo -e "${RED}后台服务脚本不存在${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}停止后台服务...${NC}"
            if [[ -x "$LED_DAEMON" ]]; then
                "$LED_DAEMON" stop
            else
                systemctl stop ugreen-led-monitor 2>/dev/null || echo -e "${YELLOW}服务未运行${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}重启后台服务...${NC}"
            if [[ -x "$LED_DAEMON" ]]; then
                "$LED_DAEMON" restart
            else
                systemctl restart ugreen-led-monitor 2>/dev/null || echo -e "${YELLOW}服务重启失败${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}查看服务状态...${NC}"
            if [[ -x "$LED_DAEMON" ]]; then
                "$LED_DAEMON" status
            fi
            echo
            echo -e "${BLUE}Systemd服务状态:${NC}"
            systemctl status ugreen-led-monitor 2>/dev/null || echo "Systemd服务未安装"
            ;;
        5)
            manage_autostart
            ;;
        6)
            install_systemd_service
            ;;
        7)
            echo -e "${CYAN}查看服务日志...${NC}"
            if [[ -f "$LOG_DIR/ugreen-led-monitor.log" ]]; then
                tail -50 "$LOG_DIR/ugreen-led-monitor.log"
            else
                echo -e "${YELLOW}日志文件不存在${NC}"
            fi
            ;;
        8)
            echo -e "${CYAN}实时查看日志 (按Ctrl+C退出)...${NC}"
            if [[ -f "$LOG_DIR/ugreen-led-monitor.log" ]]; then
                tail -f "$LOG_DIR/ugreen-led-monitor.log"
            else
                echo -e "${YELLOW}日志文件不存在${NC}"
            fi
            ;;
        9)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 开机自启管理
manage_autostart() {
    echo -e "${CYAN}开机自启设置${NC}"
    echo
    echo "1. 启用开机自启"
    echo "2. 禁用开机自启"
    echo "3. 查看自启状态"
    echo "4. 返回"
    echo
    read -p "请选择操作 (1-4): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}启用开机自启...${NC}"
            if systemctl enable ugreen-led-monitor 2>/dev/null; then
                echo -e "${GREEN}✓ 开机自启已启用${NC}"
            else
                echo -e "${RED}启用失败，请先安装守护服务${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}禁用开机自启...${NC}"
            if systemctl disable ugreen-led-monitor 2>/dev/null; then
                echo -e "${GREEN}✓ 开机自启已禁用${NC}"
            else
                echo -e "${YELLOW}禁用失败或服务未安装${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}自启状态:${NC}"
            if systemctl is-enabled ugreen-led-monitor 2>/dev/null; then
                echo -e "${GREEN}✓ 已启用开机自启${NC}"
            else
                echo -e "${YELLOW}未启用开机自启${NC}"
            fi
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 安装systemd服务
install_systemd_service() {
    echo -e "${CYAN}安装后台守护服务...${NC}"
    
    local service_file="/etc/systemd/system/ugreen-led-monitor.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=LLLED智能LED监控服务
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=$LED_DAEMON start
ExecStop=$LED_DAEMON stop
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Systemd服务已安装${NC}"
    echo -e "${BLUE}服务文件: $service_file${NC}"
    echo
    echo "现在可以使用以下命令管理服务:"
    echo "  systemctl start ugreen-led-monitor    # 启动服务"
    echo "  systemctl stop ugreen-led-monitor     # 停止服务"
    echo "  systemctl enable ugreen-led-monitor   # 开机自启"
    echo "  systemctl status ugreen-led-monitor   # 查看状态"
}

# 恢复系统LED
restore_system_leds() {
    echo -e "${CYAN}恢复系统LED (电源+网络)${NC}"
    echo
    echo "1. 恢复电源LED (白色常亮)"
    echo "2. 恢复网络LED (蓝色常亮)"
    echo "3. 恢复所有系统LED"
    echo "4. 返回主菜单"
    echo
    read -p "请选择操作 (1-4): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}恢复电源LED...${NC}"
            "$UGREEN_CLI" power -color "128 128 128" -brightness 64 2>/dev/null
            echo -e "${GREEN}✓ 电源LED已恢复 (淡白色)${NC}"
            ;;
        2)
            echo -e "${CYAN}恢复网络LED...${NC}"
            "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 2>/dev/null
            echo -e "${GREEN}✓ 网络LED已恢复${NC}"
            ;;
        3)
            echo -e "${CYAN}恢复所有系统LED...${NC}"
            "$UGREEN_CLI" power -color "128 128 128" -brightness 64 2>/dev/null
            "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 2>/dev/null
            echo -e "${GREEN}✓ 系统LED已恢复${NC}"
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 主菜单
show_main_menu() {
    clear
    show_system_info
    
    echo -e "${YELLOW}主菜单:${NC}"
    echo
    echo "1. 设置灯光"
    echo "2. 硬盘设置"
    echo "3. 后台服务管理"
    echo "4. 恢复系统LED"
    echo "5. 系统信息"
    echo "6. 退出"
    echo
    read -p "请选择功能 (1-6): " choice
    
    case $choice in
        1)
            manage_lights
            ;;
        2)
            manage_disks
            ;;
        3)
            manage_service
            ;;
        4)
            restore_system_leds
            ;;
        5)
            show_system_info
            read -p "按回车键继续..."
            ;;
        6)
            echo -e "${GREEN}感谢使用 $PROJECT_NAME${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            sleep 1
            ;;
    esac
}

# 主程序
main() {
    # 检查安装
    check_installation
    
    # 主循环
    while true; do
        show_main_menu
    done
}

# 运行主程序
main "$@"

# 检测硬盘映射
detect_disk_mapping() {
    echo "正在检测硬盘映射..."
    
    # 检测实际硬盘
    DISKS=()
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
        fi
    done
    
    echo "检测到硬盘: ${DISKS[*]}"
    
    # 读取配置文件（如果存在）
    declare -gA DISK_LED_MAP
    local config_file="/opt/ugreen-led-controller/config/disk_mapping.conf"
    
    if [[ -f "$config_file" ]]; then
        echo "加载配置文件: $config_file"
        while IFS='=' read -r disk led; do
            # 跳过注释和空行
            [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
            DISK_LED_MAP["$disk"]="$led"
        done < "$config_file"
    else
        echo "未找到配置文件，使用默认映射..."
        # 仅在没有配置文件时才使用默认映射
        DISK_LED_MAP["/dev/sda"]="disk1"
        DISK_LED_MAP["/dev/sdb"]="disk2" 
        DISK_LED_MAP["/dev/sdc"]="disk3"
        DISK_LED_MAP["/dev/sdd"]="disk4"
    fi
    
    # 显示当前映射
    echo "当前硬盘映射:"
    for disk in "${DISKS[@]}"; do
        local led_mapping="${DISK_LED_MAP[$disk]:-未映射}"
        if [[ "$led_mapping" == "none" ]]; then
            led_mapping="不映射"
        fi
        echo "  $disk -> $led_mapping"
    done
}

# 获取硬盘状态
get_disk_status() {
    local disk="$1"
    local status="unknown"
    
    if [[ -b "$disk" ]]; then
        # 检查硬盘活动状态
        local iostat_output=$(iostat -x 1 1 2>/dev/null | grep "$(basename "$disk")" | tail -1)
        if [[ -n "$iostat_output" ]]; then
            local util=$(echo "$iostat_output" | awk '{print $NF}' | sed 's/%//')
            if [[ -n "$util" ]] && (( $(echo "$util > 5" | bc -l) )); then
                status="active"
            else
                status="idle"
            fi
        else
            # 备用检测方法
            if [[ -r "/sys/block/$(basename "$disk")/stat" ]]; then
                local read1=$(awk '{print $1}' "/sys/block/$(basename "$disk")/stat")
                sleep 1
                local read2=$(awk '{print $1}' "/sys/block/$(basename "$disk")/stat")
                if [[ "$read2" -gt "$read1" ]]; then
                    status="active"
                else
                    status="idle"
                fi
            fi
        fi
    fi
    
    echo "$status"
}

# 设置硬盘LED状态
set_disk_led() {
    local disk="$1"
    local status="$2"
    local led_name="${DISK_LED_MAP[$disk]}"
    
    # 跳过未映射或不映射的硬盘
    if [[ -z "$led_name" || "$led_name" == "none" ]]; then
        return 0
    fi
    
    if [[ -n "$led_name" ]]; then
        case "$status" in
            "active")
                $UGREEN_LEDS_CLI "$led_name" -color 0 255 0 -on -brightness 255
                ;;
            "idle")
                $UGREEN_LEDS_CLI "$led_name" -color 255 255 0 -on -brightness 64
                ;;
            "error")
                $UGREEN_LEDS_CLI "$led_name" -color 255 0 0 -blink 500 500 -brightness 255
                ;;
            "off")
                $UGREEN_LEDS_CLI "$led_name" -off
                ;;
        esac
    fi
}

# 恢复系统LED状态
restore_system_leds() {
    echo "恢复系统LED状态..."
    
    # 恢复电源LED (绿色常亮)
    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 128
    
    # 恢复网络LED (根据网络状态)
    if ip route | grep -q default; then
        # 有网络连接，蓝色常亮
        $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 128
    else
        # 无网络连接，橙色常亮
        $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 64
    fi
    
    echo "系统LED已恢复正常"
}

# 显示硬盘映射信息
show_disk_mapping() {
    echo -e "${CYAN}硬盘LED映射信息:${NC}"
    echo "=================="
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        
        # 如果是不映射，则不显示状态
        if [[ "$led_name" == "none" ]]; then
            printf "%-12s -> %-6s %s\n" "$disk" "不映射" "${model:0:20}"
        elif [[ -z "$led_name" ]]; then
            printf "%-12s -> %-6s [%s] %s\n" "$disk" "未设置" "$status" "${model:0:20}"
        else
            printf "%-12s -> %-6s [%s] %s\n" "$disk" "$led_name" "$status" "${model:0:20}"
        fi
    done
    echo
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}绿联LED控制工具 v$VERSION (智能硬盘映射)${NC}"
    echo "=================================="
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 智能硬盘状态显示"
    echo "4) 实时硬盘活动监控"
    echo "5) 彩虹效果"
    echo "6) 节能模式"
    echo "7) 夜间模式"
    echo "8) 显示硬盘映射"
    echo "9) 配置硬盘映射"
    echo "s) 恢复系统LED (电源+网络)"
    echo "0) 退出"
    echo "=================================="
    echo -n "请选择: "
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
    "--on")
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--disk-status")
        detect_disk_mapping
        echo "设置智能硬盘状态..."
        for disk in "${DISKS[@]}"; do
            status=$(get_disk_status "$disk")
            set_disk_led "$disk" "$status"
            echo "$disk -> ${DISK_LED_MAP[$disk]} [$status]"
        done
        ;;
    "--monitor")
        detect_disk_mapping
        echo "启动实时硬盘监控 (按Ctrl+C停止)..."
        while true; do
            for disk in "${DISKS[@]}"; do
                status=$(get_disk_status "$disk")
                set_disk_led "$disk" "$status"
            done
            sleep 2
        done
        ;;
    "--system")
        restore_system_leds
        ;;
    "--help")
        echo "绿联LED控制工具 v$VERSION"
        echo "用法: LLLED [选项]"
        echo "  --off          关闭所有LED"
        echo "  --on           打开所有LED"
        echo "  --disk-status  智能硬盘状态显示"
        echo "  --monitor      实时硬盘活动监控"
        echo "  --system       恢复系统LED (电源+网络)"
        echo "  --version      显示版本信息"
        echo "  --help         显示帮助"
        ;;
    "--version")
        echo "绿联LED控制工具 v$VERSION"
        echo "项目地址: https://github.com/BearHero520/LLLED"
        echo "功能: 智能硬盘映射 | 实时监控 | LED控制"
        ;;
    "menu"|"")
        detect_disk_mapping
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) 
                    $UGREEN_LEDS_CLI all -off
                    echo "已关闭所有LED"
                    read -p "按回车继续..."
                    ;;
                2) 
                    $UGREEN_LEDS_CLI all -on
                    echo "已打开所有LED"
                    read -p "按回车继续..."
                    ;;
                3) 
                    echo "设置智能硬盘状态..."
                    for disk in "${DISKS[@]}"; do
                        status=$(get_disk_status "$disk")
                        set_disk_led "$disk" "$status"
                        echo "$disk -> ${DISK_LED_MAP[$disk]} [$status]"
                    done
                    echo "智能硬盘状态已设置"
                    read -p "按回车继续..."
                    ;;
                4) 
                    echo "启动实时硬盘监控 (按Ctrl+C返回菜单)..."
                    trap 'echo "停止监控"; break' INT
                    while true; do
                        clear
                        echo -e "${CYAN}实时硬盘活动监控${NC}"
                        echo "===================="
                        for disk in "${DISKS[@]}"; do
                            status=$(get_disk_status "$disk")
                            set_disk_led "$disk" "$status"
                            led_name="${DISK_LED_MAP[$disk]}"
                            printf "%-12s -> %-6s [%s]\n" "$disk" "$led_name" "$status"
                        done
                        echo "按Ctrl+C停止监控"
                        sleep 2
                    done
                    trap - INT
                    ;;
                5) 
                    echo "启动彩虹效果 (按Ctrl+C停止)..."
                    trap 'echo "停止彩虹效果"; break' INT
                    while true; do
                        $UGREEN_LEDS_CLI all -color 255 0 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 255 -on; sleep 1
                    done
                    trap - INT
                    ;;
                6) 
                    echo "设置节能模式..."
                    # 保持电源LED低亮度显示
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 32
                    # 保持网络LED低亮度显示
                    if ip route | grep -q default; then
                        $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 32
                    else
                        $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 32
                    fi
                    # 关闭硬盘LED
                    for i in {1..4}; do $UGREEN_LEDS_CLI disk$i -off; done
                    echo "节能模式已设置 (保持系统LED显示)"
                    read -p "按回车继续..."
                    ;;
                7) 
                    echo "设置夜间模式..."
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 16
                    echo "夜间模式已设置"
                    read -p "按回车继续..."
                    ;;
                8)
                    show_disk_mapping
                    read -p "按回车继续..."
                    ;;
                9)
                    echo -e "${YELLOW}硬盘映射配置${NC}"
                    echo "当前映射:"
                    show_disk_mapping
                    echo
                    echo "选项:"
                    echo "1) 运行映射测试工具"
                    echo "2) 交互式配置映射 (推荐)"
                    echo -n "请选择: "
                    read -r sub_choice
                    case $sub_choice in
                        1)
                            if [[ -x "/opt/ugreen-led-controller/scripts/led_mapping_test.sh" ]]; then
                                /opt/ugreen-led-controller/scripts/led_mapping_test.sh
                            else
                                echo "映射测试工具未找到"
                            fi
                            ;;
                        2)
                            if [[ -x "/opt/ugreen-led-controller/scripts/configure_mapping.sh" ]]; then
                                echo "启动交互式硬盘映射配置工具..."
                                /opt/ugreen-led-controller/scripts/configure_mapping.sh --configure
                                echo "配置完成，重新加载映射..."
                                detect_disk_mapping
                            else
                                echo "交互式配置工具未找到"
                                echo "手动编辑配置文件: /opt/ugreen-led-controller/config/disk_mapping.conf"
                                echo "格式: /dev/设备名=led名称"
                                echo "例如: /dev/sda=disk4  # 将sda映射到第4个LED"
                            fi
                            ;;
                    esac
                    read -p "按回车继续..."
                    ;;
                s|S)
                    restore_system_leds
                    read -p "按回车继续..."
                    ;;
                0) 
                    echo "退出"
                    exit 0
                    ;;
                *) 
                    echo "无效选项"
                    ;;
            esac
        done
        ;;
    *)
        echo "LLLED v$VERSION - 未知选项: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac
