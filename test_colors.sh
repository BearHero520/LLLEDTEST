#!/bin/bash

# LLLED v3.0.0 颜色配置测试脚本
# 用于验证新的颜色方案是否正确实现

echo "=========================================="
echo "  LLLED v3.0.0 颜色配置测试"
echo "=========================================="

# 检查配置文件是否存在
CONFIG_FILE="/opt/ugreen-led-controller/config/led_mapping.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "⚠️  配置文件不存在: $CONFIG_FILE"
    echo "请先安装 LLLED 系统"
    exit 1
fi

echo "✅ 配置文件找到: $CONFIG_FILE"
echo ""

# 检查核心颜色配置
echo "🎨 检查核心颜色配置:"
echo "----------------------------------------"

# 读取配置文件
source "$CONFIG_FILE"

# 验证硬盘颜色配置
echo "硬盘状态颜色:"
echo "  活动状态: $DISK_COLOR_ACTIVE (应为: 255 255 255)"
echo "  休眠状态: $DISK_COLOR_STANDBY (应为: 128 128 128)" 
echo "  错误状态: $DISK_COLOR_ERROR (应为: 0 0 0)"

# 验证电源颜色配置
echo ""
echo "电源状态颜色:"
echo "  开机状态: $POWER_COLOR_ON (应为: 128 128 128)"
echo "  关机状态: $POWER_COLOR_OFF (应为: 0 0 0)"

# 检查守护进程脚本
echo ""
echo "🔧 检查守护进程默认配置:"
echo "----------------------------------------"

DAEMON_SCRIPT="/opt/ugreen-led-controller/scripts/led_daemon.sh"
if [[ -f "$DAEMON_SCRIPT" ]]; then
    echo "✅ 守护进程脚本存在"
    
    # 检查守护进程中的默认颜色
    if grep -q 'DISK_COLOR_ACTIVE="255 255 255"' "$DAEMON_SCRIPT"; then
        echo "✅ 守护进程活动颜色配置正确"
    else
        echo "❌ 守护进程活动颜色配置可能不正确"
    fi
    
    if grep -q 'DISK_COLOR_STANDBY="128 128 128"' "$DAEMON_SCRIPT"; then
        echo "✅ 守护进程休眠颜色配置正确"
    else
        echo "❌ 守护进程休眠颜色配置可能不正确"
    fi
    
    if grep -q 'DISK_COLOR_ERROR="0 0 0"' "$DAEMON_SCRIPT"; then
        echo "✅ 守护进程错误颜色配置正确"
    else
        echo "❌ 守护进程错误颜色配置可能不正确"
    fi
else
    echo "⚠️  守护进程脚本不存在: $DAEMON_SCRIPT"
fi

# 检查 HCTL 脚本
echo ""
echo "🔧 检查 HCTL 映射脚本:"
echo "----------------------------------------"

HCTL_SCRIPT="/opt/ugreen-led-controller/scripts/smart_disk_activity_hctl.sh"
if [[ -f "$HCTL_SCRIPT" ]]; then
    echo "✅ HCTL 脚本存在"
    
    # 检查 HCTL 脚本中的默认颜色
    if grep -q 'DISK_COLOR_ACTIVE="255 255 255"' "$HCTL_SCRIPT"; then
        echo "✅ HCTL 脚本活动颜色配置正确"
    else
        echo "❌ HCTL 脚本活动颜色配置可能不正确"
    fi
else
    echo "⚠️  HCTL 脚本不存在: $HCTL_SCRIPT"
fi

# 检查主控制器脚本
echo ""
echo "🔧 检查主控制器脚本:"
echo "----------------------------------------"

CONTROLLER_SCRIPT="/opt/ugreen-led-controller/ugreen_led_controller.sh"
if [[ -f "$CONTROLLER_SCRIPT" ]]; then
    echo "✅ 主控制器脚本存在"
    
    # 检查恢复系统 LED 功能
    if grep -q '"128 128 128"' "$CONTROLLER_SCRIPT"; then
        echo "✅ 主控制器电源LED恢复功能使用正确颜色"
    else
        echo "❌ 主控制器电源LED恢复功能颜色可能不正确"
    fi
else
    echo "⚠️  主控制器脚本不存在: $CONTROLLER_SCRIPT"
fi

echo ""
echo "=========================================="
echo "  测试完成"
echo "=========================================="

# 提供实际测试建议
echo ""
echo "💡 建议进行实际测试:"
echo "1. 重启LED服务: sudo systemctl restart ugreen-led-monitor"
echo "2. 运行主控制面板: sudo LLLED"
echo "3. 选择 '硬盘LED测试' 验证颜色显示"
echo "4. 检查各硬盘在不同状态下的颜色是否符合预期"
echo ""
echo "预期效果:"
echo "- 硬盘活动时显示亮白色"
echo "- 硬盘休眠时显示暗白色"  
echo "- 硬盘错误时LED关闭"
echo "- 电源LED显示暗白色(开机)或关闭(关机)"
