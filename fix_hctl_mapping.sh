#!/bin/bash

# 紧急修复版本 - 直接修复HCTL映射问题
# 版本: 2.0.7-hotfix

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== HCTL映射紧急修复 v2.0.7 ===${NC}"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

# 查找LED控制程序
UGREEN_LEDS_CLI=""
search_paths=(
    "/opt/ugreen-led-controller/ugreen_leds_cli"
    "/usr/bin/ugreen_leds_cli"
    "/usr/local/bin/ugreen_leds_cli"
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
    exit 1
fi

echo
echo "1. 当前LED状态："
$UGREEN_LEDS_CLI all -status

echo
echo "2. 硬盘HCTL信息："
hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)
echo "$hctl_info"

echo
echo "3. 应用正确的HCTL映射："

# 直接映射逻辑
declare -A correct_mapping

while IFS= read -r line; do
    [[ "$line" =~ ^NAME ]] && continue
    [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
    
    name=$(echo "$line" | awk '{print $1}')
    hctl=$(echo "$line" | awk '{print $2}')
    
    if [[ "$name" =~ ^sd[a-z]+$ && -b "/dev/$name" ]]; then
        hctl_target=$(echo "$hctl" | cut -d: -f3)
        
        # 直接映射：target值直接对应槽位号
        case "$hctl_target" in
            "0") target_led="disk1" ;;
            "1") target_led="disk2" ;;
            "2") target_led="disk3" ;;
            "3") target_led="disk4" ;;
            *) target_led="disk$((hctl_target + 1))" ;;
        esac
        
        correct_mapping["/dev/$name"]="$target_led"
        echo "/dev/$name (HCTL: $hctl, target: $hctl_target) -> $target_led"
    fi
done <<< "$hctl_info"

echo
echo "4. 应用LED状态："

# 先关闭所有硬盘LED
for led in disk1 disk2 disk3 disk4; do
    $UGREEN_LEDS_CLI "$led" -off 2>/dev/null
done

# 应用正确的映射
for disk in "${!correct_mapping[@]}"; do
    led="${correct_mapping[$disk]}"
    
    # 检查硬盘活动状态
    disk_name=$(basename "$disk")
    if [[ -r "/sys/block/$disk_name/stat" ]]; then
        read1=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        sleep 0.1
        read2=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        
        if [[ -n "$read1" && -n "$read2" && "$read2" -gt "$read1" ]]; then
            # 活动状态 - 绿色高亮
            $UGREEN_LEDS_CLI "$led" -color 0 255 0 -on -brightness 255
            echo "✓ $disk -> $led (活动状态 - 绿色)"
        else
            # 空闲状态 - 黄色低亮
            $UGREEN_LEDS_CLI "$led" -color 255 255 0 -on -brightness 64
            echo "✓ $disk -> $led (空闲状态 - 黄色)"
        fi
    else
        # 默认状态 - 蓝色
        $UGREEN_LEDS_CLI "$led" -color 0 100 255 -on -brightness 128
        echo "✓ $disk -> $led (默认状态 - 蓝色)"
    fi
done

echo
echo "5. 最终LED状态："
$UGREEN_LEDS_CLI all -status

echo
echo -e "${GREEN}HCTL映射修复完成！${NC}"
echo "期望结果："
echo "  disk1: 亮 (sda - 槽位1)"
echo "  disk2: 不亮 (无硬盘)"
echo "  disk3: 亮 (sdc - 槽位3)"
echo "  disk4: 亮 (sdd - 槽位4)"
