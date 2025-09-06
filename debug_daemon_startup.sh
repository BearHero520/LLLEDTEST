#!/bin/bash

# LED守护进程启动调试脚本
# 用于诊断守护进程启动失败的原因

echo "=== LLLED守护进程启动诊断工具 ==="
echo

# 设置基本路径
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"
HCTL_SCRIPT="$SCRIPT_DIR/scripts/smart_disk_activity_hctl.sh"
LOG_FILE="/var/log/llled/ugreen-led-monitor.log"

echo "1. 检查LED控制程序..."
if [[ -x "$UGREEN_CLI" ]]; then
    echo "✓ LED控制程序存在: $UGREEN_CLI"
    
    # 测试LED控制程序
    echo "  测试LED控制程序..."
    if "$UGREEN_CLI" all -status >/dev/null 2>&1; then
        echo "✓ LED控制程序测试通过"
    else
        echo "✗ LED控制程序测试失败"
        echo "    错误详情:"
        "$UGREEN_CLI" all -status 2>&1 | sed 's/^/    /'
    fi
else
    echo "✗ LED控制程序不存在或不可执行: $UGREEN_CLI"
fi

echo
echo "2. 检查HCTL检测脚本..."
if [[ -x "$HCTL_SCRIPT" ]]; then
    echo "✓ HCTL脚本存在: $HCTL_SCRIPT"
    
    echo "  测试HCTL脚本执行..."
    if "$HCTL_SCRIPT" >/tmp/hctl_test.log 2>&1; then
        echo "✓ HCTL脚本执行成功"
        echo "    生成的配置文件:"
        if [[ -f "$CONFIG_DIR/hctl_mapping.conf" ]]; then
            echo "    ✓ $CONFIG_DIR/hctl_mapping.conf"
            echo "    配置内容预览:"
            head -10 "$CONFIG_DIR/hctl_mapping.conf" 2>/dev/null | sed 's/^/      /'
        else
            echo "    ✗ 配置文件未生成"
        fi
    else
        echo "✗ HCTL脚本执行失败"
        echo "    错误详情:"
        cat /tmp/hctl_test.log 2>/dev/null | sed 's/^/    /'
    fi
else
    echo "✗ HCTL脚本不存在或不可执行: $HCTL_SCRIPT"
fi

echo
echo "3. 检查配置目录..."
if [[ -d "$CONFIG_DIR" ]]; then
    echo "✓ 配置目录存在: $CONFIG_DIR"
    echo "  配置文件列表:"
    ls -la "$CONFIG_DIR" 2>/dev/null | sed 's/^/    /'
else
    echo "✗ 配置目录不存在: $CONFIG_DIR"
fi

echo
echo "4. 检查日志文件..."
if [[ -f "$LOG_FILE" ]]; then
    echo "✓ 日志文件存在: $LOG_FILE"
    echo "  最近的错误日志:"
    tail -20 "$LOG_FILE" 2>/dev/null | grep -E "(ERROR|WARN)" | tail -10 | sed 's/^/    /'
    echo
    echo "  最新的10行日志:"
    tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
else
    echo "✗ 日志文件不存在: $LOG_FILE"
fi

echo
echo "5. 检查系统权限..."
if [[ $(id -u) -eq 0 ]]; then
    echo "✓ 以root权限运行"
else
    echo "✗ 需要root权限运行"
fi

echo
echo "6. 检查systemd服务状态..."
systemctl status ugreen-led-monitor.service --no-pager -l | sed 's/^/  /'

echo
echo "7. 手动测试守护进程启动..."
echo "  尝试直接启动守护进程（前台模式）:"
echo "  执行命令: $SCRIPT_DIR/scripts/led_daemon.sh _daemon_process"
echo "  注意：这将在前台运行，使用Ctrl+C停止"
echo

# 提供手动测试选项
read -p "是否立即测试守护进程前台启动？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "启动守护进程（前台模式）..."
    "$SCRIPT_DIR/scripts/led_daemon.sh" _daemon_process
fi

echo
echo "=== 诊断完成 ==="
