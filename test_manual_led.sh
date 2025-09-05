#!/bin/bash
# 检查LLLED程序内部变量状态

echo "=== 检查LLLED程序内部变量状态 ==="

# 1. 运行LLLED检测并输出详细信息
echo "1. 运行LLLED检测（只检测部分）："
echo "正在执行: sudo LLLED --disk-status"
echo

# 2. 手动测试正确的LED控制
echo "2. 手动测试正确的LED映射："

echo "关闭所有硬盘LED..."
for i in {1..4}; do
    /opt/ugreen-led-controller/ugreen_leds_cli disk$i -off
done

echo
echo "按照正确映射点亮LED："

echo "sda (HCTL: 0:0:0:0) -> disk1 (绿色)"
/opt/ugreen-led-controller/ugreen_leds_cli disk1 -color 0 255 0 -on -brightness 255

echo "sdc (HCTL: 2:0:0:0) -> disk3 (蓝色)" 
/opt/ugreen-led-controller/ugreen_leds_cli disk3 -color 0 100 255 -on -brightness 255

echo "sdd (HCTL: 3:0:0:0) -> disk4 (黄色)"
/opt/ugreen-led-controller/ugreen_leds_cli disk4 -color 255 255 0 -on -brightness 255

echo
echo "现在请查看您的NAS硬盘LED："
echo "- 槽位1应该亮绿色 (对应sda)"
echo "- 槽位2应该关闭"
echo "- 槽位3应该亮蓝色 (对应sdc)"
echo "- 槽位4应该亮黄色 (对应sdd)"
echo

read -p "LED是否按预期亮起？(y/n): " led_response

if [[ "$led_response" =~ ^[Yy] ]]; then
    echo "✓ LED硬件控制正常，问题在于程序映射逻辑"
else
    echo "✗ LED硬件控制异常，需要检查硬件连接或驱动"
fi

echo
echo "=== 检查完成 ==="
