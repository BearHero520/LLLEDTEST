#!/bin/bash

# 绿联LED控制工具 - 优化版 (HCTL映射+智能检测)
# 项目地址: https://github.com/BearHero520/LLLED
# 版本: 2.0.7 (优化版 - 修复备用方法覆盖HCTL映射)

VERSION="2.0.7"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 全局变量声明
UGREEN_LEDS_CLI=""
AVAILABLE_LEDS=()
DISK_LEDS=()
SYSTEM_LEDS=()
DISKS=()
declare -A DISK_LED_MAP
declare -A DISK_INFO
declare -A DISK_HCTL_MAP

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 支持的UGREEN设备列表
SUPPORTED_MODELS=(
    "UGREEN DX4600 Pro"
    "UGREEN DX4700+"
    "UGREEN DXP2800"
    "UGREEN DXP4800"
    "UGREEN DXP4800 Plus"
    "UGREEN DXP6800 Pro"
    "UGREEN DXP8800 Plus"
)

# 显示支持的设备
show_supported_devices() {
    echo -e "${CYAN}支持的UGREEN设备型号:${NC}"
    for model in "${SUPPORTED_MODELS[@]}"; do
        echo "  - $model"
    done
    echo
}

# 查找LED控制程序（多路径支持）
detect_led_controller() {
    echo -e "${CYAN}检测LED控制程序...${NC}"
    
    UGREEN_LEDS_CLI=""
    local search_paths=(
        "/opt/ugreen-led-controller/ugreen_leds_cli"
        "/usr/bin/ugreen_leds_cli"
        "/usr/local/bin/ugreen_leds_cli"
        "./ugreen_leds_cli"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -x "$path" ]]; then
            UGREEN_LEDS_CLI="$path"
            echo -e "${GREEN}✓ 找到LED控制程序: $path${NC}"
            break
        fi
    done

    if [[ -z "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}✗ 未找到LED控制程序${NC}"
        echo -e "${YELLOW}请先安装LED控制程序:${NC}"
        echo "  cd /usr/bin"
        echo "  wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
        echo "  chmod +x ugreen_leds_cli"
        return 1
    fi

    # 加载i2c模块
    if ! lsmod | grep -q i2c_dev; then
        echo "加载i2c模块..."
        modprobe i2c-dev 2>/dev/null || echo -e "${YELLOW}警告: 无法加载i2c模块${NC}"
    fi
    
    return 0
}

# 检测可用LED灯
detect_available_leds() {
    echo -e "${CYAN}检测可用LED灯...${NC}"
    
    AVAILABLE_LEDS=()
    
    # 先检测所有LED状态
    local all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
    
    if [[ -z "$all_status" ]]; then
        echo -e "${RED}无法获取LED状态，请检查LED控制程序${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的LED状态:${NC}"
    echo "$all_status"
    echo
    
    # 解析LED状态输出，提取实际存在的LED
    # 使用字符串分割方式，避免文件操作
    local IFS=$'\n'
    local led_lines=($all_status)
    
    for line in "${led_lines[@]}"; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            AVAILABLE_LEDS+=("$led_name")
            echo -e "${GREEN}✓ 检测到LED: $led_name${NC}"
        fi
    done
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到任何LED，请检查设备兼容性${NC}"
        return 1
    fi
    
    echo -e "${BLUE}可用LED数量: ${#AVAILABLE_LEDS[@]}${NC}"
    
    # 分类LED
    DISK_LEDS=()
    SYSTEM_LEDS=()
    
    for led in "${AVAILABLE_LEDS[@]}"; do
        if [[ "$led" =~ ^disk[0-9]+$ ]]; then
            DISK_LEDS+=("$led")
        else
            SYSTEM_LEDS+=("$led")
        fi
    done
    
    echo -e "${BLUE}硬盘LED: ${DISK_LEDS[*]}${NC}"
    echo -e "${BLUE}系统LED: ${SYSTEM_LEDS[*]}${NC}"
    echo
}

# 优化的HCTL硬盘映射检测
# 新的HCTL硬盘映射检测函数 - 完全重写避免语法错误
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射 v2.0.7...${NC}"
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
    
    # 使用临时文件处理数据，确保变量修改能保留
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
            
            # 提取HCTL target值并映射到LED槽位
            local hctl_target=$(echo "$hctl" | cut -d: -f3)
            local led_number
            
            case "$hctl_target" in
                "0") led_number=1 ;;  # target 0 -> 槽位1 (disk1)
                "1") led_number=2 ;;  # target 1 -> 槽位2 (disk2) 
                "2") led_number=3 ;;  # target 2 -> 槽位3 (disk3)
                "3") led_number=4 ;;  # target 3 -> 槽位4 (disk4)
                "4") led_number=5 ;;  # target 4 -> 槽位5 (disk5)
                "5") led_number=6 ;;  # target 5 -> 槽位6 (disk6)
                "6") led_number=7 ;;  # target 6 -> 槽位7 (disk7)
                "7") led_number=8 ;;  # target 7 -> 槽位8 (disk8)
                *) led_number=$((hctl_target + 1)) ;;
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
                echo -e "${GREEN}✓ 映射: /dev/$name -> $target_led (HCTL target: $hctl_target)${NC}"
                ((successful_mappings++))
            else
                DISK_LED_MAP["/dev/$name"]="none"
                echo -e "${RED}✗ LED不可用: $target_led (HCTL target: $hctl_target)${NC}"
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

