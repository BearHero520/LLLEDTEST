#!/bin/bash

# 修复版LED守护进程 - 支持完整的参数

# 服务配置
SERVICE_NAME="ugreen-led-monitor"
LLLED_VERSION="3.0.0"

# 路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="/var/log/llled"
PID_FILE="/var/run/${SERVICE_NAME}.pid"
LOG_FILE="$LOG_DIR/${SERVICE_NAME}.log"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
declare -A DISK_LED_MAP
declare -A DISK_STATUS_CACHE
AVAILABLE_LEDS=()
DAEMON_RUNNING=true
CHECK_INTERVAL=5

# 创建必要目录
mkdir -p "$LOG_DIR"

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# 信号处理
handle_signal() {
    local signal="$1"
    log_message "INFO" "收到信号: $signal，开始优雅退出"
    DAEMON_RUNNING=false
    exit 0
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "需要root权限运行后台服务"
        exit 1
    fi
}

# 检查LED控制程序
check_led_cli() {
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "ERROR" "LED控制程序不存在: $UGREEN_CLI"
        return 1
    fi
    
    if ! timeout 5 "$UGREEN_CLI" power -status >/dev/null 2>&1; then
        log_message "ERROR" "LED控制程序测试失败"
        return 1
    fi
    
    return 0
}

# 检测可用LED (使用详细版本)
# detect_available_leds 函数在下方实现，此处删除重复定义

# 主循环
main_loop() {
    log_message "INFO" "主监控循环启动"
    local loop_count=0
    local max_loops=720  # 1小时后自动重启
    
    while [[ "$DAEMON_RUNNING" == "true" && $loop_count -lt $max_loops ]]; do
        # 简单的LED状态更新
        for led in "${AVAILABLE_LEDS[@]}"; do
            if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                # 硬盘LED简单显示
                timeout 2 "$UGREEN_CLI" "$led" -color 128 128 128 -brightness 32 >/dev/null 2>&1 || true
            fi
        done
        
        ((loop_count++))
        sleep "$CHECK_INTERVAL"
    done
    
    log_message "INFO" "主循环结束"
}

# 启动守护进程（后台模式）
start_daemon() {
    log_message "INFO" "启动后台守护进程..."
    
    # 检查是否已经运行
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_message "WARN" "服务已经在运行，PID: $existing_pid"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # 后台启动
    nohup "$0" "_daemon_process" </dev/null >/dev/null 2>&1 &
    local daemon_pid=$!
    
    # 等待一下确保启动
    sleep 2
    
    if kill -0 "$daemon_pid" 2>/dev/null; then
        log_message "INFO" "后台服务启动成功，PID: $daemon_pid"
        return 0
    else
        log_message "ERROR" "后台服务启动失败"
        return 1
    fi
}

# 直接启动守护进程
_start_daemon_direct() {
    log_message "INFO" "守护进程直接启动"
    
    # 写入PID文件
    echo $$ > "$PID_FILE"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    
    # 基础检查
    check_root
    
    # 检查LED控制程序
    if ! check_led_cli; then
        log_message "ERROR" "LED控制程序检查失败"
        exit 1
    fi
    
    # 检测LED
    if ! detect_available_leds; then
        log_message "ERROR" "LED检测失败"
        exit 1
    fi
    
    # 启动主循环
    main_loop
    
    # 清理
    rm -f "$PID_FILE"
    log_message "INFO" "守护进程结束"
}

# 停止服务
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "停止守护进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null
            
            # 等待进程退出
            local count=0
            while [[ $count -lt 10 ]] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                ((count++))
            done
            
            # 如果还没退出，强制kill
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
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

# 检查状态
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
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



