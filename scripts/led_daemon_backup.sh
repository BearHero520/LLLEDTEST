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

# 获取硬盘状态 (使用hdparm)
get_disk_status() {
    local disk="$1"
    local status="unknown"
    
    # 检查硬盘是否存在
    if [[ ! -b "$disk" ]]; then
        echo "not_found"
        return 1
    fi
    
    # 使用hdparm检查硬盘状态
    local hdparm_output
    hdparm_output=$(sudo hdparm -C "$disk" 2>&1)
    local hdparm_exit_code=$?
    
    if [[ $hdparm_exit_code -ne 0 ]]; then
        # hdparm失败，可能是设备不存在或权限问题
        if [[ "$hdparm_output" =~ "No such file or directory" ]]; then
            echo "not_found"
            return 1
        else
            echo "error"
            return 1
        fi
    fi
    
    # 解析hdparm输出
    if [[ "$hdparm_output" =~ "drive state is:"[[:space:]]*([^[:space:]]+) ]]; then
        local drive_state="${BASH_REMATCH[1]}"
        case "$drive_state" in
            "active/idle"|"active"|"idle")
                echo "active"
                ;;
            "standby"|"sleeping")
                echo "standby"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
    
    return 0
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
                DISK_LEDS+=("$test_led")
                log_message "探测到LED: $test_led"
            fi
        done
        
        if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
            log_message "无法探测到任何LED"
        else
            log_message "探测到 ${#DISK_LEDS[@]} 个LED: ${DISK_LEDS[*]}"
        fi
        return 0
    fi
    
    # 重置LED数组
    DISK_LEDS=()
    
    # 解析LED状态，提取可用的disk LED
    while read -r line; do
        if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
                DISK_LEDS+=("$led_name")
                log_message "检测到硬盘LED: $led_name"
            fi
        fi
    done <<< "$led_status"
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        log_message "未从状态输出中检测到硬盘LED，尝试探测LED"
        
        # 尝试探测disk1到disk16 (支持更多LED)
        for i in {1..16}; do
            local test_led="disk$i"
            if "$UGREEN_CLI" "$test_led" -status >/dev/null 2>&1; then
                DISK_LEDS+=("$test_led")
                log_message "探测到LED: $test_led"
            fi
        done
        
        if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
            log_message "无法探测到任何硬盘LED"
        else
            log_message "通过探测发现 ${#DISK_LEDS[@]} 个LED: ${DISK_LEDS[*]}"
        fi
    fi
    
    log_message "可用硬盘LED: ${DISK_LEDS[*]}"
    return 0
}

# HCTL硬盘映射检测
detect_disk_mapping_hctl() {
    log_message "使用HCTL方式检测硬盘映射..."
    
    # 获取所有存储设备的HCTL信息
    local hctl_info
    hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>&1)
    local lsblk_exit_code=$?
    
    log_message "lsblk命令退出码: $lsblk_exit_code"
    
    if [[ $lsblk_exit_code -ne 0 || -z "$hctl_info" ]]; then
        log_message "lsblk命令失败或无输出，尝试备用检测方法"
        log_message "lsblk输出: $hctl_info"
        
        # 备用方法：直接检测/dev/sd*设备
        DISKS=()
        DISK_LED_MAP=()
        DISK_INFO=()
        DISK_HCTL_MAP=()
        
        local disk_count=0
        for disk in /dev/sd[a-z]; do
            if [[ -b "$disk" ]]; then
                DISKS+=("$disk")
                local led_number=$((disk_count + 1))
                local target_led="disk${led_number}"
                
                # 检查这个LED是否在可用LED列表中
                local led_available=false
                for available_led in "${DISK_LEDS[@]}"; do
                    if [[ "$available_led" == "$target_led" ]]; then
                        led_available=true
                        break
                    fi
                done
                
                if [[ "$led_available" == "true" ]]; then
                    DISK_LED_MAP["$disk"]="$target_led"
                    log_message "备用映射: $disk -> $target_led"
                else
                    DISK_LED_MAP["$disk"]="none"
                    log_message "备用映射: $disk -> 无可用LED"
                fi
                
                DISK_HCTL_MAP["$disk"]="备用:$disk_count:0:0"
                DISK_INFO["$disk"]="Unknown Disk $(basename "$disk")"
                
                ((disk_count++))
            fi
        done
        
        if [[ ${#DISKS[@]} -eq 0 ]]; then
            log_message "警告: 未检测到任何硬盘设备"
            return 0  # 不返回错误，允许服务继续运行
        fi
        
        log_message "备用检测完成，检测到 ${#DISKS[@]} 个硬盘"
        return 0
    fi
    
    # 重置全局变量
    DISKS=()
    DISK_LED_MAP=()
    DISK_INFO=()
    DISK_HCTL_MAP=()
    
    local successful_mappings=0
    
    # 使用临时文件处理数据
    local temp_file="/tmp/hctl_mapping_$$"
    echo "$hctl_info" > "$temp_file"
    
    while IFS= read -r line; do
        # 跳过标题行和空行
        if [[ "$line" =~ ^NAME ]] || [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
            continue
        fi
        
        # 解析行内容
        local name hctl serial model size
        name=$(echo "$line" | awk '{print $1}')
        hctl=$(echo "$line" | awk '{print $2}')
        serial=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{print $4}')
        size=$(echo "$line" | awk '{print $5}')
        
        # 检查是否是有效的存储设备
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
            
            log_message "处理设备: /dev/$name (HCTL: $hctl)"
            
            # 提取HCTL host值并映射到LED槽位
            local hctl_host=$(echo "$hctl" | cut -d: -f1)
            local led_number
            
            case "$hctl_host" in
                "0") led_number=1 ;;
                "1") led_number=2 ;;
                "2") led_number=3 ;;
                "3") led_number=4 ;;
                "4") led_number=5 ;;
                "5") led_number=6 ;;
                "6") led_number=7 ;;
                "7") led_number=8 ;;
                *) led_number=$((hctl_host + 1)) ;;
            esac
            
            local target_led="disk${led_number}"
            
            # 检查目标LED是否在可用LED列表中
            local led_available=false
            for available_led in "${DISK_LEDS[@]}"; do
                if [[ "$available_led" == "$target_led" ]]; then
                    led_available=true
                    break
                fi
            done
            
            if [[ "$led_available" == "true" ]]; then
                DISK_LED_MAP["/dev/$name"]="$target_led"
                DISK_HCTL_MAP["/dev/$name"]="$hctl"
                DISK_INFO["/dev/$name"]="$model $size (SN: $serial)"
                
                log_message "映射成功: /dev/$name -> $target_led (HCTL: $hctl)"
                ((successful_mappings++))
            else
                DISK_LED_MAP["/dev/$name"]="none"
                DISK_HCTL_MAP["/dev/$name"]="$hctl"
                DISK_INFO["/dev/$name"]="$model $size (SN: $serial)"
                
                log_message "映射失败: /dev/$name -> 无可用LED (需要: $target_led)"
            fi
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    log_message "HCTL映射完成，成功映射 $successful_mappings 个设备"
    return 0
}

# 检测硬盘活动状态
check_disk_activity() {
    local device="$1"
    
    # 移除/dev/前缀
    device=$(basename "$device")
    
    # 读取磁盘统计信息 (读写扇区数)
    if [[ -f "/proc/diskstats" ]]; then
        # 使用全局缓存来避免重复sleep
        local current_time=$(date +%s)
        local cache_key="activity_${device}"
        
        # 如果有缓存且时间差小于5秒，直接使用缓存
        if [[ -n "${ACTIVITY_CACHE[$cache_key]}" ]]; then
            local cached_time="${ACTIVITY_CACHE[${cache_key}_time]}"
            if [[ $((current_time - cached_time)) -lt 5 ]]; then
                echo "${ACTIVITY_CACHE[$cache_key]}"
                return
            fi
        fi
        
        # 读取当前和之前的统计信息
        local stats_current=$(grep " $device " /proc/diskstats | awk '{print $6+$10}')
        local stats_previous="${ACTIVITY_CACHE[${cache_key}_stats]}"
        
        local activity_status
        if [[ -n "$stats_previous" && "$stats_current" -gt "$stats_previous" ]]; then
            activity_status="ACTIVE"
        else
            activity_status="IDLE"
        fi
        
        # 更新缓存
        ACTIVITY_CACHE[$cache_key]="$activity_status"
        ACTIVITY_CACHE["${cache_key}_time"]="$current_time"
        ACTIVITY_CACHE["${cache_key}_stats"]="$stats_current"
        
        echo "$activity_status"
    else
        echo "UNKNOWN"
    fi
}

# 检测硬盘是否休眠
check_disk_sleep() {
    local device="$1"
    
    # 移除/dev/前缀
    device=$(basename "$device")
    
    # 方法1: 使用smartctl检查电源状态
    if command -v smartctl >/dev/null 2>&1; then
        local power_mode=$(smartctl -i -n standby "/dev/$device" 2>/dev/null | grep -i "power mode" | awk '{print $NF}')
        case "${power_mode^^}" in
            "STANDBY"|"SLEEP"|"IDLE")
                echo "SLEEPING"
                return
                ;;
        esac
    fi
    
    # 方法2: 检查设备是否响应
    if ! smartctl -i "/dev/$device" >/dev/null 2>&1; then
        echo "SLEEPING"
        return
    fi
    
    echo "AWAKE"
}

# 设置硬盘LED根据活动状态
set_disk_led_by_activity() {
    local device="$1"
    local led_name="${DISK_LED_MAP[$device]}"
    
    if [[ "$led_name" == "none" || -z "$led_name" ]]; then
        log_message "跳过设备 $device: 无对应LED"
        return
    fi
    
    log_message "处理设备 $device -> LED $led_name"
    
    # 检查设备是否仍然存在
    if [[ ! -b "$device" ]]; then
        # 离线状态：彻底关闭LED
        log_message "设备 $device 离线，关闭LED $led_name"
        "$UGREEN_CLI" "$led_name" -off >/dev/null 2>&1
        # 双重确保LED关闭
        "$UGREEN_CLI" "$led_name" -color 0 0 0 -off -brightness 0 >/dev/null 2>&1
        return
    fi
    
    # 检查休眠状态
    local sleep_status=$(check_disk_sleep "$device")
    log_message "设备 $device 休眠状态: $sleep_status"
    
    if [[ "$sleep_status" == "SLEEPING" ]]; then
        # 休眠状态 - 关闭LED
        log_message "设备 $device 休眠，关闭LED $led_name"
        "$UGREEN_CLI" "$led_name" -off >/dev/null 2>&1
        return
    fi
    
    # 检查活动状态
    local activity=$(check_disk_activity "$device")
    log_message "设备 $device 活动状态: $activity"
    
    # 检查SMART健康状态
    local health="GOOD"
    if command -v smartctl >/dev/null 2>&1; then
        local device_basename=$(basename "$device")
        local smart_health=$(smartctl -H "/dev/$device_basename" 2>/dev/null | grep -E "(SMART overall-health|SMART Health Status)" | awk '{print $NF}')
        case "${smart_health^^}" in
            "FAILED"|"FAILING") health="BAD" ;;
            "PASSED"|"OK") health="GOOD" ;;
            *) health="UNKNOWN" ;;
        esac
    fi
    log_message "设备 $device 健康状态: $health"
    
    # 根据活动状态和健康状态设置LED
    case "$health" in
        "GOOD")
            case "$activity" in
                "ACTIVE")
                    # 活动状态：白色，中等亮度
                    log_message "设置 $led_name 为活动状态 (白色，亮度128)"
                    "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness 128 >/dev/null 2>&1
                    ;;
                "IDLE")
                    # 空闲状态：淡白色，低亮度
                    log_message "设置 $led_name 为空闲状态 (白色，亮度32)"
                    "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness 32 >/dev/null 2>&1
                    ;;
                *)
                    # 状态未知 - 淡白色，低亮度
                    log_message "设置 $led_name 为未知状态 (白色，亮度32)"
                    "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness 32 >/dev/null 2>&1
                    ;;
            esac
            ;;
        "BAD")
            case "$activity" in
                "ACTIVE")
                    # 错误状态：红色闪烁
                    log_message "设置 $led_name 为错误活动状态 (红色闪烁)"
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -blink 500 500 -brightness 255 >/dev/null 2>&1
                    ;;
                *)
                    # 错误状态：红色闪烁
                    log_message "设置 $led_name 为错误状态 (红色闪烁)"
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -blink 500 500 -brightness 255 >/dev/null 2>&1
                    ;;
            esac
            ;;
        *)
            # 状态未知 - 淡白色，低亮度
            log_message "设置 $led_name 为健康未知状态 (白色，亮度32)"
            "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness 32 >/dev/null 2>&1
            ;;
    esac
}

# 关闭未使用的LED
turn_off_unused_leds() {
    log_message "关闭未使用的LED..."
    
    # 获取所有已映射的LED
    local used_leds=()
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        if [[ -n "$led_name" && "$led_name" != "none" ]]; then
            used_leds+=("$led_name")
        fi
    done
    
    # 关闭未使用的硬盘LED
    for led in "${DISK_LEDS[@]}"; do
        local is_used=false
        for used_led in "${used_leds[@]}"; do
            if [[ "$led" == "$used_led" ]]; then
                is_used=true
                break
            fi
        done
        
        if [[ "$is_used" == "false" ]]; then
            log_message "关闭未使用的LED: $led"
            "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
            "$UGREEN_CLI" "$led" -color 0 0 0 -off -brightness 0 >/dev/null 2>&1
        fi
    done
}

# 后台监控函数
background_monitor() {
    local scan_interval=${1:-30}
    
    log_message "启动UGREEN LED监控服务 (基于smart_disk_activity.sh机制)"
    log_message "扫描间隔设置为: ${scan_interval}秒"
    
    # 如果不是从_background模式调用，记录PID
    if [[ "$1" != "_from_systemd" ]]; then
        echo $$ > "$PID_FILE"
    fi
    
    # 检测LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "错误: 未找到LED控制程序 $UGREEN_CLI"
        log_message "服务将以受限模式运行（无LED控制）"
    fi
    
    # 初次检测LED和硬盘 - 使用容错模式
    log_message "开始初始化检测..."
    
    if ! detect_available_leds; then
        log_message "LED检测失败，服务将继续以受限模式运行"
    fi
    
    if ! detect_disk_mapping_hctl; then
        log_message "硬盘映射检测失败，服务将继续以受限模式运行"
    fi
    
    log_message "初始化完成 - LED数量: ${#DISK_LEDS[@]}, 硬盘数量: ${#DISKS[@]}"
    
    # 如果没有检测到任何硬盘，创建最小配置继续运行
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        log_message "未检测到硬盘，创建最小监控配置"
        # 不退出，而是以最小配置运行
    fi
    
    local last_disk_count=${#DISKS[@]}
    local scan_counter=0
    
    # 主监控循环
    while true; do
        # 每隔一定时间重新扫描硬盘 (热插拔检测)
        if (( scan_counter % 6 == 0 )); then  # 每6个周期重新扫描
            log_message "重新扫描硬盘设备..."
            
            # 重新检测LED (防止系统变化)
            detect_available_leds >/dev/null 2>&1
            
            # 重新检测硬盘
            if detect_disk_mapping_hctl >/dev/null 2>&1; then
                log_message "硬盘重新检测成功"
                
                # 检查硬盘数量变化
                if [[ ${#DISKS[@]} -ne $last_disk_count ]]; then
                    log_message "硬盘数量变化: $last_disk_count -> ${#DISKS[@]}"
                    last_disk_count=${#DISKS[@]}
                fi
            else
                log_message "硬盘检测失败，继续使用现有配置"
            fi
        fi
        
        # 为每个硬盘设置LED状态
        log_message "开始LED状态更新 - 扫描周期 $scan_counter"
        for disk in "${DISKS[@]}"; do
            set_disk_led_by_activity "$disk"
        done
        
        # 关闭未使用的LED（每10个周期执行一次）
        if (( scan_counter % 10 == 0 )); then
            turn_off_unused_leds
        fi
        
        log_message "LED状态更新完成 - 等待 ${scan_interval}秒"
        
        ((scan_counter++))
        sleep "$scan_interval"
    done
}

# 启动服务
start_service() {
    local scan_interval=${1:-30}
    
    # 检查是否已有进程运行
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local existing_pid=$(cat "$PID_FILE")
        log_message "检测到已运行的服务进程: $existing_pid"
        
        # 检查是否从systemd启动
        if [[ "$PPID" == "1" ]] || [[ -n "$INVOCATION_ID" ]]; then
            # 从systemd启动：停止现有进程并重新启动
            log_message "从systemd启动，停止现有进程并重新启动"
            echo "检测到现有进程，正在重启服务..."
            
            # 停止现有进程
            if kill "$existing_pid" 2>/dev/null; then
                sleep 2
                log_message "已停止现有进程: $existing_pid"
            fi
            
            # 清理PID文件
            rm -f "$PID_FILE"
        else
            # 手动启动：报告已运行状态
            echo "服务已在运行 (PID: $existing_pid)"
            return 1
        fi
    fi
    
    log_message "启动UGREEN LED监控服务 (扫描间隔: ${scan_interval}秒)..."
    
    # 后台运行监控
    background_monitor "$scan_interval" &
    local pid=$!
    
    echo "$pid" > "$PID_FILE"
    log_message "服务已启动，PID: $pid"
    echo "✓ 服务已启动"
}

# 停止服务
stop_service() {
    local stopped=false
    
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        log_message "尝试停止服务进程: $pid"
        
        if kill "$pid" 2>/dev/null; then
            log_message "发送停止信号到进程: $pid"
            
            # 等待进程停止
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
                sleep 1
                ((count++))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log_message "强制停止进程: $pid"
                kill -9 "$pid" 2>/dev/null || true
            fi
            
            log_message "服务已停止"
            echo "✓ 服务已停止"
            stopped=true
        else
            log_message "进程 $pid 不存在或已停止"
            echo "✓ 进程不存在或已停止"
            stopped=true
        fi
        
        rm -f "$PID_FILE"
    else
        echo "服务未运行"
        log_message "服务未运行 (无PID文件)"
    fi
    
    # 额外清理：查找并停止可能的孤儿进程
    local orphan_pids=$(pgrep -f "led_daemon.sh.*background" 2>/dev/null || true)
    if [[ -n "$orphan_pids" ]]; then
        log_message "发现孤儿进程，正在清理: $orphan_pids"
        echo "$orphan_pids" | xargs kill 2>/dev/null || true
    fi
}

# 查看状态
status_service() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local pid=$(cat "$PID_FILE")
        echo "✓ 服务正在运行 (PID: $pid)"
        echo "日志文件: $LOG_FILE"
        if [[ -f "$LOG_FILE" ]]; then
            echo "最近日志:"
            tail -5 "$LOG_FILE"
        fi
        return 0
    else
        echo "✗ 服务未运行"
        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
        return 1
    fi
}

# 主函数
case "$1" in
    start)
        shift
        start_service "$@"
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        sleep 2
        shift
        start_service "$@"
        ;;
    status)
        status_service
        ;;
    logs)
        if [[ -f "$LOG_FILE" ]]; then
            tail -f "$LOG_FILE"
        else
            echo "日志文件不存在: $LOG_FILE"
        fi
        ;;
    _background)
        # systemd使用，直接运行后台监控
        scan_interval=${2:-30}
        log_message "从systemd启动后台监控服务 (扫描间隔: ${scan_interval}秒)"
        
        # 记录PID
        echo $$ > "$PID_FILE"
        
        # 直接运行监控循环（不fork）
        background_monitor "$scan_interval"
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs} [扫描间隔秒数]"
        echo "扫描间隔选项: 2(快速) 30(标准) 60(节能)"
        exit 1
        ;;
esac
