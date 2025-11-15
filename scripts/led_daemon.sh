#!/bin/bash

# UGREEN LED 守护进程
# 版本: 4.0.0
# 简化重构版

SERVICE_NAME="ugreen-led-monitor"

# 路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="/var/log/llled"
PID_FILE="/var/run/${SERVICE_NAME}.pid"
LOG_FILE="$LOG_DIR/${SERVICE_NAME}.log"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 配置文件
LED_CONFIG="$CONFIG_DIR/led_config.conf"
DISK_MAPPING_CONFIG="$CONFIG_DIR/disk_mapping.conf"
GLOBAL_CONFIG="$CONFIG_DIR/global_config.conf"

# 从全局配置读取版本号
if [[ -f "$GLOBAL_CONFIG" ]]; then
    source "$GLOBAL_CONFIG" 2>/dev/null || true
fi
VERSION="${LLLED_VERSION:-${VERSION:-4.0.0}}"

# 全局变量
declare -A DISK_LED_MAP
declare -A DISK_STATUS_CACHE
declare -A LED_STATUS_CACHE
DAEMON_RUNNING=true

# 创建目录
mkdir -p "$LOG_DIR" "$CONFIG_DIR"

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 信号处理
handle_signal() {
    log_message "INFO" "收到退出信号，正在停止..."
    DAEMON_RUNNING=false
    rm -f "$PID_FILE"
    exit 0
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { log_message "ERROR" "需要root权限"; exit 1; }
}

# 加载配置
load_config() {
    if [[ -f "$GLOBAL_CONFIG" ]]; then
        source "$GLOBAL_CONFIG" 2>/dev/null || true
    fi
    
    if [[ -f "$LED_CONFIG" ]]; then
        source "$LED_CONFIG" 2>/dev/null || true
    fi
    
    # 设置默认值
    DISK_CHECK_INTERVAL=${DISK_CHECK_INTERVAL:-30}
    NETWORK_CHECK_INTERVAL=${NETWORK_CHECK_INTERVAL:-60}
    SYSTEM_LED_UPDATE_INTERVAL=${SYSTEM_LED_UPDATE_INTERVAL:-60}
    DEFAULT_BRIGHTNESS=${DEFAULT_BRIGHTNESS:-64}
    LOW_BRIGHTNESS=${LOW_BRIGHTNESS:-32}
    
    # 颜色默认值
    POWER_COLOR=${POWER_COLOR:-"128 128 128"}
    NETWORK_COLOR_DISCONNECTED=${NETWORK_COLOR_DISCONNECTED:-"255 0 0"}
    NETWORK_COLOR_CONNECTED=${NETWORK_COLOR_CONNECTED:-"0 255 0"}
    NETWORK_COLOR_INTERNET=${NETWORK_COLOR_INTERNET:-"0 0 255"}
    DISK_COLOR_HEALTHY=${DISK_COLOR_HEALTHY:-"255 255 255"}
    DISK_COLOR_STANDBY=${DISK_COLOR_STANDBY:-"200 200 200"}
    DISK_COLOR_UNHEALTHY=${DISK_COLOR_UNHEALTHY:-"255 0 0"}
    DISK_COLOR_NO_DISK=${DISK_COLOR_NO_DISK:-"0 0 0"}
    
    log_message "INFO" "配置加载完成"
}

# 检查LED控制程序
check_led_cli() {
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "ERROR" "LED控制程序不存在"
        return 1
    fi
    return 0
}

# 加载硬盘映射
load_disk_mapping() {
    DISK_LED_MAP=()
    
    if [[ ! -f "$DISK_MAPPING_CONFIG" ]]; then
        log_message "WARN" "硬盘映射配置不存在"
        return 1
    fi
    
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
            local disk_device="${BASH_REMATCH[1]}"
            local mapping="${BASH_REMATCH[2]}"
            IFS='|' read -r hctl led_name serial model size <<< "$mapping"
            
            if [[ -n "$disk_device" && -n "$led_name" ]]; then
                DISK_LED_MAP["$disk_device"]="$led_name"
                log_message "DEBUG" "加载映射: $disk_device -> $led_name"
            fi
        fi
    done < "$DISK_MAPPING_CONFIG"
    
    log_message "INFO" "已加载 ${#DISK_LED_MAP[@]} 个硬盘映射"
    return 0
}

# 设置LED状态
set_led_status() {
    local led="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    # 检查缓存
    local cache_key="$led"
    local new_status="$color|$brightness"
    local cached_status="${LED_STATUS_CACHE[$cache_key]:-}"
    
    if [[ "$new_status" == "$cached_status" ]]; then
        return 0
    fi
    
    # 设置LED
    if [[ "$color" == "off" || "$color" == "0 0 0" ]]; then
        timeout 5 "$UGREEN_CLI" "$led" -off >/dev/null 2>&1 && {
            LED_STATUS_CACHE["$cache_key"]="off"
            return 0
        }
    else
        timeout 5 "$UGREEN_CLI" "$led" -color $color -brightness "$brightness" -on >/dev/null 2>&1 && {
            LED_STATUS_CACHE["$cache_key"]="$new_status"
            return 0
        }
    fi
    
    return 1
}

# 检查网络状态
check_network_status() {
    local test_host="${NETWORK_TEST_HOST:-8.8.8.8}"
    local timeout="${NETWORK_TIMEOUT:-3}"
    
    # 检查是否有网络接口
    if ! ip route get "$test_host" >/dev/null 2>&1; then
        echo "disconnected"
        return 2
    fi
    
    # 检查是否能连接外网
    if ping -c 1 -W "$timeout" "$test_host" >/dev/null 2>&1; then
        echo "internet"
        return 0
    fi
    
    # 有路由但无法访问外网
    echo "connected"
    return 1
}

# 更新网络LED
update_network_led() {
    local network_status
    network_status=$(check_network_status)
    
    local color brightness
    case "$network_status" in
        "internet")
            color="$NETWORK_COLOR_INTERNET"
            brightness="$DEFAULT_BRIGHTNESS"
            ;;
        "connected")
            color="$NETWORK_COLOR_CONNECTED"
            brightness="$DEFAULT_BRIGHTNESS"
            ;;
        "disconnected")
            color="$NETWORK_COLOR_DISCONNECTED"
            brightness="$DEFAULT_BRIGHTNESS"
            ;;
        *)
            color="off"
            brightness="0"
            ;;
    esac
    
    set_led_status "netdev" "$color" "$brightness"
}

# 更新电源LED
update_power_led() {
    set_led_status "power" "$POWER_COLOR" "$DEFAULT_BRIGHTNESS"
}

# 获取硬盘状态
get_disk_status() {
    local disk="$1"
    
    if [[ ! -b "$disk" ]]; then
        echo "not_found"
        return 1
    fi
    
    # 使用hdparm检查硬盘状态
    local hdparm_output
    hdparm_output=$(timeout 10 hdparm -C "$disk" 2>&1)
    local hdparm_exit_code=$?
    
    if [[ $hdparm_exit_code -ne 0 ]]; then
        echo "not_found"
        return 1
    fi
    
    # 解析状态
    if echo "$hdparm_output" | grep -q "active/idle\|active\|idle"; then
        # 检查SMART健康状态
        if command -v smartctl >/dev/null 2>&1; then
            local smart_result
            smart_result=$(smartctl -H "$disk" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
            if [[ "${smart_result^^}" == "FAILED" ]]; then
                echo "unhealthy"
                return 0
            fi
        fi
        echo "healthy"
        return 0
    elif echo "$hdparm_output" | grep -q "standby\|sleeping"; then
        echo "standby"
        return 0
    else
        echo "unknown"
        return 0
    fi
}

# 更新硬盘LED
update_disk_leds() {
    local updated_count=0
    
    # 如果没有映射，尝试加载
    if [[ ${#DISK_LED_MAP[@]} -eq 0 ]]; then
        load_disk_mapping
    fi
    
    # 遍历所有映射的硬盘
    for disk_device in "${!DISK_LED_MAP[@]}"; do
        local led_name="${DISK_LED_MAP[$disk_device]}"
        
        if [[ -z "$led_name" || "$led_name" == "none" ]]; then
            continue
        fi
        
        # 获取硬盘状态
        local disk_status
        disk_status=$(get_disk_status "$disk_device")
        
        # 检查状态是否变化
        local cached_status="${DISK_STATUS_CACHE[$disk_device]:-}"
        if [[ "$disk_status" == "$cached_status" && "$disk_status" != "not_found" ]]; then
            continue
        fi
        
        # 更新状态缓存
        DISK_STATUS_CACHE["$disk_device"]="$disk_status"
        
        # 根据状态设置LED
        local color brightness
        case "$disk_status" in
            "healthy")
                color="$DISK_COLOR_HEALTHY"
                brightness="$DEFAULT_BRIGHTNESS"
                ;;
            "standby")
                color="$DISK_COLOR_STANDBY"
                brightness="$LOW_BRIGHTNESS"
                ;;
            "unhealthy")
                color="$DISK_COLOR_UNHEALTHY"
                brightness="$DEFAULT_BRIGHTNESS"
                ;;
            "not_found")
                color="$DISK_COLOR_NO_DISK"
                brightness="0"
                ;;
            *)
                color="$DISK_COLOR_NO_DISK"
                brightness="0"
                ;;
        esac
        
        if set_led_status "$led_name" "$color" "$brightness"; then
            ((updated_count++))
            log_message "DEBUG" "更新硬盘LED: $disk_device -> $led_name ($disk_status)"
        fi
    done
    
    if [[ $updated_count -gt 0 ]]; then
        log_message "DEBUG" "更新了 $updated_count 个硬盘LED"
    fi
}

# 主循环
main_loop() {
    log_message "INFO" "守护进程主循环启动"
    
    local last_network_update=0
    local last_system_update=0
    local loop_count=0
    
    while [[ "$DAEMON_RUNNING" == "true" ]]; do
        local current_time=$(date +%s)
        ((loop_count++))
        
        # 更新硬盘LED
        update_disk_leds
        
        # 定期更新系统LED
        if [[ $((current_time - last_system_update)) -ge $SYSTEM_LED_UPDATE_INTERVAL ]]; then
            update_power_led
            last_system_update=$current_time
        fi
        
        # 定期更新网络LED
        if [[ $((current_time - last_network_update)) -ge $NETWORK_CHECK_INTERVAL ]]; then
            update_network_led
            last_network_update=$current_time
        fi
        
        # 定期记录状态
        if [[ $((loop_count % 20)) -eq 0 ]]; then
            log_message "INFO" "运行正常 - 映射硬盘: ${#DISK_LED_MAP[@]}个, 循环: $loop_count"
        fi
        
        sleep "$DISK_CHECK_INTERVAL"
    done
    
    log_message "INFO" "守护进程主循环结束"
}

# 守护进程启动
_daemon_process() {
    log_message "INFO" "守护进程启动 (v$VERSION)"
    
    # 写入PID
    echo $$ > "$PID_FILE"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    
    # 初始化
    check_root
    check_led_cli || exit 1
    load_config
    load_disk_mapping
    
    # 初始化LED
    update_power_led
    update_network_led
    
    # 启动主循环
    main_loop
    
    # 清理
    rm -f "$PID_FILE"
    log_message "INFO" "守护进程结束"
}

# 服务管理
case "${1:-}" in
    _daemon_process)
        _daemon_process
        ;;
    start)
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo "服务已在运行"
                exit 0
            fi
        fi
        nohup "$0" _daemon_process </dev/null >/dev/null 2>&1 &
        echo "服务已启动"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid"
                sleep 2
                if kill -0 "$pid" 2>/dev/null; then
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
        ;;
    status)
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo "服务正在运行，PID: $pid"
                exit 0
            else
                echo "服务未运行"
                rm -f "$PID_FILE"
                exit 1
            fi
        else
            echo "服务未运行"
            exit 1
        fi
        ;;
    *)
        echo "用法: $0 {start|stop|status|_daemon_process}"
        exit 1
        ;;
esac
