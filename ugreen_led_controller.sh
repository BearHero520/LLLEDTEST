#!/bin/bash

# UGREEN LED 控制器 - 主控制脚本
# 版本: 4.0.0
# 简化重构版

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$INSTALL_DIR/config"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
UGREEN_CLI="$INSTALL_DIR/ugreen_leds_cli"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 加载配置
load_config() {
    if [[ -f "$CONFIG_DIR/global_config.conf" ]]; then
        source "$CONFIG_DIR/global_config.conf"
    fi
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        source "$CONFIG_DIR/led_config.conf"
    fi
    # 从配置读取版本号
    VERSION="${LLLED_VERSION:-${VERSION:-4.0.0}}"
}

# 检查安装
check_installation() {
    if [[ ! -f "$UGREEN_CLI" ]] || [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: LED控制程序未正确安装${NC}"
        echo "请运行安装脚本: sudo bash quick_install.sh"
        exit 1
    fi
}

# 获取所有LED
get_all_leds() {
    local all_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    local leds=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+): ]]; then
            leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$all_status"
    
    echo "${leds[@]}"
}

# 关闭所有LED
turn_off_all_leds() {
    echo -e "${CYAN}关闭所有LED...${NC}"
    local leds=($(get_all_leds))
    
    if [[ ${#leds[@]} -eq 0 ]]; then
        # 备用方法：先尝试 all 参数
        "$UGREEN_CLI" all -off >/dev/null 2>&1 || true
        
        # 如果 all 参数失败，尝试系统LED和常见硬盘LED
        for led in power netdev; do
            "$UGREEN_CLI" "$led" -off 2>/dev/null || true
        done
        
        # 从配置文件读取实际存在的硬盘LED
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    "$UGREEN_CLI" "disk$i" -off 2>/dev/null || true
                fi
            done
        fi
    else
        for led in "${leds[@]}"; do
            "$UGREEN_CLI" "$led" -off 2>/dev/null || true
        done
    fi
    
    # 确保所有LED关闭
    "$UGREEN_CLI" all -off >/dev/null 2>&1 || true
    
    echo -e "${GREEN}✓ 所有LED已关闭${NC}"
}

# 打开所有LED
turn_on_all_leds() {
    echo -e "${CYAN}打开所有LED...${NC}"
    local leds=($(get_all_leds))
    local color="${POWER_COLOR:-128 128 128}"
    local brightness="${DEFAULT_BRIGHTNESS:-64}"
    
    if [[ ${#leds[@]} -eq 0 ]]; then
        # 备用方法：从配置文件读取实际存在的LED
        for led in power netdev; do
            "$UGREEN_CLI" "$led" -color $color -brightness $brightness -on 2>/dev/null || true
        done
        
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    "$UGREEN_CLI" "disk$i" -color $color -brightness $brightness -on 2>/dev/null || true
                fi
            done
        fi
    else
        for led in "${leds[@]}"; do
            "$UGREEN_CLI" "$led" -color $color -brightness $brightness -on 2>/dev/null || true
        done
    fi
    
    echo -e "${GREEN}✓ 所有LED已打开${NC}"
}

# 智能模式 - 启动后台监控服务
smart_mode() {
    echo -e "${CYAN}启动智能模式（后台监控服务）...${NC}"
    if systemctl start ugreen-led-monitor.service; then
        echo -e "${GREEN}✓ 智能模式已启动${NC}"
        echo -e "${BLUE}后台服务正在运行，将自动监控硬盘状态并控制LED${NC}"
        
        # 显示服务状态
        if systemctl is-active --quiet ugreen-led-monitor.service; then
            echo -e "${GREEN}服务状态: 运行中${NC}"
        else
            echo -e "${YELLOW}服务状态: 启动中...${NC}"
        fi
    else
        echo -e "${RED}✗ 启动智能模式失败${NC}"
        echo -e "${YELLOW}请检查服务是否已正确安装${NC}"
    fi
}

# 设置开机自启
enable_autostart() {
    echo -e "${CYAN}设置开机自启...${NC}"
    if systemctl enable ugreen-led-monitor.service >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 开机自启已启用${NC}"
    else
        echo -e "${RED}✗ 启用开机自启失败${NC}"
    fi
}

# 关闭开机自启
disable_autostart() {
    echo -e "${CYAN}关闭开机自启...${NC}"
    if systemctl disable ugreen-led-monitor.service >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 开机自启已关闭${NC}"
    else
        echo -e "${RED}✗ 关闭开机自启失败${NC}"
    fi
}

# 查看映射状态
show_mapping_status() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}LED映射状态${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    # 显示LED配置
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        echo -e "${BLUE}LED配置:${NC}"
        echo "  电源LED: ID ${POWER_LED:-0}"
        echo "  网络LED: ID ${NETDEV_LED:-1}"
        
        # 显示硬盘LED - 从配置文件读取实际存在的LED
        local disk_count=0
        local disk_leds=()
        
        # 优先从配置文件读取
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    echo "  硬盘${i}LED: ID ${!var_name}"
                    disk_leds+=("disk$i")
                    ((disk_count++))
                fi
            done
        fi
        
        # 如果配置文件没有，尝试从实际检测
        if [[ $disk_count -eq 0 ]]; then
            local detected_leds=($(get_all_leds))
            for led in "${detected_leds[@]}"; do
                if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                    echo "  检测到LED: $led"
                    disk_leds+=("$led")
                    ((disk_count++))
                fi
            done
        fi
        
        echo "  检测到 $disk_count 个硬盘LED"
        echo
    fi
    
    # 显示硬盘映射
    if [[ -f "$CONFIG_DIR/disk_mapping.conf" ]]; then
        echo -e "${BLUE}硬盘映射:${NC}"
        local mapping_count=0
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
                local device="${BASH_REMATCH[1]}"
                local mapping="${BASH_REMATCH[2]}"
                IFS='|' read -r hctl led serial model size <<< "$mapping"
                echo "  $device -> $led (HCTL: $hctl)"
                echo "    型号: ${model:-Unknown} | 序列号: ${serial:-N/A} | 大小: ${size:-N/A}"
                ((mapping_count++))
            fi
        done < "$CONFIG_DIR/disk_mapping.conf"
        
        if [[ $mapping_count -eq 0 ]]; then
            echo "  (无硬盘映射)"
        fi
        echo
    fi
    
    # 显示服务状态
    echo -e "${BLUE}服务状态:${NC}"
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        echo -e "  状态: ${GREEN}运行中${NC}"
    else
        echo -e "  状态: ${RED}未运行${NC}"
    fi
    
    if systemctl is-enabled --quiet ugreen-led-monitor.service; then
        echo -e "  开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "  开机自启: ${YELLOW}未启用${NC}"
    fi
    echo
}

# 主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}UGREEN LED 控制器 v${VERSION}${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo "1. 关闭所有LED"
    echo "2. 打开所有LED"
    echo "3. 智能模式"
    echo "4. 设置开机自启"
    echo "5. 关闭开机自启"
    echo "6. 查看映射状态"
    echo "7. 退出"
    echo
    read -p "请选择功能 (1-7): " choice
    
    case $choice in
        1)
            turn_off_all_leds
            ;;
        2)
            turn_on_all_leds
            ;;
        3)
            smart_mode
            ;;
        4)
            enable_autostart
            ;;
        5)
            disable_autostart
            ;;
        6)
            show_mapping_status
            ;;
        7)
            echo -e "${GREEN}感谢使用！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 处理命令行参数
