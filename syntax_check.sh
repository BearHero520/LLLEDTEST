#!/bin/bash

# 语法检查脚本
echo "=== LLLED脚本语法检查 ==="

# 检查主脚本
echo "检查主脚本语法..."
if bash -n ugreen_led_controller_optimized.sh 2>/dev/null; then
    echo "✓ 主脚本语法正确"
else
    echo "✗ 主脚本语法错误:"
    bash -n ugreen_led_controller_optimized.sh
fi

echo
echo "检查安装脚本语法..."
if bash -n quick_install.sh 2>/dev/null; then
    echo "✓ 安装脚本语法正确"
else
    echo "✗ 安装脚本语法错误:"
    bash -n quick_install.sh
fi

echo
echo "检查诊断脚本语法..."
if bash -n debug_mapping.sh 2>/dev/null; then
    echo "✓ 诊断脚本语法正确"
else
    echo "✗ 诊断脚本语法错误:"
    bash -n debug_mapping.sh
fi

echo
echo "语法检查完成"
