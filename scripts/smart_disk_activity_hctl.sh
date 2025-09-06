#!/bin/bash

# 智能硬盘活动状态显示脚本 - HCTL版本 v3.0.0
# 根据硬盘活动状态、休眠状态显示不同亮度和效果
# 支持HCTL智能映射、自动更新和多盘位
# 新增: 自动保存HCTL映射到配置文件

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 版本信息
SCRIPT_VERSION="3.0.0"
LAST_UPDATE="2025-09-06"

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
DISKS=()
DISK_LEDS=()
declare -A DISK_LED_MAP
declare -A DISK_INFO
declare -A DISK_HCTL_MAP
declare -A CURRENT_HCTL_MAP

# 参数解析
UPDATE_MAPPING=false
SAVE_CONFIG=false
INTERACTIVE_MODE=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --update-mapping)
            UPDATE_MAPPING=true
            shift
            ;;
        --save-config)
            SAVE_CONFIG=true
            shift
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        --help|-h)
            echo "智能硬盘活动状态检测脚本 v$SCRIPT_VERSION"
            echo "用法: $0 [选项]"
            echo
            echo "选项:"
            echo "  --update-mapping    更新HCTL映射并保存到配置文件"
            echo "  --save-config       保存当前检测结果到配置文件"
            echo "  --interactive       交互式模式"
            echo "  --help, -h          显示帮助信息"
            echo
            echo "配置文件: $HCTL_CONFIG"
            echo "LED配置: $LED_CONFIG"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 检测可用LED
detect_available_leds() {
    echo -e "${CYAN}检测可用LED...${NC}"
    
    local led_status
    led_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    
    if [[ -z "$led_status" ]]; then
        echo -e "${RED}无法检测LED状态，请检查ugreen_leds_cli${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的LED状态:${NC}"
    echo "$led_status"
    
    # 解析LED状态，提取可用的disk LED
    while read -r line; do
        if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
                DISK_LEDS+=("$led_name")
                echo -e "${GREEN}✓ 检测到硬盘LED: $led_name${NC}"
            fi
# 加载配置
load_config() {
    if [[ -f "$LED_CONFIG" ]]; then
        source "$LED_CONFIG" 2>/dev/null || {
            echo -e "${YELLOW}使用默认LED配置${NC}"
            DEFAULT_BRIGHTNESS=64
            LOW_BRIGHTNESS=16
            HIGH_BRIGHTNESS=128
            DISK_COLOR_ACTIVE="255 255 255"    # 硬盘活动 - 白色
            DISK_COLOR_STANDBY="128 128 128"   # 硬盘休眠 - 淡白色
            DISK_COLOR_ERROR="0 0 0"           # 硬盘错误 - 不显示
        }
    fi
}

# 检查脚本权限和依赖
check_dependencies() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限来检测硬盘状态${NC}"
        exit 1
    fi
    
    # 检查LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}LED控制程序不存在: $UGREEN_CLI${NC}"
        exit 1
    fi
    
    # 检查必要的命令
    for cmd in lsblk hdparm; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}缺少必要命令: $cmd${NC}"
            echo "请安装相应软件包"
            exit 1
        fi
    done
}

# 创建配置目录
ensure_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        echo -e "${GREEN}创建配置目录: $CONFIG_DIR${NC}"
    fi
}

