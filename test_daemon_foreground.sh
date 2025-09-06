#!/bin/bash

# 测试守护进程前台启动脚本
# 用于调试服务启动问题

echo "=== 守护进程前台测试启动 ==="
echo "时间: $(date)"
echo "用户: $(whoami)"
echo "工作目录: $(pwd)"
echo

# 设置环境变量
export SCRIPT_DIR="/opt/ugreen-led-controller"
export PATH="/opt/ugreen-led-controller:$PATH"

echo "环境设置:"
echo "  SCRIPT_DIR: $SCRIPT_DIR"
echo "  PATH: $PATH"
echo

# 检查必要文件
echo "检查必要文件:"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"
LED_DAEMON="$SCRIPT_DIR/scripts/led_daemon.sh"

echo "  LED控制程序: $UGREEN_CLI"
if [[ -x "$UGREEN_CLI" ]]; then
    echo "    ✓ 存在且可执行"
else
    echo "    ✗ 不存在或不可执行"
fi

echo "  LED守护进程: $LED_DAEMON"
if [[ -x "$LED_DAEMON" ]]; then
    echo "    ✓ 存在且可执行"
else
    echo "    ✗ 不存在或不可执行"
fi

echo

# 测试LED控制程序
echo "测试LED控制程序:"
echo "  执行: $UGREEN_CLI disk1 -status"
if "$UGREEN_CLI" disk1 -status 2>&1; then
    echo "    ✓ LED控制程序测试成功"
else
    echo "    ✗ LED控制程序测试失败"
fi

echo

# 启动守护进程（前台模式）
echo "启动守护进程（前台模式，详细日志）:"
echo "  执行命令: $LED_DAEMON _daemon_process"
echo "  使用 Ctrl+C 停止"
echo

# 使用stdbuf确保立即输出
exec stdbuf -oL -eL "$LED_DAEMON" _daemon_process
