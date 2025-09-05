#!/bin/bash
# 紧急修复LLLED映射问题 v2.0.8

echo "=== 紧急修复LLLED映射问题 ==="

# 1. 检查当前安装的版本
echo "1. 检查当前版本："
if [[ -f /usr/local/bin/LLLED ]]; then
    head -n 10 /usr/local/bin/LLLED | grep "v2.0"
else
    echo "未找到LLLED程序"
    exit 1
fi

echo
echo "2. 备份当前程序："
cp /usr/local/bin/LLLED /usr/local/bin/LLLED.backup.$(date +%Y%m%d_%H%M%S)

echo
echo "3. 应用紧急修复："

# 修复detect_disk_mapping_fallback函数，确保不覆盖HCTL映射
sed -i '/detect_disk_mapping_fallback()/,/^}$/{
    /declare -gA DISK_LED_MAP/s/declare -gA DISK_LED_MAP/#declare -gA DISK_LED_MAP/
    /DISK_LED_MAP=(/s/DISK_LED_MAP=(/#DISK_LED_MAP=(/
}' /usr/local/bin/LLLED

echo "✓ 已禁用备用方法中的映射重置"

echo
echo "4. 测试修复结果："
echo "正在运行LLLED检测..."

# 运行检测
/usr/local/bin/LLLED --detect-only

echo
echo "5. 验证映射："
echo "现在运行完整的硬盘状态检测..."

/usr/local/bin/LLLED --disk-status

echo
echo "=== 修复完成 ==="
echo "如果映射仍然不正确，请运行："
echo "wget -O- https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash"
