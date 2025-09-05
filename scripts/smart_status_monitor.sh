#!/bin/bash

# LLLED 智能状态监控脚本
# 基于用户自定义颜色配置显示设备状态
# 支持电源、网络、硬盘的实时状态监控

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"
COLOR_CONFIG="$SCRIPT_DIR/config/color_themes.conf"
LOG_FILE="/var/log/llled_status_monitor.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查并加载颜色配置
load_color_config() {
    if [[ -f "$COLOR_CONFIG" ]]; then
        source "$COLOR_CONFIG"
        log_message "加载用户颜色配置"
    else
        # 使用默认颜色配置
        POWER_NORMAL="255 255 255"
        POWER_STANDBY="255 255 0"
        POWER_ERROR="255 0 0"
        
        NETWORK_ACTIVE="0 255 0"
        NETWORK_IDLE="255 255 0"
        NETWORK_ERROR="255 0 0"
        NETWORK_OFFLINE="0 0 0"
        
        DISK_ACTIVE="0 255 0"
        DISK_IDLE="255 255 0"
        DISK_ERROR="255 0 0"
        DISK_OFFLINE="0 0 0"
        
        log_message "使用默认颜色配置"
    fi
}

# 日志函数
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[$timestamp]${NC} $message"
    fi
}

# 设置LED状态（带颜色和模式）
set_led_status() {
    local led_name="$1"
    local color="$2"
    local mode="$3"
    local brightness="$4"
    
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "错误: ugreen_leds_cli 未找到"
        return 1
    fi
    
    local cmd="$UGREEN_LEDS_CLI $led_name -color $color"
    
    case "$mode" in
        "on")
            cmd="$cmd -on -brightness $brightness"
            ;;
        "off")
            cmd="$cmd -off"
            ;;
        "blink")
            cmd="$cmd -blink 500 500 -brightness $brightness"
            ;;
        "fast_blink")
            cmd="$cmd -blink 200 200 -brightness $brightness"
            ;;
        "breath")
            cmd="$cmd -breath 2000 1000 -brightness $brightness"
            ;;
    esac
    
    eval "$cmd" >/dev/null 2>&1
    return $?
}