# 检测可用LED
detect_available_leds() {
    echo -e "${CYAN}检测可用LED...${NC}"
    
    local led_status
    led_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    
    if [[ -z "$led_status" ]]; then
        echo -e "${YELLOW}无法获取LED状态，尝试探测...${NC}"
        # 探测硬盘LED
        DISK_LEDS=()
        for i in {1..16}; do
            local test_led="disk$i"
            if "$UGREEN_CLI" "$test_led" -status >/dev/null 2>&1; then
                DISK_LEDS+=("$test_led")
                echo -e "${GREEN}✓ 检测到LED: $test_led${NC}"
            fi
        done
    else
        echo -e "${YELLOW}LED状态信息:${NC}"
        echo "$led_status"
        
        # 解析LED状态，提取可用的disk LED
        while read -r line; do
            if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
                local led_name="${BASH_REMATCH[1]}"
                if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
                    DISK_LEDS+=("$led_name")
                    echo -e "${GREEN}✓ 检测到硬盘LED: $led_name${NC}"
                fi
            fi
        done <<< "$led_status"
    fi
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘LED，请检查设备兼容性${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}可用硬盘LED (${#DISK_LEDS[@]}个): ${DISK_LEDS[*]}${NC}"
    return 0
}

# HCTL硬盘映射检测
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射...${NC}"
    echo -e "${BLUE}当前可用硬盘LED: ${DISK_LEDS[*]}${NC}"
    
    # 获取所有存储设备的HCTL信息
    local hctl_info
    hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)
    
    if [[ -z "$hctl_info" ]]; then
        echo -e "${YELLOW}无法获取HCTL信息，可能系统不支持或无存储设备${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的存储设备HCTL信息:${NC}"
    echo "$hctl_info"
    echo
    
    # 重置全局变量
    DISKS=()
    DISK_LED_MAP=()
    DISK_INFO=()
    DISK_HCTL_MAP=()
    CURRENT_HCTL_MAP=()
    
    local successful_mappings=0
    local line_count=0
    
    # 处理HCTL信息
    while IFS= read -r line; do
        ((line_count++))
        
        # 跳过标题行
        [[ $line_count -eq 1 ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 解析行数据 (NAME HCTL SERIAL MODEL SIZE)
        read -r name hctl serial model size <<< "$line"
        
        # 跳过无效行
        [[ -z "$name" || -z "$hctl" ]] && continue
        
        # 构建完整设备路径
        local disk_device="/dev/$name"
        
        # 验证设备是否存在
        if [[ ! -b "$disk_device" ]]; then
            echo -e "${YELLOW}设备不存在，跳过: $disk_device${NC}"
            continue
        fi
        
        # 分配LED
        if [[ $successful_mappings -lt ${#DISK_LEDS[@]} ]]; then
            local assigned_led="${DISK_LEDS[$successful_mappings]}"
            
            # 保存映射信息
            DISKS+=("$disk_device")
            DISK_LED_MAP["$disk_device"]="$assigned_led"
            DISK_HCTL_MAP["$disk_device"]="$hctl"
            DISK_INFO["$disk_device"]="$serial|$model|$size"
            
            # 保存到当前HCTL映射 (用于配置文件保存)
            CURRENT_HCTL_MAP["$disk_device"]="$hctl|$assigned_led|${serial:-N/A}|${model:-Unknown}|${size:-N/A}"
            
            echo -e "${GREEN}✓ 映射成功: $disk_device (HCTL: $hctl) -> $assigned_led${NC}"
            echo -e "  序列号: ${serial:-N/A} | 型号: ${model:-Unknown} | 大小: ${size:-N/A}"
            
            ((successful_mappings++))
        else
            echo -e "${YELLOW}! LED不足，无法映射: $disk_device${NC}"
        fi
        
    done <<< "$hctl_info"
    
    echo
    echo -e "${BLUE}HCTL映射总结:${NC}"
    echo -e "检测到硬盘: $successful_mappings 个"
    echo -e "可用LED: ${#DISK_LEDS[@]} 个"
    echo -e "成功映射: $successful_mappings 个"
    
    if [[ $successful_mappings -eq 0 ]]; then
        echo -e "${RED}没有成功映射任何硬盘${NC}"
        return 1
    fi
    
    return 0
}

# 保存HCTL映射到配置文件
save_hctl_mapping_config() {
    echo -e "${CYAN}保存HCTL映射到配置文件...${NC}"
    
    # 确保配置目录存在
    ensure_config_dir
    
    # 创建备份 (如果文件存在)
    if [[ -f "$HCTL_CONFIG" ]]; then
        local backup_file="${HCTL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$HCTL_CONFIG" "$backup_file"
        echo -e "${BLUE}已备份原配置文件: $backup_file${NC}"
    fi
    
    # 写入配置文件
    cat > "$HCTL_CONFIG" << EOF
# HCTL硬盘位置映射配置文件
# 版本: $SCRIPT_VERSION
# 此文件由系统自动生成和维护，记录硬盘HCTL信息与LED位置的映射关系

# 配置文件信息
CONFIG_VERSION="$SCRIPT_VERSION"
LAST_UPDATE="$(date '+%Y-%m-%d %H:%M:%S')"
AUTO_GENERATED=true

# HCTL映射格式说明:
# HCTL_MAPPING[硬盘设备]=HCTL信息|LED位置|序列号|型号|大小
# 例如: HCTL_MAPPING[/dev/sda]=0:0:0:0|disk1|WD123456|WD Blue|1TB

# 自动生成的HCTL映射 (由脚本维护)
EOF
    
    # 写入映射数据
    local mapping_count=0
    for disk_device in "${!CURRENT_HCTL_MAP[@]}"; do
        local mapping_info="${CURRENT_HCTL_MAP[$disk_device]}"
        echo "HCTL_MAPPING[$disk_device]=\"$mapping_info\"" >> "$HCTL_CONFIG"
        ((mapping_count++))
    done
    
    # 添加配置说明
    cat >> "$HCTL_CONFIG" << EOF

# 手动映射覆盖 (可手动编辑)
# 如果需要强制指定某个硬盘的LED映射，请在下方添加
# MANUAL_MAPPING[硬盘设备]=LED位置
# 例如: MANUAL_MAPPING[/dev/sda]=disk2

# 映射策略配置
AUTO_DETECTION=true          # 是否启用自动检测
HCTL_PRIORITY=true          # HCTL检测优先级高于传统检测
SAVE_ON_CHANGE=true         # 检测到变化时自动保存
BACKUP_ON_UPDATE=true       # 更新时备份旧配置

# 检测配置
SCAN_TIMEOUT=30             # 扫描超时时间(秒)
RETRY_COUNT=3               # 重试次数
EXCLUDE_DEVICES=""          # 排除的设备(用空格分隔)
EOF
    
    echo -e "${GREEN}✓ HCTL映射配置已保存: $HCTL_CONFIG${NC}"
    echo -e "${BLUE}保存了 $mapping_count 个设备映射${NC}"
    
    return 0
}

# 显示硬盘状态
show_disk_status() {
    echo -e "${CYAN}当前硬盘状态:${NC}"
    echo
    
    for disk in "${DISKS[@]}"; do
        local led="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析设备信息
        IFS='|' read -r serial model size <<< "$info"
        
        echo -e "${YELLOW}硬盘: $disk${NC}"
        echo -e "  LED位置: $led"
        echo -e "  HCTL: $hctl"
        echo -e "  序列号: ${serial:-N/A}"
        echo -e "  型号: ${model:-Unknown}"
        echo -e "  大小: ${size:-N/A}"
        
        # 检查硬盘状态
        if [[ -b "$disk" ]]; then
            local disk_status
            disk_status=$(hdparm -C "$disk" 2>/dev/null | grep "drive state is:" | awk -F': ' '{print $2}')
            if [[ -n "$disk_status" ]]; then
                case "$disk_status" in
                    *"active"*|*"idle"*)
                        echo -e "  状态: ${GREEN}活动${NC} ($disk_status)"
                        ;;
                    *"standby"*|*"sleeping"*)
                        echo -e "  状态: ${BLUE}休眠${NC} ($disk_status)"
                        ;;
                    *)
                        echo -e "  状态: ${YELLOW}未知${NC} ($disk_status)"
                        ;;
                esac
            else
                echo -e "  状态: ${RED}无法检测${NC}"
            fi
        else
            echo -e "  状态: ${RED}设备不存在${NC}"
        fi
        
        echo
    done
}

# 设置LED状态 (仅在交互模式下使用)
set_led_status() {
    local led="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    if [[ "$color" == "off" ]]; then
        "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
    else
        "$UGREEN_CLI" "$led" -color "$color" -brightness "$brightness" >/dev/null 2>&1
    fi
}

# 交互式LED测试
interactive_led_test() {
    echo -e "${CYAN}交互式LED测试模式${NC}"
    echo
    
    while true; do
        echo -e "${YELLOW}请选择操作:${NC}"
        echo "1. 测试所有硬盘LED"
        echo "2. 根据硬盘状态设置LED"
        echo "3. 关闭所有硬盘LED"
        echo "4. 显示硬盘状态"
        echo "5. 退出"
        echo
        read -p "请输入选择 (1-5): " choice
        
        case $choice in
            1)
                echo -e "${CYAN}测试所有硬盘LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    echo "测试 $disk -> $led (绿色)"
                    set_led_status "$led" "0 255 0" "$DEFAULT_BRIGHTNESS"
                    sleep 1
                done
                echo "测试完成"
                ;;
            2)
                echo -e "${CYAN}根据硬盘状态设置LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    local disk_status
                    disk_status=$(hdparm -C "$disk" 2>/dev/null | grep "drive state is:" | awk -F': ' '{print $2}')
                    
                    if [[ -n "$disk_status" ]]; then
                        case "$disk_status" in
                            *"active"*|*"idle"*)
                                echo "$disk: 活动状态 -> 白色"
                                set_led_status "$led" "$DISK_COLOR_ACTIVE" "$HIGH_BRIGHTNESS"
                                ;;
                            *"standby"*|*"sleeping"*)
                                echo "$disk: 休眠状态 -> 淡白色"
                                set_led_status "$led" "$DISK_COLOR_STANDBY" "$LOW_BRIGHTNESS"
                                ;;
                            *)
                                echo "$disk: 未知状态 -> 关闭"
                                set_led_status "$led" "off"
                                ;;
                        esac
                    else
                        echo "$disk: 无法检测状态 -> 关闭"
                        set_led_status "$led" "off"
                    fi
                done
                ;;
            3)
                echo -e "${CYAN}关闭所有硬盘LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    echo "关闭 $led"
                    set_led_status "$led" "off"
                done
                ;;
            4)
                show_disk_status
                ;;
            5)
                echo "退出交互模式"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                ;;
        esac
        echo
    done
}

