#!/bin/bash

# 快速HCTL映射验证脚本
echo "=== HCTL强制映射测试 v2.0.4 ==="

# 模拟您的硬盘数据
declare -A test_mapping

# 测试HCTL映射逻辑
test_hctl_mapping() {
    local name="$1"
    local hctl="$2"
    local hctl_target=$(echo "$hctl" | cut -d: -f3)
    
    # 新的强制映射逻辑
    local led_number
    case "$hctl_target" in
        "0") led_number=1 ;;  # target 0 -> 槽位1 (disk1)
        "1") led_number=2 ;;  # target 1 -> 槽位2 (disk2)
        "2") led_number=3 ;;  # target 2 -> 槽位3 (disk3)  
        "3") led_number=4 ;;  # target 3 -> 槽位4 (disk4)
        *) led_number=$((hctl_target + 1)) ;;
    esac
    
    local target_led="disk${led_number}"
    test_mapping["$name"]="$target_led"
    
    echo "$name (HCTL: $hctl) -> HCTL target: $hctl_target -> $target_led"
}

echo "测试用户的实际硬盘配置："
test_hctl_mapping "sda" "0:0:0:0"
test_hctl_mapping "sdc" "2:0:0:0"
test_hctl_mapping "sdd" "3:0:0:0"

echo
echo "=== 映射结果 ==="
for disk in "${!test_mapping[@]}"; do
    echo "$disk -> ${test_mapping[$disk]}"
done

echo
echo "=== 期望的LED状态 ==="
echo "disk1: 亮 (对应sda，槽位1)"
echo "disk2: 不亮 (无硬盘)"
echo "disk3: 亮 (对应sdc，槽位3)"
echo "disk4: 亮 (对应sdd，槽位4)"

echo
echo "这样就能正确对应物理槽位了！"