# 检查LED控制程序
check_led_cli() {
    log_message "DEBUG" "检查LED控制程序: $UGREEN_CLI"
    
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "ERROR" "LED控制程序不存在或不可执行: $UGREEN_CLI"
        return 1
    fi
    log_message "DEBUG" "LED控制程序文件存在且可执行"
    
    # 测试LED控制程序 - 使用disk1进行测试，因为all可能不被支持
    log_message "DEBUG" "测试LED控制程序 - 尝试disk1 -status"
    if ! timeout 5 "$UGREEN_CLI" disk1 -status >/dev/null 2>&1; then
        log_message "WARN" "LED控制程序测试失败，尝试使用power LED测试..."
        # 如果disk1失败，尝试power LED
        log_message "DEBUG" "测试LED控制程序 - 尝试power -status"
        if ! timeout 5 "$UGREEN_CLI" power -status >/dev/null 2>&1; then
            log_message "ERROR" "LED控制程序测试完全失败，可能设备不兼容"
            return 1
        fi
        log_message "DEBUG" "power LED测试成功"
    else
        log_message "DEBUG" "disk1 LED测试成功"
    fi
    
    log_message "INFO" "LED控制程序检查通过"
    return 0
}

# 检测可用LED
detect_available_leds() {
    log_message "INFO" "检测可用LED..."
    AVAILABLE_LEDS=()
    
    # 尝试检测所有可能的LED，添加超时保护
    log_message "DEBUG" "检测disk LED (1-16)..."
    for i in {1..16}; do
        local led_name="disk$i"
        log_message "DEBUG" "测试LED: $led_name"
        
        # 添加3秒超时保护，防止单个LED检测卡住
        if timeout 3 "$UGREEN_CLI" "$led_name" -status >/dev/null 2>&1; then
            AVAILABLE_LEDS+=("$led_name")
            log_message "DEBUG" "检测到LED: $led_name"
        else
            log_message "DEBUG" "LED $led_name 不可用或超时"
        fi
    done
    
    # 检测电源和网络LED
    log_message "DEBUG" "检测系统LED (power, netdev)..."
    for led in "power" "netdev"; do
        log_message "DEBUG" "测试LED: $led"
        
        # 尝试多种方法检测LED
        local led_detected=false
        
        # 方法1：status检查
        if timeout 3 "$UGREEN_CLI" "$led" -status >/dev/null 2>&1; then
            led_detected=true
            log_message "DEBUG" "通过status检测到LED: $led"
        # 方法2：尝试简单的off命令
        elif timeout 3 "$UGREEN_CLI" "$led" -off >/dev/null 2>&1; then
            led_detected=true
            log_message "DEBUG" "通过off命令检测到LED: $led"
        # 方法3：尝试颜色设置
        elif timeout 3 "$UGREEN_CLI" "$led" -color "0 0 0" >/dev/null 2>&1; then
            led_detected=true
            log_message "DEBUG" "通过color命令检测到LED: $led"
        fi
        
        if [[ "$led_detected" == "true" ]]; then
            AVAILABLE_LEDS+=("$led")
            log_message "INFO" "成功检测到系统LED: $led"
        else
            log_message "WARN" "系统LED $led 检测失败，但将保留在功能中"
            # 即使检测失败，也加入列表，因为某些设备可能在检测时有问题但实际可控制
            AVAILABLE_LEDS+=("$led")
        fi
    done
    
    log_message "INFO" "检测到 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}"
    
    # 确保至少检测到一些LED，否则可能有问题
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        log_message "WARN" "未检测到任何可用LED，可能存在问题"
        return 1
    fi
    
    return 0
}

# 检查网络状态
check_network_status() {
    # 从配置文件读取网络测试主机，默认使用Google DNS
    local test_host="${NETWORK_TEST_HOST:-8.8.8.8}"
    local timeout="${NETWORK_TIMEOUT:-3}"
    
    # 尝试ping测试
    if ping -c 1 -W "$timeout" "$test_host" >/dev/null 2>&1; then
        echo "connected"
        return 0
    fi
    
    # 如果第一个主机失败，尝试备用主机
    local backup_hosts=("1.1.1.1" "114.114.114.114" "8.8.4.4")
    for host in "${backup_hosts[@]}"; do
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            echo "connected"
            return 0
        fi
    done
    
    # 检查网络接口状态
    if ip route get "$test_host" >/dev/null 2>&1; then
        echo "no_internet"  # 有路由但无法访问外网
        return 1
    else
        echo "disconnected"  # 完全断网
        return 2
    fi
}