# 主函数
main() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}智能硬盘活动状态监控 v$SCRIPT_VERSION${NC}"
    echo -e "${CYAN}HCTL映射版本${NC}"
    echo -e "${CYAN}================================${NC}"
    echo -e "更新时间: $LAST_UPDATE"
    echo -e "配置目录: $CONFIG_DIR"
    echo
    
    # 检查依赖
    check_dependencies
    
    # 加载配置
    load_config
    
    # 确保配置目录存在
    ensure_config_dir
    
    # 检测可用LED
    detect_available_leds
    
    # 检测硬盘映射
    if detect_disk_mapping_hctl; then
        echo -e "${GREEN}✓ HCTL硬盘映射检测成功${NC}"
        
        # 保存配置 (如果指定或更新映射模式)
        if [[ "$UPDATE_MAPPING" == "true" || "$SAVE_CONFIG" == "true" ]]; then
            save_hctl_mapping_config
        fi
        
        # 显示硬盘状态
        show_disk_status
        
        # 交互式模式
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            interactive_led_test
        fi
        
        echo -e "${GREEN}✓ 检测完成${NC}"
        exit 0
    else
        echo -e "${RED}✗ HCTL硬盘映射检测失败${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@"

# HCTL硬盘映射检测
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射...${NC}"
    echo -e "${BLUE}当前可用硬盘LED: ${DISK_LEDS[*]}${NC}"
    
    # 获取所有存储设备的HCTL信息
    local hctl_info
    hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)
    
    if [[ -z "$hctl_info" ]]; then
        echo -e "${YELLOW}无法获取HCTL信息，可能系统不支持或无存储设备${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的存储设备HCTL信息:${NC}"
    echo "$hctl_info"
    echo
    
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
            
            echo -e "${CYAN}处理设备: /dev/$name (HCTL: $hctl)${NC}"
            
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
                echo -e "${GREEN}✓ 映射: /dev/$name -> $target_led (HCTL host: $hctl_host)${NC}"
                ((successful_mappings++))
            else
                DISK_LED_MAP["/dev/$name"]="none"
                echo -e "${RED}✗ LED不可用: $target_led (HCTL host: $hctl_host)${NC}"
            fi
            
            # 保存设备信息
            DISK_INFO["/dev/$name"]="HCTL:$hctl Serial:${serial:-N/A} Model:${model:-N/A} Size:${size:-N/A}"
            DISK_HCTL_MAP["/dev/$name"]="$hctl"
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    echo
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，成功映射 $successful_mappings 个${NC}"
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