# 检查网络状态
check_network_status() {
    local network_test_host="${NETWORK_TEST_HOST:-8.8.8.8}"
    local timeout="${NETWORK_TIMEOUT:-3}"
    
    # 检查网络接口状态
    local interface_up=false
    for interface in /sys/class/net/*/operstate; do
        if [[ -f "$interface" ]] && [[ "$(cat "$interface")" == "up" ]]; then
            local iface_name=$(basename "$(dirname "$interface")")
            if [[ "$iface_name" != "lo" ]]; then
                interface_up=true
                break
            fi
        fi
    done
    
    if [[ "$interface_up" == "false" ]]; then
        echo "OFFLINE"
        return
    fi
    
    # 检查网络连通性
    if ping -c 1 -W "$timeout" "$network_test_host" >/dev/null 2>&1; then
        # 检查网络活动（简单的流量检测）
        local rx_bytes1=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | awk '{sum+=$1} END {print sum}')
        local tx_bytes1=$(cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null | awk '{sum+=$1} END {print sum}')
        
        sleep 1
        
        local rx_bytes2=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | awk '{sum+=$1} END {print sum}')
        local tx_bytes2=$(cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null | awk '{sum+=$1} END {print sum}')
        
        local rx_diff=$((rx_bytes2 - rx_bytes1))
        local tx_diff=$((tx_bytes2 - tx_bytes1))
        
        if [[ $rx_diff -gt 1000 ]] || [[ $tx_diff -gt 1000 ]]; then
            echo "ACTIVE"
        else
            echo "IDLE"
        fi
    else
        echo "ERROR"
    fi
}

# 检查硬盘状态
check_disk_status() {
    local disk_name="$1"
    
    if [[ ! -e "/dev/$disk_name" ]]; then
        echo "OFFLINE"
        return
    fi
    
    # 检查SMART状态
    local smart_status="UNKNOWN"
    if command -v smartctl >/dev/null 2>&1; then
        local smart_result=$(smartctl -H "/dev/$disk_name" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
        case "${smart_result^^}" in
            "PASSED"|"OK") smart_status="HEALTHY" ;;
            "FAILED") smart_status="ERROR" ;;
        esac
    fi
    
    if [[ "$smart_status" == "ERROR" ]]; then
        echo "ERROR"
        return
    fi
    
    # 检查硬盘活动
    local disk_stats="/sys/block/$disk_name/stat"
    if [[ -f "$disk_stats" ]]; then
        local read1=$(awk '{print $1}' "$disk_stats")
        local write1=$(awk '{print $5}' "$disk_stats")
        
        sleep 1
        
        local read2=$(awk '{print $1}' "$disk_stats")
        local write2=$(awk '{print $5}' "$disk_stats")
        
        local read_diff=$((read2 - read1))
        local write_diff=$((write2 - write1))
        
        if [[ $read_diff -gt 0 ]] || [[ $write_diff -gt 0 ]]; then
            echo "ACTIVE"
        else
            echo "IDLE"
        fi
    else
        echo "IDLE"
    fi
}

# 更新电源LED状态
update_power_status() {
    # 检查系统负载来决定电源状态
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_level=$(echo "$load_avg > 2.0" | bc -l 2>/dev/null || echo 0)
    
    if [[ "$load_level" == "1" ]]; then
        # 高负载 - 使用正常状态
        set_led_status "power" "$POWER_NORMAL" "on" "128"
        log_message "电源LED: 正常状态 (负载: $load_avg)"
    else
        # 低负载 - 使用待机状态
        set_led_status "power" "$POWER_STANDBY" "on" "64"
        log_message "电源LED: 待机状态 (负载: $load_avg)"
    fi
}

# 更新网络LED状态
update_network_status() {
    local network_status
    network_status=$(check_network_status)
    
    case "$network_status" in
        "ACTIVE")
            set_led_status "netdev" "$NETWORK_ACTIVE" "on" "128"
            log_message "网络LED: 活动状态 (🟢 传输中)"
            ;;
        "IDLE")
            set_led_status "netdev" "$NETWORK_IDLE" "on" "32"
            log_message "网络LED: 空闲状态 (🟡 待机)"
            ;;
        "ERROR")
            set_led_status "netdev" "$NETWORK_ERROR" "blink" "255"
            log_message "网络LED: 错误状态 (🔴 故障)"
            ;;
        "OFFLINE")
            set_led_status "netdev" "$NETWORK_OFFLINE" "off" "0"
            log_message "网络LED: 离线状态 (⚫ 灯光关闭)"
            ;;
    esac
}

# 更新硬盘LED状态
update_disk_status() {
    # 获取所有SATA硬盘
    local disk_list=()
    for dev in /dev/sd[a-z]; do
        if [[ -e "$dev" ]]; then
            local disk_name=$(basename "$dev")
            local transport=$(lsblk -d -n -o TRAN "/dev/$disk_name" 2>/dev/null)
            if [[ "$transport" == "sata" ]]; then
                disk_list+=("$disk_name")
            fi
        fi
    done
    
    # 更新每个硬盘的LED状态
    local disk_num=1
    for disk_name in "${disk_list[@]}"; do
        if [[ $disk_num -gt 8 ]]; then
            break  # 最多支持8个硬盘LED
        fi
        
        local led_name="disk$disk_num"
        local disk_status
        disk_status=$(check_disk_status "$disk_name")
        
        case "$disk_status" in
            "ACTIVE")
                set_led_status "$led_name" "$DISK_ACTIVE" "on" "128"
                log_message "硬盘${disk_num}LED: 活动状态 (🟢 读写中)"
                ;;
            "IDLE")
                set_led_status "$led_name" "$DISK_IDLE" "on" "32"
                log_message "硬盘${disk_num}LED: 空闲状态 (🟡 待机)"
                ;;
            "ERROR")
                set_led_status "$led_name" "$DISK_ERROR" "fast_blink" "255"
                log_message "硬盘${disk_num}LED: 错误状态 (🔴 故障)"
                ;;
            "OFFLINE")
                set_led_status "$led_name" "$DISK_OFFLINE" "off" "0"
                log_message "硬盘${disk_num}LED: 离线状态 (⚫ 灯光关闭)"
                ;;
        esac
        
        ((disk_num++))
    done
    
    # 关闭多余的硬盘LED
    for ((i=disk_num; i<=8; i++)); do
        set_led_status "disk$i" "0 0 0" "off" "0" 2>/dev/null
    done
}

# 监控循环
monitor_loop() {
    local interval="${MONITOR_INTERVAL:-30}"
    
    log_message "开始智能状态监控 (间隔: ${interval}秒)"
    
    while true; do
        # 更新所有LED状态
        update_power_status
        update_network_status
        update_disk_status
        
        sleep "$interval"
    done
}

# 显示当前状态
show_current_status() {
    echo -e "${CYAN}=== LLLED 当前状态 ===${NC}"
    echo ""
    
    # 网络状态
    local network_status
    network_status=$(check_network_status)
    echo -e "${BLUE}网络状态:${NC} $network_status"
    
    # 硬盘状态
    echo -e "${BLUE}硬盘状态:${NC}"
    local disk_num=1
    for dev in /dev/sd[a-z]; do
        if [[ -e "$dev" ]] && [[ $disk_num -le 8 ]]; then
            local disk_name=$(basename "$dev")
            local transport=$(lsblk -d -n -o TRAN "/dev/$disk_name" 2>/dev/null)
            if [[ "$transport" == "sata" ]]; then
                local disk_status
                disk_status=$(check_disk_status "$disk_name")
                echo "  硬盘$disk_num ($disk_name): $disk_status"
                ((disk_num++))
            fi
        fi
    done
    
    # 系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    echo -e "${BLUE}系统负载:${NC} $load_avg"
}

# 使用说明
show_usage() {
    echo "LLLED 智能状态监控"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -m, --monitor     启动持续监控模式"
    echo "  -s, --status      显示当前状态"
    echo "  -o, --once        运行一次状态更新"
    echo "  -v, --verbose     详细输出模式"
    echo "  -h, --help        显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -m             # 启动持续监控"
    echo "  $0 -s             # 查看当前状态"
    echo "  $0 -o -v          # 运行一次并显示详细信息"
}

# 主函数
main() {
    local mode="help"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--monitor)
                mode="monitor"
                shift
                ;;
            -s|--status)
                mode="status"
                shift
                ;;
            -o|--once)
                mode="once"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                mode="help"
                shift
                ;;
            *)
                echo "未知参数: $1"
                mode="help"
                shift
                ;;
        esac
    done
    
    # 检查依赖
    if [[ ! -f "$UGREEN_LEDS_CLI" ]] && [[ "$mode" != "help" ]]; then
        echo -e "${RED}错误: ugreen_leds_cli 未找到${NC}"
        echo "请先运行 quick_install.sh 安装LLLED系统"
        exit 1
    fi
    
    # 加载颜色配置
    load_color_config
    
    # 执行对应功能
    case "$mode" in
        "monitor")
            echo -e "${GREEN}启动智能状态监控...${NC}"
            monitor_loop
            ;;
        "status")
            show_current_status
            ;;
        "once")
            echo -e "${GREEN}运行一次状态更新...${NC}"
            update_power_status
            update_network_status
            update_disk_status
            echo -e "${GREEN}状态更新完成${NC}"
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 信号处理
trap 'echo -e "\n${YELLOW}停止监控...${NC}"; exit 0' SIGINT SIGTERM

# 运行主程序
main "$@"