# 备用硬盘检测方法
detect_disk_mapping_fallback() {
    echo -e "${CYAN}使用备用方式检测硬盘...${NC}"
    
    # 注意：不要重新初始化DISK_LED_MAP，以保留已有的HCTL映射
    # DISKS=()  # 保留原有的DISKS数组
    # declare -gA DISK_LED_MAP  # 不重新初始化，保留HCTL映射
    # declare -gA DISK_INFO  # 不重新初始化
    
    # 如果DISKS数组为空，说明HCTL检测完全失败，需要重新检测
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        DISKS=()
        declare -gA DISK_LED_MAP
        declare -gA DISK_INFO
        
        local disk_index=0
        
        # 检测SATA硬盘
        for disk in /dev/sd[a-z]; do
            if [[ -b "$disk" ]]; then
                DISKS+=("$disk")
                
                # 按顺序分配可用的硬盘LED
                if [[ $disk_index -lt ${#DISK_LEDS[@]} ]]; then
                    DISK_LED_MAP["$disk"]="${DISK_LEDS[$disk_index]}"
                else
                    DISK_LED_MAP["$disk"]="none"
                fi
                
                local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
                local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
                DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
                
                echo -e "${GREEN}✓ $disk -> ${DISK_LED_MAP["$disk"]}${NC}"
                ((disk_index++))
            fi
        done
    else
        echo -e "${YELLOW}HCTL检测已有结果，跳过备用检测以保留HCTL映射${NC}"
        echo -e "${BLUE}当前映射: ${#DISKS[@]} 个硬盘已映射${NC}"
    fi
    
    # 检测NVMe硬盘
    for disk in /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
            
            if [[ $disk_index -lt ${#DISK_LEDS[@]} ]]; then
                DISK_LED_MAP["$disk"]="${DISK_LEDS[$disk_index]}"
            else
                DISK_LED_MAP["$disk"]="none"
            fi
            
            local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
            local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
            
            echo -e "${GREEN}✓ $disk -> ${DISK_LED_MAP["$disk"]}${NC}"
            ((disk_index++))
        fi
    done
    
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘${NC}"
    echo
}

# 优化的主检测函数 - 先检测LED再检测硬盘
detect_system() {
    echo -e "${CYAN}=== 系统自动检测 ===${NC}"
    echo "开始检测UGREEN LED控制系统..."
    echo
    
    # 第一步：检测LED控制程序
    echo -e "${BLUE}[1/3] 检测LED控制程序...${NC}"
    if ! detect_led_controller; then
        echo -e "${RED}LED控制程序检测失败，无法继续${NC}"
        exit 1
    fi
    echo
    
    # 第二步：检测可用LED灯
    echo -e "${BLUE}[2/3] 检测可用LED灯...${NC}"
    detect_available_leds
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到任何可用LED，程序无法正常工作${NC}"
        exit 1
    fi
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}警告: 未检测到硬盘LED，硬盘状态功能将受限${NC}"
        echo -e "${BLUE}仅检测到系统LED: ${SYSTEM_LEDS[*]}${NC}"
        
        # 询问是否继续
        echo -e "${YELLOW}是否继续运行？ (y/N)${NC}"
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}退出程序${NC}"
            exit 0
        fi
    fi
    echo
    
    # 第三步：检测硬盘映射 (仅在有硬盘LED时执行)
    if [[ ${#DISK_LEDS[@]} -gt 0 ]]; then
        echo -e "${BLUE}[3/3] 检测硬盘设备和映射...${NC}"
        
        # 优先使用HCTL方式检测
        if detect_disk_mapping_hctl; then
            echo -e "${GREEN}✓ HCTL映射检测成功${NC}"
        else
            echo -e "${YELLOW}⚠ HCTL检测失败，尝试备用方式...${NC}"
            detect_disk_mapping_fallback
        fi
        
        if [[ ${#DISKS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}警告: 未检测到硬盘设备${NC}"
            echo -e "${BLUE}LED控制功能仍可正常使用${NC}"
        else
            echo -e "${GREEN}✓ 检测到 ${#DISKS[@]} 个硬盘设备${NC}"
        fi
    else
        echo -e "${BLUE}[3/3] 跳过硬盘检测 (无硬盘LED可用)${NC}"
        DISKS=()
        declare -gA DISK_LED_MAP
        declare -gA DISK_INFO
        declare -gA DISK_HCTL_MAP
    fi
    echo
    
    # 检测结果摘要
    echo -e "${GREEN}=== 检测结果摘要 ===${NC}"
    echo -e "${CYAN}LED控制程序:${NC} $UGREEN_LEDS_CLI"
    echo -e "${CYAN}可用LED总数:${NC} ${#AVAILABLE_LEDS[@]} (${AVAILABLE_LEDS[*]})"
    echo -e "${CYAN}硬盘LED数量:${NC} ${#DISK_LEDS[@]} (${DISK_LEDS[*]})"
    echo -e "${CYAN}系统LED数量:${NC} ${#SYSTEM_LEDS[@]} (${SYSTEM_LEDS[*]})"
    echo -e "${CYAN}检测硬盘数量:${NC} ${#DISKS[@]}"
    
    if [[ ${#DISKS[@]} -gt 0 ]]; then
        local mapped_count=0
        for disk in "${DISKS[@]}"; do
            if [[ "${DISK_LED_MAP[$disk]}" != "none" ]]; then
                ((mapped_count++))
            fi
        done
        echo -e "${CYAN}硬盘LED映射:${NC} ${mapped_count}/${#DISKS[@]}"
    fi
    
    echo -e "${GREEN}=== 系统检测完成 ===${NC}"
    echo
}

# 获取硬盘状态
get_disk_status() {
    local disk="$1"
    local status="unknown"
    
    if [[ ! -b "$disk" ]]; then
        echo "offline"
        return
    fi
    
    # 检查硬盘健康状态
    if command -v smartctl >/dev/null 2>&1; then
        local smart_status=$(smartctl -H "$disk" 2>/dev/null | grep -i "overall-health")
        if [[ "$smart_status" =~ FAILED ]]; then
            echo "error"
            return
        fi
    fi
    
    # 检查硬盘活动状态
    local disk_name=$(basename "$disk")
    
    # 方法1: 使用iostat
    if command -v iostat >/dev/null 2>&1; then
        local iostat_output=$(iostat -x 1 1 2>/dev/null | grep "$disk_name" | tail -1)
        if [[ -n "$iostat_output" ]]; then
            local util=$(echo "$iostat_output" | awk '{print $NF}' | sed 's/%//')
            if [[ -n "$util" ]] && (( $(echo "$util > 1" | bc -l 2>/dev/null || echo 0) )); then
                echo "active"
                return
            fi
        fi
    fi
    
    # 方法2: 检查/sys/block统计信息
    if [[ -r "/sys/block/$disk_name/stat" ]]; then
        local read1=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        sleep 0.5
        local read2=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        
        if [[ -n "$read1" && -n "$read2" && "$read2" -gt "$read1" ]]; then
            echo "active"
        else
            echo "idle"
        fi
    else
        echo "idle"
    fi
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
        "offline")
            $UGREEN_LEDS_CLI "$led_name" -color 128 128 128 -on -brightness 32
            ;;
        "off")
            $UGREEN_LEDS_CLI "$led_name" -off
            ;;
    esac
}

# 优化的智能硬盘状态显示
smart_disk_status() {
    echo -e "${CYAN}=== 智能硬盘状态显示 ===${NC}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "====================================="
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    # 表头
    printf "%-12s %-8s %-8s %-12s %s\n" "设备" "LED" "状态" "HCTL" "设备信息"
    echo "---------------------------------------------------------------------"
    
    local active_count=0
    local idle_count=0
    local error_count=0
    local offline_count=0
    
    for disk in "${DISKS[@]}"; do
        local status=$(get_disk_status "$disk")
        local led_name="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        
        # 设置LED状态
        set_disk_led "$disk" "$status"
        
        # 状态颜色和计数
        local status_display
        case "$status" in
            "active") 
                status_display="${GREEN}●活动${NC}"
                ((active_count++))
                ;;
            "idle") 
                status_display="${YELLOW}●空闲${NC}"
                ((idle_count++))
                ;;
            "error") 
                status_display="${RED}●错误${NC}"
                ((error_count++))
                ;;
            "offline") 
                status_display="${MAGENTA}●离线${NC}"
                ((offline_count++))
                ;;
            *) 
                status_display="${RED}●未知${NC}"
                ;;
        esac
        
        # LED显示
        local led_display
        if [[ "$led_name" == "none" ]]; then
            led_display="${RED}无LED${NC}"
        else
            led_display="${CYAN}$led_name${NC}"
        fi
        
        # 格式化输出
        printf "%-12s %-16s %-16s %-12s\n" "$disk" "$led_display" "$status_display" "$hctl"
        
        # 设备详细信息（缩进显示）
        echo "    $info"
        echo
    done
    
    # 统计信息
    echo "====================================="
    echo -e "${GREEN}状态统计:${NC}"
    echo "  活动: $active_count | 空闲: $idle_count | 错误: $error_count | 离线: $offline_count"
    echo "  总计: ${#DISKS[@]} 个硬盘，${#DISK_LEDS[@]} 个LED可用"
    
    # 健康状态概览
    if [[ $error_count -gt 0 ]]; then
        echo -e "${RED}⚠ 警告: 检测到 $error_count 个硬盘有错误状态${NC}"
    elif [[ $offline_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 注意: 有 $offline_count 个硬盘离线${NC}"
    else
        echo -e "${GREEN}✓ 所有硬盘状态正常${NC}"
    fi
    
    echo -e "${GREEN}智能硬盘状态已更新到LED显示${NC}"
}

# 实时硬盘活动监控
real_time_monitor() {
    echo -e "${CYAN}启动实时硬盘监控 (按Ctrl+C停止)...${NC}"
    
    trap 'echo -e "\n${YELLOW}停止监控${NC}"; return' INT
    
    while true; do
        clear
        echo -e "${CYAN}=== 实时硬盘活动监控 ===${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================"
        
        for disk in "${DISKS[@]}"; do
            local status=$(get_disk_status "$disk")
            local led_name="${DISK_LED_MAP[$disk]}"
            
            set_disk_led "$disk" "$status"
            
            # 状态图标
            local status_icon
            case "$status" in
                "active") status_icon="🟢" ;;
                "idle") status_icon="🟡" ;;
                "error") status_icon="🔴" ;;
                "offline") status_icon="⚫" ;;
                *) status_icon="❓" ;;
            esac
            
            printf "%s %-12s -> %-6s [%s]\n" "$status_icon" "$disk" "$led_name" "$status"
        done
        
        echo "================================"
        echo "按 Ctrl+C 停止监控"
        sleep 2
    done
    
    trap - INT
}

# 恢复系统LED状态
restore_system_leds() {
    echo -e "${CYAN}恢复系统LED状态...${NC}"
    
    # 恢复电源LED (绿色常亮)
    if [[ " ${SYSTEM_LEDS[*]} " =~ " power " ]]; then
        $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 128
        echo -e "${GREEN}✓ 电源LED已恢复${NC}"
    fi
    
    # 恢复网络LED (根据网络状态)
    if [[ " ${SYSTEM_LEDS[*]} " =~ " netdev " ]]; then
        if ip route | grep -q default; then
            # 有网络连接，蓝色常亮
            $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 128
            echo -e "${GREEN}✓ 网络LED已恢复 (已连接)${NC}"
        else
            # 无网络连接，橙色常亮
            $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 64
            echo -e "${YELLOW}✓ 网络LED已恢复 (未连接)${NC}"
        fi
    fi
}

# 优化的硬盘映射显示
show_disk_mapping() {
    echo -e "${CYAN}=== 硬盘LED映射状态 ===${NC}"
    echo "======================================"
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    # 表头
    printf "%-12s %-8s %-8s %-12s %-10s %s\n" "设备" "LED" "状态" "HCTL" "大小" "型号"
    echo "--------------------------------------------------------------------------"
    
    local mapped_count=0
    local unmapped_count=0
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析设备信息
        local model=""
        local size=""
        if [[ "$info" =~ Model:([^[:space:]]+) ]]; then
            model="${BASH_REMATCH[1]}"
        fi
        if [[ "$info" =~ Size:([^[:space:]]+) ]]; then
            size="${BASH_REMATCH[1]}"
        fi
        
        # 状态图标和颜色
        local status_display
        case "$status" in
            "active") status_display="${GREEN}●活动${NC}" ;;
            "idle") status_display="${YELLOW}●空闲${NC}" ;;
            "error") status_display="${RED}●错误${NC}" ;;
            "offline") status_display="${MAGENTA}●离线${NC}" ;;
            *) status_display="${RED}●未知${NC}" ;;
        esac
        
        # LED显示
        local led_display
        if [[ "$led_name" == "none" ]]; then
            led_display="${RED}未映射${NC}"
            ((unmapped_count++))
        else
            led_display="${CYAN}$led_name${NC}"
            ((mapped_count++))
        fi
        
        # 格式化输出
        printf "%-12s %-16s %-16s %-12s %-10s %s\n" \
            "$disk" "$led_display" "$status_display" "$hctl" "${size:-N/A}" "${model:-N/A}"
    done
    
    echo "--------------------------------------------------------------------------"
    echo -e "${BLUE}映射统计: 已映射 $mapped_count 个，未映射 $unmapped_count 个，总计 ${#DISKS[@]} 个硬盘${NC}"
    echo -e "${BLUE}可用LED: ${DISK_LEDS[*]} (共 ${#DISK_LEDS[@]} 个)${NC}"
    
    # 显示未使用的LED
    local unused_leds=()
    for led in "${DISK_LEDS[@]}"; do
        local is_used=false
        for disk in "${DISKS[@]}"; do
            if [[ "${DISK_LED_MAP[$disk]}" == "$led" ]]; then
                is_used=true
                break
            fi
        done
        if [[ "$is_used" == "false" ]]; then
            unused_leds+=("$led")
        fi
    done
    
    if [[ ${#unused_leds[@]} -gt 0 ]]; then
        echo -e "${YELLOW}未使用LED: ${unused_leds[*]}${NC}"
    else
        echo -e "${GREEN}所有LED已分配使用${NC}"
    fi
}

# 优化的交互式硬盘映射配置
interactive_config() {
    echo -e "${CYAN}=== 交互式硬盘映射配置 ===${NC}"
    echo "======================================="
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}当前硬盘映射状态:${NC}"
    show_disk_mapping
    
    echo -e "${BLUE}可用的LED位置: ${DISK_LEDS[*]}${NC}"
    echo -e "${BLUE}检测到的硬盘数量: ${#DISKS[@]}${NC}"
    echo
    
    echo -e "${YELLOW}配置选项:${NC}"
    echo "1) 自动重新映射 (基于HCTL优化)"
    echo "2) 手动配置每个硬盘"
    echo "3) 恢复默认映射"
    echo "4) 清除所有映射"
    echo "0) 返回主菜单"
    echo
    
    read -p "请选择配置方式 (1-4/0): " config_choice
    
    case $config_choice in
        1)
            # 自动重新映射
            echo -e "${CYAN}执行自动HCTL优化映射...${NC}"
            
            # 清空当前映射
            for disk in "${DISKS[@]}"; do
                unset DISK_LED_MAP["$disk"]
            done
            
            # 重新检测映射
            if detect_disk_mapping_hctl; then
                echo -e "${GREEN}✓ 自动映射完成${NC}"
            else
                echo -e "${YELLOW}HCTL映射失败，使用备用方式...${NC}"
                detect_disk_mapping_fallback
            fi
            ;;
            
        2)
            # 手动配置
            echo -e "${CYAN}手动配置硬盘映射...${NC}"
            manual_disk_mapping
            ;;
            
        3)
            # 恢复默认映射
            echo -e "${CYAN}恢复默认映射 (按检测顺序)...${NC}"
            local index=0
            for disk in "${DISKS[@]}"; do
                if [[ $index -lt ${#DISK_LEDS[@]} ]]; then
                    DISK_LED_MAP["$disk"]="${DISK_LEDS[$index]}"
                    echo -e "${GREEN}✓ $disk -> ${DISK_LEDS[$index]}${NC}"
                else
                    DISK_LED_MAP["$disk"]="none"
                    echo -e "${YELLOW}✓ $disk -> 无LED (超出可用范围)${NC}"
                fi
                ((index++))
            done
            ;;
            
        4)
            # 清除所有映射
            echo -e "${YELLOW}确认清除所有硬盘LED映射？ (y/N)${NC}"
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                for disk in "${DISKS[@]}"; do
                    DISK_LED_MAP["$disk"]="none"
                    # 关闭对应LED
                    set_disk_led "$disk" "off"
                done
                echo -e "${GREEN}✓ 所有映射已清除${NC}"
            else
                echo -e "${YELLOW}取消操作${NC}"
            fi
            ;;
            
        0)
            echo -e "${YELLOW}返回主菜单${NC}"
            return 0
            ;;
            
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}配置完成后的映射状态:${NC}"
    show_disk_mapping
}