# 检测硬盘是否处于活动状态
check_disk_activity() {
    local device="$1"
    local stats_before stats_after
    
    # 移除/dev/前缀
    device=$(basename "$device")
    
    # 读取磁盘统计信息 (读写扇区数)
    if [[ -f "/proc/diskstats" ]]; then
        stats_before=$(grep " $device " /proc/diskstats | awk '{print $6+$10}')
        sleep 2
        stats_after=$(grep " $device " /proc/diskstats | awk '{print $6+$10}')
        
        if [[ "$stats_after" -gt "$stats_before" ]]; then
            echo "ACTIVE"
        else
            echo "IDLE"
        fi
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
        echo -e "${YELLOW}跳过设备 $device (无可用LED)${NC}"
        return
    fi
    
    echo -e "${BLUE}检查硬盘 $device -> $led_name${NC}"
    
    # 检查休眠状态
    local sleep_status=$(check_disk_sleep "$device")
    echo "  休眠状态: $sleep_status"
    
    if [[ "$sleep_status" == "SLEEPING" ]]; then
        # 休眠状态 - 微亮白光
        "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness ${LOW_BRIGHTNESS:-16}
        echo "  -> 休眠状态: 微亮白光"
        return
    fi
    
    # 检查活动状态
    local activity=$(check_disk_activity "$device")
    echo "  活动状态: $activity"
    
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
    echo "  健康状态: $health"
    
    # 根据活动状态和健康状态设置LED
    case "$health" in
        "GOOD")
            case "$activity" in
                "ACTIVE")
                    # 活动且健康 - 绿色高亮
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                    echo "  -> 活动健康: 绿色高亮"
                    ;;
                "IDLE")
                    # 空闲且健康 - 绿色微亮
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 空闲健康: 绿色微亮"
                    ;;
                *)
                    # 状态未知 - 绿色默认亮度
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 状态未知但健康: 绿色默认"
                    ;;
            esac
            ;;
        "BAD")
            case "$activity" in
                "ACTIVE")
                    # 活动但异常 - 红色闪烁
                    for i in {1..3}; do
                        "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                        sleep 0.3
                        "$UGREEN_CLI" "$led_name" -off
                        sleep 0.3
                    done
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                    echo "  -> 活动异常: 红色闪烁"
                    ;;
                *)
                    # 空闲但异常 - 红色常亮
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 空闲异常: 红色常亮"
                    ;;
            esac
            ;;
        *)
            # 状态未知 - 黄色
            "$UGREEN_CLI" "$led_name" -color 255 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
            echo "  -> 状态未知: 黄色"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${CYAN}开始智能硬盘活动监控 (HCTL版)...${NC}"
    
    # 检测LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: 未找到LED控制程序 $UGREEN_CLI${NC}"
        return 1
    fi
    
    # 检测可用LED
    if ! detect_available_leds; then
        echo -e "${RED}LED检测失败${NC}"
        return 1
    fi
    
    # 使用HCTL方式检测硬盘映射
    if ! detect_disk_mapping_hctl; then
        echo -e "${RED}硬盘映射检测失败${NC}"
        return 1
    fi
    
    echo -e "${CYAN}=== 硬盘映射结果 ===${NC}"
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]}"
        local info="${DISK_INFO[$disk]}"
        echo -e "${YELLOW}$disk${NC} -> ${GREEN}$led_name${NC} (HCTL: $hctl)"
        echo "  $info"
    done
    echo
    
    # 为每个硬盘设置LED
    echo -e "${CYAN}=== 设置硬盘LED状态 ===${NC}"
    for disk in "${DISKS[@]}"; do
        set_disk_led_by_activity "$disk"
        echo
    done
    
    echo -e "${GREEN}智能硬盘活动状态设置完成${NC}"
    echo -e "${YELLOW}LED状态说明:${NC}"
    echo "  🟢 绿色高亮 - 硬盘活动且健康"
    echo "  🟢 绿色微亮 - 硬盘空闲且健康" 
    echo "  ⚪ 白色微亮 - 硬盘休眠"
    echo "  🔴 红色闪烁 - 硬盘活动但异常"
    echo "  🔴 红色常亮 - 硬盘空闲但异常"
    echo "  🟡 黄色 - 硬盘状态未知"
    echo
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，支持最多 ${#DISK_LEDS[@]} 个LED槽位${NC}"
}

# 运行主函数
main "$@"
