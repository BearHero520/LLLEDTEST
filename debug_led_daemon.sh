#!/bin/bash
# LED守护进程调试脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ugreen-led-daemon.log"

echo "=== LED守护进程调试工具 ==="
echo "日志文件: $LOG_FILE"
echo

# 检查守护进程状态
echo "1. 检查守护进程状态:"
if systemctl is-active --quiet ugreen-led-monitor; then
    echo "   ✓ LED守护进程正在运行"
    echo "   PID: $(systemctl show -p MainPID --value ugreen-led-monitor)"
else
    echo "   ✗ LED守护进程未运行"
fi
echo

# 检查LED映射配置
echo "2. 检查LED映射配置:"
config_file="/opt/ugreen-led-controller/config/led_mapping.conf"
if [[ -f "$config_file" ]]; then
    echo "   ✓ 配置文件存在: $config_file"
    echo "   内容:"
    cat "$config_file" | sed 's/^/     /'
else
    echo "   ✗ 配置文件不存在: $config_file"
fi
echo

# 测试硬盘状态检测
echo "3. 测试硬盘状态检测:"
for disk in sda sdb sdc sdd; do
    if [[ -b "/dev/$disk" ]]; then
        echo "   测试硬盘: $disk"
        echo -n "     hdparm输出: "
        hdparm_output=$(timeout 5 hdparm -C "/dev/$disk" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$hdparm_output" | grep "drive state is:" | cut -d':' -f2 | xargs
        else
            echo "超时或错误"
        fi
    fi
done
echo

# 查看最近的日志
echo "4. 最近的守护进程日志 (最后20行):"
if [[ -f "$LOG_FILE" ]]; then
    tail -20 "$LOG_FILE" | sed 's/^/   /'
else
    echo "   日志文件不存在"
fi
echo

# 手动测试LED控制
echo "5. 手动测试LED控制:"
echo "   测试 disk1 LED 白色..."
ugreen_leds_cli disk1 -color 255 255 255 -brightness 100 -on
sleep 2

echo "   测试 disk1 LED 淡白色..."
ugreen_leds_cli disk1 -color 128 128 128 -brightness 50 -on
sleep 2

echo "   关闭 disk1 LED..."
ugreen_leds_cli disk1 -off
echo

echo "=== 调试完成 ==="
echo "如需重启守护进程: sudo systemctl restart ugreen-led-monitor"
echo "如需查看实时日志: sudo journalctl -f -u ugreen-led-monitor"
