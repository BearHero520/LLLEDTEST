#!/bin/bash

# 绿联LED控制工具 - 优化版 (HCTL映射+智能检测)
# 项目地址: https://github.com/BearHero520/LLLED
# 版本: 2.0.7 (优化版 - 完全重建避免语法错误)

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

# 新的HCTL硬盘映射检测函数 - 完全重写
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
    
    # 使用简单的方式处理每一行
    echo "$hctl_info" | while IFS= read -r line; do
        # 跳过标题行
        if [[ "$line" =~ ^NAME ]]; then
            continue
        fi
        
        # 跳过空行
        if [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
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
            echo -e "${CYAN}处理设备: /dev/$name (HCTL: $hctl)${NC}"
            
            # 提取HCTL target值
            local hctl_target
            hctl_target=$(echo "$hctl" | cut -d: -f3)
            
            # 根据HCTL target映射到LED槽位
            local led_number
            case "$hctl_target" in
                "0") led_number=1 ;;
                "1") led_number=2 ;;
                "2") led_number=3 ;;
                "3") led_number=4 ;;
                "4") led_number=5 ;;
                "5") led_number=6 ;;
                "6") led_number=7 ;;
                "7") led_number=8 ;;
                *) led_number=$((hctl_target + 1)) ;;
            esac
            
            local target_led="disk${led_number}"
            
            # 检查目标LED是否可用
            local led_available=false
            for available_led in "${DISK_LEDS[@]}"; do
                if [[ "$available_led" == "$target_led" ]]; then
                    led_available=true
                    break
                fi
            done
            
            if [[ "$led_available" == "true" ]]; then
                echo -e "${GREEN}✓ 映射: /dev/$name -> $target_led (HCTL target: $hctl_target)${NC}"
            else
                target_led="none"
                echo -e "${RED}✗ LED不可用: disk${led_number} (HCTL target: $hctl_target)${NC}"
            fi
            
            # 由于使用管道，变量修改不会保留到父shell
            # 这里只是显示映射信息
        fi
    done
    
    # 重新处理数据，这次保留变量修改
    local temp_file="/tmp/hctl_mapping_$$"
    echo "$hctl_info" > "$temp_file"
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^NAME ]] || [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
            continue
        fi
        
        local name hctl serial model size
        name=$(echo "$line" | awk '{print $1}')
        hctl=$(echo "$line" | awk '{print $2}')
        serial=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{print $4}')
        size=$(echo "$line" | awk '{print $5}')
        
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
            
            local hctl_target=$(echo "$hctl" | cut -d: -f3)
            local led_number
            
            case "$hctl_target" in
                "0") led_number=1 ;;
                "1") led_number=2 ;;
                "2") led_number=3 ;;
                "3") led_number=4 ;;
                "4") led_number=5 ;;
                "5") led_number=6 ;;
                "6") led_number=7 ;;
                "7") led_number=8 ;;
                *) led_number=$((hctl_target + 1)) ;;
            esac
            
            local target_led="disk${led_number}"
            local led_available=false
            
            for available_led in "${DISK_LEDS[@]}"; do
                if [[ "$available_led" == "$target_led" ]]; then
                    led_available=true
                    break
                fi
            done
            
            if [[ "$led_available" == "true" ]]; then
                DISK_LED_MAP["/dev/$name"]="$target_led"
                ((successful_mappings++))
            else
                DISK_LED_MAP["/dev/$name"]="none"
            fi
            
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

# 其余函数保持不变...
# 这里只重写了有问题的detect_disk_mapping_hctl函数
echo "HCTL映射函数已重写 - v2.0.7"
