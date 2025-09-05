#!/bin/bash

# 绿联LED控制工具 - 优化版 (HCTL映射+智能检测)
# 项目地址: https://github.com/BearHero520/LLLED
# 版本: 2.0.0 (优化版 - HCTL映射+多LED检测)

VERSION="2.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

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
    LED_TYPES=("power" "netdev" "disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
    
    for led in "${LED_TYPES[@]}"; do
        if $UGREEN_LEDS_CLI "$led" -status &>/dev/null; then
            AVAILABLE_LEDS+=("$led")
            echo -e "${GREEN}✓ 检测到LED: $led${NC}"
        else
            echo -e "${YELLOW}✗ LED不可用: $led${NC}"
        fi
    done
    
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

# 使用HCTL检测硬盘映射
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射...${NC}"
    
    # 获取所有硬盘的HCTL信息
    local hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model 2>/dev/null)
    
    if [[ -z "$hctl_info" ]]; then
        echo -e "${RED}无法获取硬盘HCTL信息${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}硬盘HCTL信息:${NC}"
    echo "$hctl_info"
    echo
    
    # 解析HCTL信息并建立映射
    DISKS=()
    declare -gA DISK_LED_MAP
    declare -gA DISK_INFO
    
    local disk_index=0
    
    while IFS= read -r line; do
        # 跳过标题行
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$line" ]] && continue
        
        local name=$(echo "$line" | awk '{print $1}')
        local hctl=$(echo "$line" | awk '{print $2}')
        local serial=$(echo "$line" | awk '{print $3}')
        local model=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')
        
        # 只处理真实的硬盘设备
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
            
            # 根据HCTL的第一个数字映射到LED (0->disk1, 1->disk2, ...)
            local hctl_slot=$(echo "$hctl" | cut -d: -f1)
            local led_number=$((hctl_slot + 1))
            
            # 检查对应的LED是否可用
            if [[ " ${DISK_LEDS[*]} " =~ " disk${led_number} " ]]; then
                DISK_LED_MAP["/dev/$name"]="disk${led_number}"
            else
                # 如果对应LED不可用，按顺序分配可用LED
                if [[ $disk_index -lt ${#DISK_LEDS[@]} ]]; then
                    DISK_LED_MAP["/dev/$name"]="${DISK_LEDS[$disk_index]}"
                else
                    DISK_LED_MAP["/dev/$name"]="none"
                fi
            fi
            
            DISK_INFO["/dev/$name"]="HCTL:$hctl Serial:${serial:-N/A} Model:${model:-N/A}"
            
            echo -e "${GREEN}✓ /dev/$name -> ${DISK_LED_MAP["/dev/$name"]} (HCTL: $hctl)${NC}"
            
            ((disk_index++))
        fi
    done < <(echo "$hctl_info")
    
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，已分配 LED 映射${NC}"
    echo
}

# 备用硬盘检测方法
detect_disk_mapping_fallback() {
    echo -e "${CYAN}使用备用方式检测硬盘...${NC}"
    
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

# 主检测函数
detect_system() {
    echo -e "${CYAN}=== 系统检测 ===${NC}"
    
    # 1. 检测LED控制程序
    if ! detect_led_controller; then
        exit 1
    fi
    
    # 2. 检测可用LED
    detect_available_leds
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘LED，程序无法正常工作${NC}"
        exit 1
    fi
    
    # 3. 检测硬盘映射 (优先使用HCTL方式)
    if ! detect_disk_mapping_hctl; then
        echo -e "${YELLOW}HCTL检测失败，使用备用方式...${NC}"
        detect_disk_mapping_fallback
    fi
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘${NC}"
        exit 1
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

# 智能硬盘状态显示
smart_disk_status() {
    echo -e "${CYAN}智能硬盘状态显示${NC}"
    echo "=========================="
    
    for disk in "${DISKS[@]}"; do
        local status=$(get_disk_status "$disk")
        local led_name="${DISK_LED_MAP[$disk]}"
        local info="${DISK_INFO[$disk]}"
        
        set_disk_led "$disk" "$status"
        
        # 状态颜色显示
        local status_color
        case "$status" in
            "active") status_color="${GREEN}活动${NC}" ;;
            "idle") status_color="${YELLOW}空闲${NC}" ;;
            "error") status_color="${RED}错误${NC}" ;;
            "offline") status_color="${MAGENTA}离线${NC}" ;;
            *) status_color="${RED}未知${NC}" ;;
        esac
        
        printf "%-12s -> %-6s [%s] %s\n" "$disk" "$led_name" "$status_color" "$info"
    done
    
    echo -e "${GREEN}智能硬盘状态已更新${NC}"
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

