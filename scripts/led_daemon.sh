#!/bin/bash

# UGREEN LED 后台监控服务
# 自动监控硬盘状态变化和插拔事件
# 功能: 活动检测、休眠监控、插拔响应、LED状态控制

# 服务配置
SERVICE_NAME="ugreen-led-monitor"
LOG_FILE="/var/log/${SERVICE_NAME}.log"
PID_FILE="/var/run/${SERVICE_NAME}.pid"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "需要root权限运行后台服务"
    exit 1
fi

# 查找主控制脚本
MAIN_SCRIPT="/opt/ugreen-led-controller/ugreen_led_controller_optimized.sh"
if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo "未找到主控制脚本: $MAIN_SCRIPT"
    exit 1
fi

# 后台监控函数
background_monitor() {
    log_message "UGREEN LED监控服务启动"
    
    # 设置扫描间隔（默认30秒）
    local scan_interval=${1:-30}
    log_message "扫描间隔设置为: ${scan_interval}秒"
    
    # 记录PID
    echo $$ > "$PID_FILE"
    
    # 初始化系统
    source "$MAIN_SCRIPT"
    
    # 检测系统
    if ! detect_system; then
        log_message "系统检测失败，服务退出"
        exit 1
    fi
    
    log_message "系统检测成功 - LED数量: ${#AVAILABLE_LEDS[@]}, 硬盘数量: ${#DISKS[@]}"
    
    # 恢复系统LED
    restore_system_leds
    log_message "系统LED已恢复"
    
    local last_disk_count=${#DISKS[@]}
    local scan_counter=0
    
    # 主监控循环
    while true; do
        # 定期重新扫描硬盘
        if (( scan_counter % scan_interval == 0 )); then
            log_message "重新扫描硬盘设备..."
            
            # 重新检测硬盘
            if detect_disk_mapping_hctl; then
                log_message "HCTL重新检测成功"
            else
                log_message "HCTL检测失败，使用备用方式"
                detect_disk_mapping_fallback
            fi
            
            # 检查硬盘数量变化
            if [[ ${#DISKS[@]} -ne $last_disk_count ]]; then
                log_message "硬盘数量变化: $last_disk_count -> ${#DISKS[@]}"
                last_disk_count=${#DISKS[@]}
                
                # 重新恢复系统LED
                restore_system_leds
            fi
        fi
        
        # 更新所有硬盘LED状态 (监控活动、休眠、离线状态)
        for disk in "${DISKS[@]}"; do
            local status=$(get_disk_status "$disk")
            set_disk_led "$disk" "$status"
        done
        
        ((scan_counter++))
        sleep 1
    done
}

# 服务控制函数
case "${1:-start}" in
    "start")
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "服务已在运行 (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        
        echo "启动UGREEN LED监控服务..."
        # 扫描间隔参数（默认30秒）
        scan_interval=${2:-30}
        
        # 后台运行
        nohup bash "$0" _background "$scan_interval" > /dev/null 2>&1 &
        sleep 2
        
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}✓ 服务启动成功 (PID: $(cat "$PID_FILE"))${NC}"
            echo "扫描间隔: ${scan_interval}秒"
            echo "日志文件: $LOG_FILE"
        else
            echo -e "${RED}✗ 服务启动失败${NC}"
            exit 1
        fi
        ;;
        
    "stop")
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "停止UGREEN LED监控服务..."
                kill "$pid"
                rm -f "$PID_FILE"
                echo -e "${GREEN}✓ 服务已停止${NC}"
            else
                echo "服务未在运行"
                rm -f "$PID_FILE"
            fi
        else
            echo "服务未在运行"
        fi
        ;;
        
    "restart")
        "$0" stop
        sleep 2
        "$0" start "${2:-30}"
        ;;
        
    "status")
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}✓ 服务正在运行 (PID: $(cat "$PID_FILE"))${NC}"
            echo "日志文件: $LOG_FILE"
            if [[ -f "$LOG_FILE" ]]; then
                echo "最近日志:"
                tail -5 "$LOG_FILE"
            fi
        else
            echo -e "${RED}✗ 服务未运行${NC}"
            [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
        fi
        ;;
        
    "logs")
        if [[ -f "$LOG_FILE" ]]; then
            tail -f "$LOG_FILE"
        else
            echo "日志文件不存在: $LOG_FILE"
        fi
        ;;
        
    "_background")
        # 内部使用，启动后台监控
        background_monitor "$2"
        ;;
        
    *)
        echo "用法: $0 {start|stop|restart|status|logs} [扫描间隔秒数]"
        echo "扫描间隔选项: 2(快速) 30(标准) 60(节能)"
        exit 1
        ;;
esac
