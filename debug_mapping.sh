#!/bin/bash

# HCTL映射诊断脚本 - 实时调试
echo "=== HCTL映射诊断 v2.0.4 ==="

# 检查root权限
[[ $EUID -ne 0 ]] && { echo "需要root权限: sudo bash $0"; exit 1; }

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
        echo "✓ 找到LED控制程序: $path"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo "✗ 未找到LED控制程序"
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
echo "3. 模拟HCTL映射过程："

# 获取可用硬盘LED
DISK_LEDS=("disk1" "disk2" "disk3" "disk4")
echo "可用硬盘LED: ${DISK_LEDS[*]}"

declare -A DISK_LED_MAP

while IFS= read -r line; do
    [[ "$line" =~ ^NAME ]] && continue
    [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
    
    name=$(echo "$line" | awk '{print $1}')
    hctl=$(echo "$line" | awk '{print $2}')
    
    if [[ "$name" =~ ^sd[a-z]+$ ]]; then
        hctl_target=$(echo "$hctl" | cut -d: -f3)
        
        # 应用新的映射逻辑
        local led_number
        case "$hctl_target" in
            "0") led_number=1 ;;
            "1") led_number=2 ;;
            "2") led_number=3 ;;
            "3") led_number=4 ;;
            *) led_number=$((hctl_target + 1)) ;;
        esac
        
        target_led="disk${led_number}"
        DISK_LED_MAP["/dev/$name"]="$target_led"
        
        echo "/dev/$name (HCTL: $hctl) -> target: $hctl_target -> $target_led"
    fi
done <<< "$hctl_info"

echo
echo "4. 期望的映射结果："
for disk in "${!DISK_LED_MAP[@]}"; do
    echo "$disk -> ${DISK_LED_MAP[$disk]}"
done

echo
echo "5. 期望的LED状态："
echo "disk1: 亮 (sda - 槽位1)"
echo "disk2: 不亮 (无硬盘)"
echo "disk3: 亮 (sdc - 槽位3)"
echo "disk4: 亮 (sdd - 槽位4)"

echo
echo "如果LED状态不符合期望，请检查LLLED脚本是否使用了最新的映射逻辑"
