#!/bin/bash

# 多盘位支持测试脚本
# 测试LLLED系统是否正确支持多盘位设备

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${CYAN}=== LLLED 多盘位支持测试 ===${NC}"
echo ""

# 测试1: 检查配置文件是否支持多盘位
echo -e "${BLUE}测试1: 检查配置文件多盘位支持${NC}"
config_file="config/led_mapping.conf"

if [[ -f "$config_file" ]]; then
    disk_vars=$(grep -E "^DISK[5-8]_LED=" "$config_file" | wc -l)
    if [[ $disk_vars -ge 4 ]]; then
        echo -e "${GREEN}✓ 配置文件支持8盘位 (DISK1-DISK8)${NC}"
    elif [[ $disk_vars -ge 2 ]]; then
        echo -e "${YELLOW}△ 配置文件支持6盘位 (DISK1-DISK6)${NC}"
    else
        echo -e "${RED}✗ 配置文件仅支持4盘位${NC}"
    fi
else
    echo -e "${RED}✗ 配置文件不存在${NC}"
fi

# 测试2: 检查disk_status_leds.sh脚本
echo -e "${BLUE}测试2: 检查硬盘状态脚本${NC}"
script_file="scripts/disk_status_leds.sh"

if [[ -f "$script_file" ]]; then
    # 检查是否有动态LED检测
    if grep -q "detect_available_leds" "$script_file"; then
        echo -e "${GREEN}✓ 支持动态LED检测${NC}"
    else
        echo -e "${RED}✗ 缺少动态LED检测${NC}"
    fi
    
    # 检查LED_ID_MAP是否包含多盘位
    disk8_count=$(grep -c "disk[5-8]" "$script_file")
    if [[ $disk8_count -ge 4 ]]; then
        echo -e "${GREEN}✓ 脚本支持8盘位硬盘LED${NC}"
    else
        echo -e "${YELLOW}△ 脚本支持有限的多盘位${NC}"
    fi
    
    # 检查get_led_id_by_hctl函数
    if grep -A 20 "get_led_id_by_hctl" "$script_file" | grep -q "disk[5-8]"; then
        echo -e "${GREEN}✓ HCTL映射函数支持多盘位${NC}"
    else
        echo -e "${RED}✗ HCTL映射函数仅支持4盘位${NC}"
    fi
else
    echo -e "${RED}✗ 硬盘状态脚本不存在${NC}"
fi

# 测试3: 检查其他LED脚本
echo -e "${BLUE}测试3: 检查其他LED相关脚本${NC}"

scripts_to_check=(
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh" 
    "scripts/smart_disk_activity.sh"
)

for script in "${scripts_to_check[@]}"; do
    script_name=$(basename "$script")
    if [[ -f "$script" ]]; then
        if grep -q "detect_available_leds\|AVAILABLE_LEDS" "$script"; then
            echo -e "${GREEN}✓ $script_name 支持动态LED检测${NC}"
        else
            echo -e "${YELLOW}△ $script_name 可能使用固定LED列表${NC}"
        fi
    else
        echo -e "${RED}✗ $script_name 不存在${NC}"
    fi
done

# 测试4: 模拟LED检测
echo -e "${BLUE}测试4: 模拟LED检测功能${NC}"

if [[ -f "ugreen_leds_cli" ]]; then
    echo -e "${GREEN}✓ ugreen_leds_cli 程序存在${NC}"
    
    # 尝试检测LED状态
    led_status=$(./ugreen_leds_cli all -status 2>/dev/null)
    if [[ $? -eq 0 && -n "$led_status" ]]; then
        led_count=$(echo "$led_status" | grep -c "LED")
        echo -e "${GREEN}✓ 检测到 $led_count 个LED设备${NC}"
        
        # 显示检测到的LED
        echo -e "${CYAN}检测到的LED列表:${NC}"
        echo "$led_status" | grep "LED" | while read -r line; do
            if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
                led_name="${BASH_REMATCH[1]}"
                echo -e "  - $led_name"
            fi
        done
    else
        echo -e "${YELLOW}△ 无法检测LED状态 (可能需要root权限或设备不支持)${NC}"
    fi
else
    echo -e "${YELLOW}△ ugreen_leds_cli 程序不存在 (需要先运行安装脚本)${NC}"
fi

# 测试5: 检查系统硬盘
echo -e "${BLUE}测试5: 检查系统硬盘配置${NC}"

# 检测SATA硬盘
sata_disks=$(lsblk -d -n -o NAME,TRAN 2>/dev/null | grep sata | wc -l)
if [[ $sata_disks -gt 0 ]]; then
    echo -e "${GREEN}✓ 检测到 $sata_disks 个SATA硬盘${NC}"
    
    if [[ $sata_disks -gt 4 ]]; then
        echo -e "${CYAN}  系统有 $sata_disks 个硬盘，需要多盘位支持${NC}"
    fi
    
    # 显示HCTL信息
    echo -e "${CYAN}硬盘HCTL信息:${NC}"
    lsblk -S -o NAME,HCTL 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^sd[a-z] ]]; then
            echo -e "  $line"
        fi
    done
else
    echo -e "${YELLOW}△ 未检测到SATA硬盘${NC}"
fi

echo ""
echo -e "${CYAN}=== 测试完成 ===${NC}"
echo ""

# 总结
echo -e "${BLUE}功能支持总结:${NC}"
echo -e "  - 配置文件多盘位支持: $(grep -c "^DISK[1-8]_LED=" "$config_file" 2>/dev/null || echo 0)/8"
echo -e "  - 动态LED检测: $(ls scripts/*.sh | xargs grep -l "detect_available_leds" | wc -l)/$(ls scripts/*.sh | wc -l) 个脚本支持"
echo -e "  - 系统硬盘数量: $sata_disks 个"

if [[ $sata_disks -gt 4 ]]; then
    echo ""
    echo -e "${YELLOW}建议: 您的系统有超过4个硬盘，确保:${NC}"
    echo -e "  1. 运行安装脚本获取 ugreen_leds_cli"
    echo -e "  2. 根据实际硬盘HCTL地址调整配置文件"
    echo -e "  3. 测试LED控制功能是否正常"
fi