# 手动硬盘映射配置
manual_disk_mapping() {
    declare -A new_mapping
    declare -A used_leds
    
    # 保留当前已使用的LED信息
    for disk in "${DISKS[@]}"; do
        local current_led="${DISK_LED_MAP[$disk]}"
        if [[ -n "$current_led" && "$current_led" != "none" ]]; then
            used_leds["$current_led"]="$disk"
        fi
    done
    
    echo -e "${CYAN}开始手动配置...${NC}"
    echo
    
    for disk in "${DISKS[@]}"; do
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        local current_led="${DISK_LED_MAP[$disk]}"
        
        echo -e "${GREEN}配置硬盘: $disk${NC}"
        echo "  HCTL: $hctl"
        echo "  信息: $info"
        echo "  当前映射: ${current_led:-未映射}"
        echo
        
        # 显示可用LED选项
        echo "可用LED选项:"
        local led_index=1
        local available_leds=()
        
        for led in "${DISK_LEDS[@]}"; do
            local led_status=""
            if [[ "${used_leds[$led]}" == "$disk" ]]; then
                led_status=" (当前)"
                available_leds+=("$led")
            elif [[ -z "${used_leds[$led]}" ]]; then
                led_status=" (可用)"
                available_leds+=("$led")
            else
                led_status=" (被${used_leds[$led]}使用)"
            fi
            
            if [[ -z "${used_leds[$led]}" || "${used_leds[$led]}" == "$disk" ]]; then
                echo "  $led_index) $led$led_status"
                ((led_index++))
            fi
        done
        
        echo "  n) 不映射LED"
        echo "  s) 跳过 (保持当前设置)"
        echo
        
        while true; do
            read -p "请选择 (数字/n/s): " choice
            
            if [[ "$choice" == "n" ]]; then
                new_mapping["$disk"]="none"
                # 释放当前LED
                if [[ -n "$current_led" && "$current_led" != "none" ]]; then
                    unset used_leds["$current_led"]
                fi
                echo -e "${YELLOW}✓ 设置: $disk -> 不映射${NC}"
                break
                
            elif [[ "$choice" == "s" ]]; then
                echo -e "${YELLOW}✓ 跳过: $disk (保持当前设置)${NC}"
                break
                
            elif [[ "$choice" =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#available_leds[@]} ]]; then
                local selected_led="${available_leds[$((choice-1))]}"
                
                # 释放当前LED
                if [[ -n "$current_led" && "$current_led" != "none" ]]; then
                    unset used_leds["$current_led"]
                fi
                
                # 如果选择的LED被其他设备使用，先释放
                if [[ -n "${used_leds[$selected_led]}" && "${used_leds[$selected_led]}" != "$disk" ]]; then
                    unset used_leds["$selected_led"]
                fi
                
                new_mapping["$disk"]="$selected_led"
                used_leds["$selected_led"]="$disk"
                echo -e "${GREEN}✓ 设置: $disk -> $selected_led${NC}"
                break
                
            else
                echo -e "${RED}无效选择，请重新输入${NC}"
            fi
        done
        echo "---"
    done
    
    # 应用新的映射配置
    echo -e "${CYAN}应用新的映射配置...${NC}"
    for disk in "${!new_mapping[@]}"; do
        DISK_LED_MAP["$disk"]="${new_mapping[$disk]}"
        echo -e "${GREEN}✓ 已应用: $disk -> ${new_mapping[$disk]}${NC}"
    done
    
    echo -e "${GREEN}手动映射配置完成${NC}"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}绿联LED控制工具 v$VERSION${NC}"
    echo -e "${CYAN}(优化版 - HCTL映射+智能检测)${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    show_supported_devices
    echo -e "${YELLOW}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
    echo -e "${YELLOW}硬盘数量: ${#DISKS[@]}${NC}"
    echo
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 智能硬盘状态显示"
    echo "4) 实时硬盘活动监控"
    echo "5) 彩虹效果"
    echo "6) 节能模式"
    echo "7) 夜间模式"
    echo "8) 显示硬盘映射"
    echo "9) 配置硬盘映射"
    echo "d) 删除脚本 (卸载)"
    echo "s) 恢复系统LED (电源+网络)"
    echo "0) 退出"
    echo "=================================="
    echo -n "请选择: "
}

# 卸载脚本
uninstall_script() {
    echo -e "${YELLOW}确认要删除/卸载LLLED脚本吗？ (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}正在卸载LLLED...${NC}"
        
        # 删除可能的安装位置
        local script_locations=(
            "/usr/local/bin/LLLED"
            "/usr/bin/LLLED"
            "/opt/ugreen-led-controller/LLLED"
        )
        
        for location in "${script_locations[@]}"; do
            if [[ -f "$location" ]]; then
                rm -f "$location"
                echo -e "${GREEN}✓ 删除: $location${NC}"
            fi
        done
        
        # 删除配置目录（可选）
        if [[ -d "/opt/ugreen-led-controller" ]]; then
            echo -e "${YELLOW}是否删除配置目录 /opt/ugreen-led-controller？ (y/N)${NC}"
            read -r delete_config
            if [[ "$delete_config" =~ ^[Yy]$ ]]; then
                rm -rf "/opt/ugreen-led-controller"
                echo -e "${GREEN}✓ 配置目录已删除${NC}"
            fi
        fi
        
        echo -e "${GREEN}LLLED卸载完成${NC}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        detect_system
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
    "--on")
        detect_system
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--disk-status")
        detect_system
        smart_disk_status
        ;;
    "--monitor")
        detect_system
        real_time_monitor
        ;;
    "--system")
        detect_system
        restore_system_leds
        ;;
    "--mapping")
        detect_system
        show_disk_mapping
        ;;
    "--help")
        echo "绿联LED控制工具 v$VERSION (优化版)"
        echo "用法: LLLED [选项]"
        echo
        echo "选项:"
        echo "  --off          关闭所有LED"
        echo "  --on           打开所有LED"
        echo "  --disk-status  智能硬盘状态显示"
        echo "  --monitor      实时硬盘活动监控"
        echo "  --system       恢复系统LED (电源+网络)"
        echo "  --mapping      显示硬盘映射"
        echo "  --version      显示版本信息"
        echo "  --help         显示帮助"
        echo
        show_supported_devices
        ;;
    "--version")
        echo "绿联LED控制工具 v$VERSION (优化版)"
        echo "项目地址: https://github.com/BearHero520/LLLED"
        echo "功能: HCTL映射 | 智能检测 | 多LED支持 | 实时监控"
        show_supported_devices
        ;;
    "menu"|"")
        detect_system
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) 
                    $UGREEN_LEDS_CLI all -off
                    echo -e "${GREEN}已关闭所有LED${NC}"
                    read -p "按回车继续..."
                    ;;
                2) 
                    $UGREEN_LEDS_CLI all -on
                    echo -e "${GREEN}已打开所有LED${NC}"
                    read -p "按回车继续..."
                    ;;
                3) 
                    smart_disk_status
                    read -p "按回车继续..."
                    ;;
                4) 
                    real_time_monitor
                    ;;
                5) 
                    echo -e "${CYAN}启动彩虹效果 (按Ctrl+C停止)...${NC}"
                    trap 'echo -e "\n${YELLOW}停止彩虹效果${NC}"; break' INT
                    while true; do
                        for color in "255 0 0" "0 255 0" "0 0 255" "255 255 0" "255 0 255" "0 255 255" "255 128 0" "128 0 255"; do
                            $UGREEN_LEDS_CLI all -color $color -on -brightness 128
                            sleep 0.8
                        done
                    done
                    trap - INT
                    ;;
                6) 
                    echo -e "${CYAN}设置节能模式...${NC}"
                    restore_system_leds
                    # 关闭硬盘LED
                    for led in "${DISK_LEDS[@]}"; do
                        $UGREEN_LEDS_CLI "$led" -off
                    done
                    echo -e "${GREEN}节能模式已设置 (仅保持系统LED)${NC}"
                    read -p "按回车继续..."
                    ;;
                7) 
                    echo -e "${CYAN}设置夜间模式...${NC}"
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 16
                    echo -e "${GREEN}夜间模式已设置${NC}"
                    read -p "按回车继续..."
                    ;;
                8)
                    show_disk_mapping
                    read -p "按回车继续..."
                    ;;
                9)
                    interactive_config
                    read -p "按回车继续..."
                    ;;
                d|D)
                    uninstall_script
                    ;;
                s|S)
                    restore_system_leds
                    read -p "按回车继续..."
                    ;;
                0) 
                    echo -e "${GREEN}退出${NC}"
                    exit 0
                    ;;
                *) 
                    echo -e "${RED}无效选项${NC}"
                    read -p "按回车继续..."
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