case "${1:-}" in
    "off"|"关闭")
        load_config
        check_installation
        turn_off_all_leds
        ;;
    "on"|"打开")
        load_config
        check_installation
        turn_on_all_leds
        ;;
    "smart"|"智能"|"intelligent")
        load_config
        check_installation
        smart_mode
        ;;
    "enable"|"启用")
        enable_autostart
        ;;
    "disable"|"禁用")
        disable_autostart
        ;;
    "status"|"状态")
        load_config
        show_mapping_status
        ;;
    "start")
        systemctl start ugreen-led-monitor.service
        ;;
    "stop")
        systemctl stop ugreen-led-monitor.service
        ;;
    "restart")
        systemctl restart ugreen-led-monitor.service
        ;;
    "--help"|"-h")
        echo "UGREEN LED 控制器 v$VERSION"
        echo
        echo "用法: sudo LLLED [命令]"
        echo
        echo "命令:"
        echo "  off, 关闭        - 关闭所有LED"
        echo "  on, 打开         - 打开所有LED"
        echo "  smart, 智能      - 启动智能模式（后台监控服务）"
        echo "  enable, 启用     - 设置开机自启"
        echo "  disable, 禁用    - 关闭开机自启"
        echo "  status, 状态     - 查看映射状态"
        echo "  start            - 启动服务"
        echo "  stop             - 停止服务"
        echo "  restart          - 重启服务"
        echo
        echo "不使用参数则进入交互模式"
        ;;
    "")
        load_config
        check_installation
        while true; do
            show_main_menu
        done
        ;;
    *)
        echo "未知参数: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac
