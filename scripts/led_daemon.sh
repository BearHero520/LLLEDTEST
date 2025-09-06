#!/bin/bash

# UGREEN LED 后台监控服务 v3.0.0
# 智能硬盘状态检测与LED控制守护进程
# 支持自动HCTL映射更新和错误恢复

# 服务配置
SERVICE_NAME="ugreen-led-monitor"
LLLED_VERSION="3.0.0"

# 路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="/var/log/llled"
PID_FILE="/var/run/${SERVICE_NAME}.pid"
LOG_FILE="$LOG_DIR/${SERVICE_NAME}.log"

# 配置文件
GLOBAL_CONFIG="$CONFIG_DIR/global_config.conf"
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
DISK_CONFIG="$CONFIG_DIR/disk_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 全局变量
declare -A DISK_LED_MAP          # 硬盘到LED的映射
declare -A DISK_STATUS_CACHE     # 硬盘状态缓存
declare -A DISK_HCTL_MAP         # HCTL映射信息
declare -A LED_STATUS_CACHE      # LED状态缓存
AVAILABLE_DISKS=()               # 可用硬盘列表
AVAILABLE_LEDS=()                # 可用LED列表
DAEMON_RUNNING=true              # 守护进程运行标志
LAST_HCTL_UPDATE=0               # 上次HCTL更新时间
CHECK_INTERVAL=5                 # 检查间隔(秒)
ERROR_COUNT=0                    # 错误计数
MAX_ERRORS=10                    # 最大错误次数

# 创建必要目录
mkdir -p "$LOG_DIR"

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # 控制台输出(仅在非后台模式)
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        case "$level" in
            "ERROR") echo -e "${RED}[$timestamp] [ERROR] $message${NC}" ;;
            "WARN")  echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}" ;;
            "INFO")  echo -e "${GREEN}[$timestamp] [INFO] $message${NC}" ;;
            "DEBUG") echo -e "${CYAN}[$timestamp] [DEBUG] $message${NC}" ;;
            *) echo "[$timestamp] [$level] $message" ;;
        esac
    fi
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "需要root权限运行后台服务"
        exit 1
    fi
}

# 加载配置文件
load_configs() {
    log_message "INFO" "加载配置文件..."
    
    # 加载全局配置
    if [[ -f "$GLOBAL_CONFIG" ]]; then
        source "$GLOBAL_CONFIG"
        log_message "INFO" "已加载全局配置: $GLOBAL_CONFIG"
    fi
    
    # 加载LED配置
    if [[ -f "$LED_CONFIG" ]]; then
        source "$LED_CONFIG"
        log_message "INFO" "已加载LED配置: $LED_CONFIG"
    else
        log_message "WARN" "LED配置文件不存在，使用默认配置"
        DEFAULT_BRIGHTNESS=64
        LOW_BRIGHTNESS=16
        HIGH_BRIGHTNESS=128
        DISK_COLOR_ACTIVE="255 255 255"    # 硬盘活动 - 白色
        DISK_COLOR_STANDBY="128 128 128"   # 硬盘休眠 - 淡白色
        DISK_COLOR_ERROR="0 0 0"           # 硬盘错误 - 不显示
        DISK_COLOR_WARNING="0 0 0"         # 硬盘警告 - 不显示
    fi
    
    # 应用配置中的检查间隔
    if [[ -n "${DISK_CHECK_INTERVAL:-}" ]]; then
        CHECK_INTERVAL="$DISK_CHECK_INTERVAL"
    fi
}

# 检查LED控制程序
check_led_cli() {
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "ERROR" "LED控制程序不存在或不可执行: $UGREEN_CLI"
        return 1
    fi
    
    # 测试LED控制程序
    if ! "$UGREEN_CLI" all -status >/dev/null 2>&1; then
        log_message "WARN" "LED控制程序测试失败，可能设备不兼容"
        return 1
    fi
    
    log_message "INFO" "LED控制程序检查通过"
    return 0
}

# 检测可用LED
detect_available_leds() {
    log_message "INFO" "检测可用LED..."
    AVAILABLE_LEDS=()
    
    # 尝试检测所有可能的LED
    for i in {1..16}; do
        local led_name="disk$i"
        if "$UGREEN_CLI" "$led_name" -status >/dev/null 2>&1; then
            AVAILABLE_LEDS+=("$led_name")
            log_message "DEBUG" "检测到LED: $led_name"
        fi
    done
    
    # 检测电源和网络LED
    for led in "power" "netdev"; do
        if "$UGREEN_CLI" "$led" -status >/dev/null 2>&1; then
            AVAILABLE_LEDS+=("$led")
            log_message "DEBUG" "检测到LED: $led"
        fi
    done
    
    log_message "INFO" "检测到 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}"
    return 0
}

