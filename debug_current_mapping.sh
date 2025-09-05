#!/bin/bash
# 调试当前映射状态

echo "=== 调试当前HCTL映射状态 ==="

# 获取HCTL信息
echo "1. HCTL硬盘信息："
lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null

echo
echo "2. 应该的映射关系（使用Host字段）："
while IFS= read -r line; do
    [[ "$line" =~ ^NAME ]] && continue
    [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
    
    name=$(echo "$line" | awk '{print $1}')
    hctl=$(echo "$line" | awk '{print $2}')
    
    if [[ "$name" =~ ^sd[a-z]+$ && -b "/dev/$name" ]]; then
        hctl_host=$(echo "$hctl" | cut -d: -f1)
        
        case "$hctl_host" in
            "0") target_led="disk1" ;;
            "1") target_led="disk2" ;;
            "2") target_led="disk3" ;;
            "3") target_led="disk4" ;;
            *) target_led="disk$((hctl_host + 1))" ;;
        esac
        
        echo "/dev/$name (HCTL: $hctl, Host: $hctl_host) -> $target_led"
    fi
done <<< "$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)"

echo
echo "3. 验证LED控制："
echo "正在测试LED控制..."

# 测试每个LED
for led in disk1 disk3 disk4; do
    echo "测试 $led:"
    /opt/ugreen-led-controller/ugreen_leds_cli $led -brightness 255 -color 0,255,0 -status on
    echo "  设置 $led 为绿色亮起"
    sleep 1
done

echo
echo "=== 调试完成 ==="