# 显示硬盘映射信息
show_disk_mapping() {
    echo -e "${CYAN}硬盘LED映射信息${NC}"
    echo "================================"
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local info="${DISK_INFO[$disk]}"
        
        # 状态颜色
        local status_color
        case "$status" in
            "active") status_color="${GREEN}$status${NC}" ;;
            "idle") status_color="${YELLOW}$status${NC}" ;;
            "error") status_color="${RED}$status${NC}" ;;
            "offline") status_color="${MAGENTA}$status${NC}" ;;
            *) status_color="${RED}$status${NC}" ;;
        esac
        
        if [[ "$led_name" == "none" ]]; then
            printf "%-12s -> %-6s [%s]\n" "$disk" "不映射" "$status_color"
        else
            printf "%-12s -> %-6s [%s]\n" "$disk" "$led_name" "$status_color"
        fi
        
        echo "    $info"
        echo
    done
}

# 交互式配置硬盘映射
interactive_config() {
    echo -e "${CYAN}交互式硬盘映射配置${NC}"
    echo "============================"
    
    echo -e "${YELLOW}当前映射:${NC}"
    show_disk_mapping
    
    echo -e "${YELLOW}可用LED:${NC} ${DISK_LEDS[*]}"
    echo
    
    declare -A new_mapping
    declare -A used_leds
    
    for disk in "${DISKS[@]}"; do
        local info="${DISK_INFO[$disk]}"
        
        echo -e "${GREEN}配置硬盘: $disk${NC}"
        echo "  $info"
        echo
        
        while true; do
            echo "可用LED位置:"
            local led_index=1
            for led in "${DISK_LEDS[@]}"; do
                if [[ -z "${used_leds[$led]}" ]]; then
                    echo "  $led_index) $led"
                    ((led_index++))
                fi
            done
            echo "  n) 不映射"
            echo "  s) 跳过此硬盘"
            echo
            
            read -p "请选择LED (数字/n/s): " choice
            
            if [[ "$choice" == "n" ]]; then
                new_mapping["$disk"]="none"
                echo -e "${YELLOW}已设置: $disk -> 不映射${NC}"
                break
            elif [[ "$choice" == "s" ]]; then
                echo -e "${YELLOW}跳过: $disk${NC}"
                break
            elif [[ "$choice" =~ ^[0-9]+$ ]]; then
                local selected_led=""
                local current_index=1
                for led in "${DISK_LEDS[@]}"; do
                    if [[ -z "${used_leds[$led]}" ]]; then
                        if [[ $current_index -eq $choice ]]; then
                            selected_led="$led"
                            break
                        fi
                        ((current_index++))
                    fi
                done
                
                if [[ -n "$selected_led" ]]; then
                    new_mapping["$disk"]="$selected_led"
                    used_leds["$selected_led"]="$disk"
                    echo -e "${GREEN}已设置: $disk -> $selected_led${NC}"
                    break
                else
                    echo -e "${RED}无效选择${NC}"
                fi
            else
                echo -e "${RED}无效输入${NC}"
            fi
        done
        echo
    done
    
    # 应用新映射
    echo -e "${CYAN}应用新的映射配置...${NC}"
    for disk in "${!new_mapping[@]}"; do
        DISK_LED_MAP["$disk"]="${new_mapping[$disk]}"
    done
    
    echo -e "${GREEN}映射配置已更新${NC}"
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