# 获取硬盘状态 (使用hdparm，优先检测硬盘可访问性)
get_disk_status() {
    local disk="$1"
    
    # 首先检查设备文件是否存在
    if [[ ! -b "$disk" ]]; then
        echo "not_found"
        return 1
    fi
    
    # 使用hdparm检查硬盘状态 - 这是关键的可访问性测试
    local hdparm_output
    hdparm_output=$(timeout 10 hdparm -C "$disk" 2>&1)
    local hdparm_exit_code=$?
    
    # hdparm超时或失败，说明硬盘无响应（可能已拔出）
    if [[ $hdparm_exit_code -ne 0 ]]; then
        if [[ "$hdparm_output" =~ "No such file or directory" ]]; then
            echo "not_found"
            return 1
        elif [[ "$hdparm_output" =~ "Input/output error" ]] || [[ $hdparm_exit_code -eq 124 ]]; then
            # I/O错误或超时，说明硬盘可能已拔出但设备文件还在
            echo "not_found"
            return 1
        else
            echo "error"
            return 1
        fi
    fi
    
    # 成功获取hdparm输出，解析硬盘状态
    if [[ "$hdparm_output" =~ "drive state is:"[[:space:]]*([^[:space:]]+) ]]; then
        local drive_state="${BASH_REMATCH[1]}"
        case "$drive_state" in
            "active/idle"|"active"|"idle")
                echo "active"
                return 0
                ;;
            "standby"|"sleeping")
                echo "standby"
                return 0
                ;;
            *)
                echo "unknown"
                return 0
                ;;
        esac
    else
        # hdparm返回成功但无法解析状态，可能是硬盘问题
        echo "unknown"
        return 0
    fi
}

# 加载HCTL映射
load_hctl_mapping() {
    log_message "INFO" "加载HCTL映射配置..."
    
    if [[ ! -f "$HCTL_CONFIG" ]]; then
        log_message "WARN" "HCTL配置文件不存在: $HCTL_CONFIG"
        return 1
    fi
    
    # 清空现有映射
    DISK_LED_MAP=()
    DISK_HCTL_MAP=()
    
    # 读取HCTL映射配置
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 解析HCTL_MAPPING行
        if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"?([^\"]+)\"?$ ]]; then
            local disk_device="${BASH_REMATCH[1]}"
            local mapping_info="${BASH_REMATCH[2]}"
            
            # 解析映射信息: HCTL|LED|Serial|Model|Size
            IFS='|' read -r hctl_info led_pos serial model size <<< "$mapping_info"
            
            if [[ -n "$disk_device" && -n "$led_pos" ]]; then
                DISK_LED_MAP["$disk_device"]="$led_pos"
                DISK_HCTL_MAP["$disk_device"]="$hctl_info|$serial|$model|$size"
                log_message "DEBUG" "加载映射: $disk_device -> $led_pos (HCTL: $hctl_info)"
            fi
        fi
    done < "$HCTL_CONFIG"
    
    log_message "INFO" "已加载 ${#DISK_LED_MAP[@]} 个HCTL映射"
    return 0
}

# 重新获取HCTL映射 (调用智能硬盘状态显示逻辑)
refresh_hctl_mapping() {
    log_message "INFO" "重新获取HCTL硬盘映射..."
    
    # 调用智能硬盘状态显示脚本
    local hctl_script="$SCRIPT_DIR/scripts/smart_disk_activity_hctl.sh"
    if [[ -x "$hctl_script" ]]; then
        log_message "INFO" "调用HCTL检测脚本: $hctl_script"
        if "$hctl_script" --update-mapping; then
            log_message "INFO" "HCTL映射更新成功"
            # 重新加载映射
            load_hctl_mapping
            LAST_HCTL_UPDATE=$(date +%s)
            return 0
        else
            log_message "ERROR" "HCTL映射更新失败"
            return 1
        fi
    else
        log_message "ERROR" "HCTL检测脚本不存在: $hctl_script"
        return 1
    fi
}

# 获取当前可用硬盘列表
get_available_disks() {
    AVAILABLE_DISKS=()
    
    # 从映射中获取硬盘列表
    for disk in "${!DISK_LED_MAP[@]}"; do
        if [[ -b "$disk" ]]; then
            AVAILABLE_DISKS+=("$disk")
        fi
    done
    
    # 如果没有映射或映射中的硬盘都不存在，尝试自动检测
    if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
        log_message "WARN" "没有可用的映射硬盘，尝试自动检测..."
        for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [[ -b "$disk" ]]; then
                AVAILABLE_DISKS+=("$disk")
            fi
        done
    fi
    
    log_message "DEBUG" "可用硬盘: ${AVAILABLE_DISKS[*]}"
}

# 设置LED状态
set_led_status() {
    local led="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    # 检查LED是否在可用列表中
    if [[ ! " ${AVAILABLE_LEDS[*]} " =~ " $led " ]]; then
        log_message "DEBUG" "LED $led 不在可用列表中"
        return 1
    fi
    
    # 构建控制命令
    if [[ "$color" == "off" || "$color" == "0 0 0" ]]; then
        if "$UGREEN_CLI" "$led" -off >/dev/null 2>&1; then
            LED_STATUS_CACHE["$led"]="off"
            log_message "DEBUG" "LED $led 已关闭"
        else
            log_message "WARN" "关闭LED $led 失败"
            return 1
        fi
    else
        if "$UGREEN_CLI" "$led" -color "$color" -brightness "$brightness" >/dev/null 2>&1; then
            LED_STATUS_CACHE["$led"]="$color|$brightness"
            log_message "DEBUG" "LED $led 设置为 $color (亮度: $brightness)"
        else
            log_message "WARN" "设置LED $led 失败"
            return 1
        fi
    fi
    
    return 0
}

# 更新硬盘LED状态
update_disk_leds() {
    local updated_count=0
    local error_count=0
    
    # 获取当前可用硬盘
    get_available_disks
    
    # 首先处理所有映射中的硬盘（包括可能已拔出的）
    for disk in "${!DISK_LED_MAP[@]}"; do
        local led="${DISK_LED_MAP[$disk]:-}"
        
        # 如果没有LED映射，跳过
        if [[ -z "$led" || "$led" == "none" ]]; then
            log_message "DEBUG" "硬盘 $disk 没有LED映射"
            continue
        fi
        
        # 通过获取硬盘状态来判断硬盘是否存在和可用
        local disk_status
        disk_status=$(get_disk_status "$disk")
        local status_result=$?
        
        log_message "DEBUG" "硬盘 $disk 状态检测: status=$disk_status, result=$status_result"
        
        # 如果无法获取状态，说明硬盘已经拔出或无响应
        if [[ $status_result -ne 0 ]]; then
            case "$disk_status" in
                "not_found"|"error")
                    log_message "WARN" "硬盘 $disk 无法访问 (状态: $disk_status)，关闭LED $led"
                    set_led_status "$led" "off"
                    # 从映射中移除无法访问的硬盘
                    unset DISK_LED_MAP["$disk"]
                    unset DISK_STATUS_CACHE["$disk"]
                    unset DISK_HCTL_MAP["$disk"]
                    ((updated_count++))
                    
                    # 如果是not_found，触发HCTL重映射
                    if [[ "$disk_status" == "not_found" ]]; then
                        log_message "INFO" "触发HCTL重映射以检测硬盘变化"
                        refresh_hctl_mapping >/dev/null 2>&1 &  # 后台执行，不阻塞
                    fi
                    continue
                    ;;
            esac
        fi
        
        # 检查状态是否变化
        local cached_status="${DISK_STATUS_CACHE[$disk]:-}"
        if [[ "$disk_status" == "$cached_status" ]]; then
            log_message "DEBUG" "硬盘 $disk 状态无变化: $disk_status"
            continue
        fi
        
        # 更新状态缓存
        DISK_STATUS_CACHE["$disk"]="$disk_status"
        
        # 根据硬盘状态设置LED
        case "$disk_status" in
            "active")
                log_message "INFO" "硬盘 $disk 活动状态 -> LED $led"
                set_led_status "$led" "$DISK_COLOR_ACTIVE" "$HIGH_BRIGHTNESS"
                ((updated_count++))
                ;;
            "standby")
                log_message "INFO" "硬盘 $disk 休眠状态 -> LED $led"
                set_led_status "$led" "$DISK_COLOR_STANDBY" "$LOW_BRIGHTNESS"
                ((updated_count++))
                ;;
            "unknown")
                log_message "WARN" "硬盘 $disk 状态未知 -> 关闭LED"
                set_led_status "$led" "off"
                ((updated_count++))
                ;;
            *)
                log_message "WARN" "硬盘 $disk 未知状态: $disk_status"
                ;;
        esac
    done
    
    # 更新统计信息
    if [[ $error_count -gt 0 ]]; then
        ERROR_COUNT=$((ERROR_COUNT + error_count))
        log_message "WARN" "本次更新遇到 $error_count 个错误，累计错误: $ERROR_COUNT"
        
        # 如果错误过多，触发HCTL重映射
        if [[ $ERROR_COUNT -ge $MAX_ERRORS ]]; then
            log_message "ERROR" "错误次数过多，触发HCTL重映射"
            if refresh_hctl_mapping; then
                ERROR_COUNT=0
                log_message "INFO" "HCTL重映射成功，错误计数已重置"
            fi
        fi
    else
        # 重置错误计数
        if [[ $ERROR_COUNT -gt 0 ]]; then
            ERROR_COUNT=0
            log_message "INFO" "硬盘状态正常，错误计数已重置"
        fi
    fi
    
    log_message "DEBUG" "LED更新完成，更新了 $updated_count 个LED"
}