# 更新网络LED状态
update_network_led() {
    local network_status
    network_status=$(check_network_status)
    local status_result=$?
    
    log_message "DEBUG" "网络状态检测结果: $network_status"
    
    # 根据网络状态设置LED颜色和亮度
    local color brightness
    case "$network_status" in
        "connected")
            color="0 0 255"      # 蓝色
            brightness="64"
            log_message "DEBUG" "网络状态: 已连接 -> 蓝色LED"
            ;;
        "no_internet")
            color="255 165 0"    # 橙色
            brightness="64"
            log_message "WARN" "网络状态: 无法访问外网 -> 橙色LED"
            ;;
        "disconnected")
            color="255 0 0"      # 红色
            brightness="64"
            log_message "WARN" "网络状态: 断开连接 -> 红色LED"
            ;;
        *)
            color="off"
            brightness="0"
            log_message "ERROR" "网络状态: 未知 -> 关闭LED"
            ;;
    esac
    
    # 尝试使用set_led_status（检查可用性）
    if [[ " ${AVAILABLE_LEDS[*]} " =~ " netdev " ]]; then
        if set_led_status "netdev" "$color" "$brightness"; then
            return 0
        fi
    fi
    
    # 如果上面失败，直接尝试控制LED（绕过可用性检查）
    log_message "DEBUG" "直接控制网络LED（绕过可用性检查）"
    if [[ "$color" == "off" ]]; then
        if timeout 5 "$UGREEN_CLI" netdev -off >/dev/null 2>&1; then
            log_message "DEBUG" "直接关闭网络LED成功"
            return 0
        fi
    else
        if timeout 5 "$UGREEN_CLI" netdev -color $color -brightness "$brightness" -on >/dev/null 2>&1; then
            log_message "DEBUG" "直接控制网络LED成功: $color (亮度: $brightness)"
            return 0
        fi
    fi
    
    log_message "WARN" "网络LED控制失败"
    return 1
}

# 更新电源LED状态
update_power_led() {
    # 电源LED保持淡白色常亮表示系统运行正常
    log_message "DEBUG" "更新电源LED状态 -> 淡白色常亮"
    
    # 尝试使用set_led_status（检查可用性）
    if [[ " ${AVAILABLE_LEDS[*]} " =~ " power " ]]; then
        if set_led_status "power" "128 128 128" "64"; then
            return 0
        fi
    fi
    
    # 如果上面失败，直接尝试控制LED（绕过可用性检查）
    log_message "DEBUG" "直接控制电源LED（绕过可用性检查）"
    if timeout 5 "$UGREEN_CLI" power -color "128 128 128" -brightness 64 -on >/dev/null 2>&1; then
        log_message "DEBUG" "直接控制电源LED成功"
        return 0
    else
        log_message "WARN" "电源LED控制失败"
        return 1
    fi
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
    if [[ "$hdparm_output" =~ drive\ state\ is:[[:space:]]*([^[:space:]]+) ]]; then
        local drive_state="${BASH_REMATCH[1]}"
        log_message "DEBUG" "硬盘 $disk hdparm输出: $hdparm_output"
        log_message "DEBUG" "解析到的驱动器状态: '$drive_state'"
        
        case "$drive_state" in
            "active/idle"|"active"|"idle")
                log_message "DEBUG" "硬盘 $disk 状态: 活跃"
                echo "active"
                return 0
                ;;
            "standby"|"sleeping")
                log_message "DEBUG" "硬盘 $disk 状态: 休眠"
                echo "standby"
                return 0
                ;;
            *)
                log_message "DEBUG" "硬盘 $disk 状态: 未知 ($drive_state)"
                echo "unknown"
                return 0
                ;;
        esac
    else
        # hdparm返回成功但无法解析状态，记录完整输出用于调试
        log_message "WARN" "无法解析硬盘 $disk 的hdparm输出: $hdparm_output"
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

# 重新获取HCTL映射 (生成新的硬盘-LED配置)
refresh_hctl_mapping() {
    log_message "INFO" "重新生成HCTL硬盘映射配置..."
    
    # 调用智能硬盘状态脚本来生成HCTL配置
    local hctl_script="$SCRIPT_DIR/scripts/smart_disk_activity_hctl.sh"
    if [[ -x "$hctl_script" ]]; then
        log_message "INFO" "调用HCTL检测脚本生成配置: $hctl_script"
        
        # 执行脚本来生成HCTL映射配置（添加30秒超时保护）
        if timeout 30 "$hctl_script" >/dev/null 2>&1; then
            log_message "INFO" "HCTL配置生成成功"
            
            # 重新加载生成的映射配置
            if load_hctl_mapping; then
                LAST_HCTL_UPDATE=$(date +%s)
                log_message "INFO" "HCTL映射配置重新加载完成"
                return 0
            else
                log_message "ERROR" "重新加载HCTL映射配置失败"
                return 1
            fi
        else
            log_message "ERROR" "HCTL配置生成失败或超时"
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
        if "$UGREEN_CLI" "$led" -color $color -brightness "$brightness" -on >/dev/null 2>&1; then
            LED_STATUS_CACHE["$led"]="$color|$brightness"
            log_message "DEBUG" "LED $led 设置为 $color (亮度: $brightness)"
        else
            log_message "WARN" "设置LED $led 失败"
            return 1
        fi
    fi
    
    return 0
}

# 更新硬盘LED状态 (基于HCTL配置)
update_disk_leds() {
    local updated_count=0
    local need_remap=false
    
    log_message "DEBUG" "开始更新硬盘LED状态，当前映射数量: ${#DISK_LED_MAP[@]}"
    
    # 如果没有HCTL映射配置，立即生成
    if [[ ${#DISK_LED_MAP[@]} -eq 0 ]]; then
        log_message "INFO" "没有HCTL映射配置，立即生成..."
        refresh_hctl_mapping
        return
    fi
    
    # 收集当前应该使用的LED列表
    local used_leds=()
    
    # 遍历所有HCTL配置中的硬盘
    for disk in "${!DISK_LED_MAP[@]}"; do
        local led="${DISK_LED_MAP[$disk]:-}"
        
        # 跳过无效的LED映射
        if [[ -z "$led" || "$led" == "none" ]]; then
            log_message "DEBUG" "硬盘 $disk 无LED映射，跳过"
            continue
        fi
        
        # 关键步骤：尝试获取HCTL配置中硬盘的当前状态
        local disk_status
        disk_status=$(get_disk_status "$disk")
        local status_result=$?
        
        log_message "DEBUG" "HCTL配置硬盘 $disk -> LED $led: status=$disk_status, result=$status_result"
        
        # 如果无法获取硬盘状态，说明硬盘位置变化或被拔出
        if [[ $status_result -ne 0 ]]; then
            case "$disk_status" in
                "not_found"|"error")
                    log_message "WARN" "HCTL配置中的硬盘 $disk 无法访问 (状态: $disk_status)"
                    log_message "INFO" "硬盘位置可能变化或已拔出，关闭LED $led"
                    
                    # 立即关闭对应LED
                    set_led_status "$led" "off"
                    
                    # 标记需要重新生成HCTL配置
                    need_remap=true
                    ;;
            esac
            continue
        fi
        
        # 记录这个LED正在使用
        used_leds+=("$led")
        
        # 能获取到硬盘状态，检查是否需要更新LED
        local cached_status="${DISK_STATUS_CACHE[$disk]:-}"
        if [[ "$disk_status" == "$cached_status" ]]; then
            log_message "DEBUG" "硬盘 $disk 状态无变化: $disk_status"
            continue
        fi
        
        # 更新状态缓存
        DISK_STATUS_CACHE["$disk"]="$disk_status"
        
        # 根据硬盘状态更新LED（只更新LED，不改变配置）
        case "$disk_status" in
            "active")
                log_message "INFO" "硬盘 $disk 活动状态 -> LED $led 白色高亮"
                set_led_status "$led" "$DISK_COLOR_ACTIVE" "$HIGH_BRIGHTNESS"
                ((updated_count++))
                ;;
            "standby")
                log_message "INFO" "硬盘 $disk 休眠状态 -> LED $led 淡白色"
                set_led_status "$led" "$DISK_COLOR_STANDBY" "$LOW_BRIGHTNESS"
                ((updated_count++))
                ;;
            "unknown")
                log_message "WARN" "硬盘 $disk 状态未知 -> LED $led 关闭"
                set_led_status "$led" "off"
                ((updated_count++))
                ;;
            *)
                log_message "WARN" "硬盘 $disk 未知状态: $disk_status"
                ;;
        esac
    done
    
    # 关闭未使用的硬盘LED
    for led in "${AVAILABLE_LEDS[@]}"; do
        # 只处理硬盘LED
        if [[ "$led" =~ ^disk[0-9]+$ ]]; then
            local led_in_use=false
            for used_led in "${used_leds[@]}"; do
                if [[ "$led" == "$used_led" ]]; then
                    led_in_use=true
                    break
                fi
            done
            
            # 如果这个LED没有被使用，关闭它
            if [[ "$led_in_use" == "false" ]]; then
                local current_status="${LED_STATUS_CACHE[$led]:-}"
                if [[ "$current_status" != "off" ]]; then
                    log_message "INFO" "关闭未使用的硬盘LED: $led"
                    set_led_status "$led" "off"
                    ((updated_count++))
                fi
            fi
        fi
    done
    
    # 如果检测到硬盘位置变化，重新生成HCTL配置
    if [[ "$need_remap" == "true" ]]; then
        log_message "INFO" "检测到硬盘位置变化，重新生成HCTL配置..."
        refresh_hctl_mapping
        return
    fi
    
    log_message "DEBUG" "LED状态更新完成，更新了 $updated_count 个LED"
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

# 主循环 - 严格按照HCTL配置进行监控
main_loop() {
    log_message "INFO" "主监控循环启动，检查间隔: ${CHECK_INTERVAL}秒"
    log_message "INFO" "当前HCTL配置：${#DISK_LED_MAP[@]} 个硬盘映射"
    
    # 记录开始时间用于定期重映射和系统LED更新
    local last_hctl_refresh=$(date +%s)
    local last_system_led_update=0    # 立即更新系统LED
    local hctl_refresh_interval=3600  # 1小时定期刷新HCTL
    local system_led_interval=10      # 10秒更新一次系统LED (更快响应)
    
    while [[ "$DAEMON_RUNNING" == "true" ]]; do
        local current_time=$(date +%s)
        
        log_message "DEBUG" "循环迭代开始，时间: $(date)"
        
        # 核心步骤：严格基于当前HCTL配置更新硬盘LED状态
        # 只检查配置中的硬盘，不扫描新硬盘
        if ! update_disk_leds; then
            log_message "WARN" "硬盘LED更新失败，继续运行"
        fi
        
        # 定期更新系统LED状态（电源和网络）
        if [[ $((current_time - last_system_led_update)) -gt $system_led_interval ]]; then
            log_message "INFO" "定期更新系统LED状态..."
            
            # 显示当前可用LED列表用于调试
            log_message "DEBUG" "当前可用LED列表: ${AVAILABLE_LEDS[*]}"
            
            if ! update_power_led; then
                log_message "WARN" "电源LED更新失败，尝试强制控制"
                timeout 5 "$UGREEN_CLI" power -color "128 128 128" -brightness 64 -on >/dev/null 2>&1
            else
                log_message "DEBUG" "电源LED更新成功"
            fi
            
            if ! update_network_led; then
                log_message "WARN" "网络LED更新失败，尝试强制控制"
                timeout 5 "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 -on >/dev/null 2>&1
            else
                log_message "DEBUG" "网络LED更新成功"
            fi
            
            last_system_led_update=$current_time
        fi
        
        # 定期刷新HCTL配置（处理硬盘热插拔情况）
        if [[ $((current_time - last_hctl_refresh)) -gt $hctl_refresh_interval ]]; then
            log_message "INFO" "定期HCTL配置刷新时间到达，重新生成配置..."
            if refresh_hctl_mapping; then
                log_message "INFO" "定期HCTL配置刷新成功，当前映射数量: ${#DISK_LED_MAP[@]}"
                last_hctl_refresh=$current_time
            else
                log_message "WARN" "定期HCTL配置刷新失败，将在下次继续尝试"
            fi
        fi
        
        # 等待下次检查
        sleep "$CHECK_INTERVAL"
    done
    
    log_message "INFO" "主监控循环结束"
}

# 守护进程启动函数 - 严格的三步初始化流程
start_daemon() {
    local background_mode="${1:-false}"
    
    log_message "INFO" "启动LLLED后台监控服务 v$LLLED_VERSION (后台模式: $background_mode)"
    
    # 检查是否已经运行
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_message "ERROR" "服务已经运行，PID: $old_pid"
            echo "服务已经运行，PID: $old_pid"
            exit 1
        else
            log_message "WARN" "清理过期的PID文件"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 如果是后台模式，启动新进程并退出
    if [[ "$background_mode" == "true" ]]; then
        log_message "INFO" "启动后台守护进程..."
        echo "启动后台守护进程..."
        
        # 启动后台进程
        nohup "$0" "_daemon_process" </dev/null >/dev/null 2>&1 &
        local daemon_pid=$!
        
        # 等待一下确保进程启动
        sleep 2
        
        # 检查进程是否成功启动
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "✓ 后台服务启动成功，PID: $daemon_pid"
            log_message "INFO" "后台服务启动成功，PID: $daemon_pid"
            return 0
        else
            echo "✗ 后台服务启动失败"
            log_message "ERROR" "后台服务启动失败"
            return 1
        fi
    fi
    
    # 直接启动模式（由 _daemon_process 调用）
    _start_daemon_direct
}

# 直接启动守护进程（不fork）
_start_daemon_direct() {
    # 强制启用调试模式用于问题排查
    DEBUG_MODE=true
    
    log_message "INFO" "=== _start_daemon_direct 函数开始执行 ==="
    
    # 写入PID文件
    echo $$ > "$PID_FILE"
    log_message "INFO" "已写入PID文件: $PID_FILE, PID: $$"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    log_message "INFO" "已设置信号处理"
    
    # 基础环境检查
    log_message "INFO" "开始基础环境检查..."
    check_root
    log_message "INFO" "root权限检查通过"
    
    load_configs
    log_message "INFO" "配置文件加载完成"
    
    log_message "INFO" "开始LED控制程序检查..."
    if ! check_led_cli; then
        log_message "ERROR" "LED控制程序检查失败，服务无法启动"
        exit 1
    fi
    log_message "INFO" "LED控制程序检查通过"
    
    log_message "INFO" "开始检测可用LED..."
    if ! detect_available_leds; then
        log_message "ERROR" "LED检测失败"
        exit 1
    fi
    log_message "INFO" "LED检测完成，发现 ${#AVAILABLE_LEDS[@]} 个LED"
    
    # 启动时清理所有硬盘LED状态，确保干净的初始状态
    log_message "INFO" "【初始化】清理所有硬盘LED状态"
    for led in "${AVAILABLE_LEDS[@]}"; do
        if [[ "$led" =~ ^disk[0-9]+$ ]]; then
            set_led_status "$led" "off"
            log_message "DEBUG" "已关闭硬盘LED: $led"
        fi
    done
    
    # 初始化系统LED状态
    log_message "INFO" "【初始化】设置系统LED初始状态"
    
    # 强制立即更新系统LED，不依赖于检测结果
    if [[ " ${AVAILABLE_LEDS[*]} " =~ " power " ]]; then
        log_message "INFO" "初始化电源LED..."
        if ! update_power_led; then
            log_message "WARN" "电源LED初始化失败"
            # 尝试直接设置
            timeout 5 "$UGREEN_CLI" power -color "128 128 128" -brightness 64 -on >/dev/null 2>&1
        fi
    else
        log_message "WARN" "power LED未在可用列表中，尝试直接初始化"
        timeout 5 "$UGREEN_CLI" power -color "128 128 128" -brightness 64 -on >/dev/null 2>&1
    fi
    
    if [[ " ${AVAILABLE_LEDS[*]} " =~ " netdev " ]]; then
        log_message "INFO" "初始化网络LED..."
        if ! update_network_led; then
            log_message "WARN" "网络LED初始化失败"
            # 尝试直接设置为蓝色（假设网络正常）
            timeout 5 "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 -on >/dev/null 2>&1
        fi
    else
        log_message "WARN" "netdev LED未在可用列表中，尝试直接初始化"
        timeout 5 "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 -on >/dev/null 2>&1
    fi
    
    # ===== 三步初始化流程 =====
    
    # 第一步：生成HCTL配置建立硬盘-LED映射关系
    log_message "INFO" "【第一步】生成HCTL配置建立硬盘-LED映射关系"
    if ! refresh_hctl_mapping; then
        log_message "WARN" "HCTL映射生成失败，继续运行仅监控系统LED"
        # 即使HCTL映射失败，也继续运行守护进程，至少可以监控系统LED
    fi
    
    # 验证第一步结果
    if [[ ${#DISK_LED_MAP[@]} -eq 0 ]]; then
        log_message "WARN" "警告：没有检测到任何硬盘映射，服务将持续监控"
    else
        log_message "INFO" "第一步完成，已建立 ${#DISK_LED_MAP[@]} 个硬盘-LED映射："
        for disk in "${!DISK_LED_MAP[@]}"; do
            local led="${DISK_LED_MAP[$disk]}"
            local hctl_info="${DISK_HCTL_MAP[$disk]}"
            log_message "INFO" "  $disk -> LED $led (HCTL: ${hctl_info%%|*})"
        done
    fi
    
    # 第二步：根据HCTL配置设置硬盘LED初始状态
    log_message "INFO" "【第二步】根据HCTL配置设置硬盘LED初始状态"
    update_disk_leds
    log_message "INFO" "第二步完成，硬盘LED初始状态设置完毕"
    
    # 第三步：开始持续监控循环
    log_message "INFO" "【第三步】开始基于HCTL配置的持续监控循环"
    log_message "INFO" "守护进程初始化完成，进入主循环监控模式"
    log_message "INFO" "当前环境状态:"
    log_message "INFO" "  - DAEMON_RUNNING: $DAEMON_RUNNING"
    log_message "INFO" "  - CHECK_INTERVAL: $CHECK_INTERVAL"
    log_message "INFO" "  - 硬盘映射数量: ${#DISK_LED_MAP[@]}"
    log_message "INFO" "  - 可用LED数量: ${#AVAILABLE_LEDS[@]}"
    
    # 启动主循环
    main_loop
    
    # 如果主循环意外退出，记录日志
    log_message "WARN" "主循环意外退出！"
    log_message "INFO" "DAEMON_RUNNING状态: $DAEMON_RUNNING"
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
        start_daemon true
        ;;
    _daemon_process)
        _start_daemon_direct
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