# 信号处理函数
handle_signal() {
    local signal="$1"
    log_message "INFO" "收到信号: $signal，准备退出..."
    DAEMON_RUNNING=false
    
    # 清理LED状态 (可选)
    if [[ "${CLEANUP_ON_EXIT:-true}" == "true" ]]; then
        log_message "INFO" "清理LED状态..."
        for led in "${AVAILABLE_LEDS[@]}"; do
            if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                set_led_status "$led" "off"
            fi
        done
    fi
    
    # 移除PID文件
    rm -f "$PID_FILE"
    log_message "INFO" "后台服务已停止"
    exit 0
}

# 主循环
main_loop() {
    log_message "INFO" "后台监控循环启动，检查间隔: ${CHECK_INTERVAL}秒"
    
    while [[ "$DAEMON_RUNNING" == "true" ]]; do
        # 更新硬盘LED状态
        update_disk_leds
        
        # 检查是否需要定期更新HCTL映射
        local current_time=$(date +%s)
        local hctl_update_interval=$((3600))  # 1小时
        
        if [[ $((current_time - LAST_HCTL_UPDATE)) -gt $hctl_update_interval ]]; then
            log_message "INFO" "定期更新HCTL映射..."
            if refresh_hctl_mapping; then
                LAST_HCTL_UPDATE=$current_time
            fi
        fi
        
        # 等待下次检查
        sleep "$CHECK_INTERVAL"
    done
}

# 守护进程启动函数
start_daemon() {
    log_message "INFO" "启动LLLED后台监控服务 v$LLLED_VERSION"
    
    # 检查是否已经运行
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_message "ERROR" "服务已经运行，PID: $old_pid"
            exit 1
        else
            log_message "WARN" "清理过期的PID文件"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 写入PID文件
    echo $$ > "$PID_FILE"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    
    # 初始化
    check_root
    load_configs
    
    if ! check_led_cli; then
        log_message "ERROR" "LED控制程序检查失败，服务无法启动"
        exit 1
    fi
    
    detect_available_leds
    
    # 加载或刷新HCTL映射
    if ! load_hctl_mapping; then
        log_message "INFO" "首次运行，执行HCTL映射检测..."
        if ! refresh_hctl_mapping; then
            log_message "ERROR" "初始HCTL映射失败，服务无法启动"
            exit 1
        fi
    fi
    
    # 启动主循环
    main_loop
}

# 服务状态检查
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "服务正在运行，PID: $pid"
            return 0
        else
            echo "服务未运行（PID文件过期）"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "服务未运行"
        return 1
    fi
}

# 停止服务
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "停止服务，PID: $pid"
            kill -TERM "$pid"
            
            # 等待进程退出
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 30 ]]; do
                sleep 1
                ((count++))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log_message "WARN" "强制停止服务"
                kill -KILL "$pid"
            fi
            
            rm -f "$PID_FILE"
            echo "服务已停止"
        else
            echo "服务未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "服务未运行"
    fi
}

# 重启服务
restart_daemon() {
    stop_daemon
    sleep 2
    start_daemon
}

# 显示帮助信息
show_help() {
    echo "LLLED后台监控服务 v$LLLED_VERSION"
    echo "用法: $0 {start|stop|restart|status|help}"
    echo
    echo "命令说明:"
    echo "  start   - 启动后台服务"
    echo "  stop    - 停止后台服务"
    echo "  restart - 重启后台服务"
    echo "  status  - 查看服务状态"
    echo "  help    - 显示帮助信息"
    echo
    echo "日志文件: $LOG_FILE"
    echo "配置文件: $LED_CONFIG"
}

# 主程序入口
case "${1:-start}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        restart_daemon
        ;;
    status)
        check_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac
