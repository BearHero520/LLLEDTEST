#!/bin/bash

# LLLED 智能监控修复验证脚本
# 用于测试智能状态监控脚本的算术运算问题

echo "=== LLLED 智能监控修复验证 ==="
echo ""

# 测试网络流量统计
echo "1. 测试网络流量统计..."
rx_bytes=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum}')
tx_bytes=$(cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum}')

echo "   RX bytes: $rx_bytes"
echo "   TX bytes: $tx_bytes"

# 验证数字格式
if [[ "$rx_bytes" =~ ^[0-9]+$ ]]; then
    echo "   ✓ RX bytes 格式正确"
else
    echo "   ✗ RX bytes 格式错误: $rx_bytes"
fi

if [[ "$tx_bytes" =~ ^[0-9]+$ ]]; then
    echo "   ✓ TX bytes 格式正确"
else
    echo "   ✗ TX bytes 格式错误: $tx_bytes"
fi

# 测试算术运算
echo ""
echo "2. 测试算术运算..."
if [[ -n "$rx_bytes" && -n "$tx_bytes" ]]; then
    total=$((rx_bytes + tx_bytes))
    echo "   总流量: $total bytes"
    echo "   ✓ 算术运算成功"
else
    echo "   ✗ 无法进行算术运算"
fi

# 测试系统负载检测
echo ""
echo "3. 测试系统负载检测..."
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
echo "   当前负载: $load_avg"

load_level=$(echo "$load_avg" | awk '{if($1 > 2.0) print 1; else print 0}')
echo "   负载等级: $load_level (1=高负载, 0=低负载)"
echo "   ✓ 负载检测成功"

# 测试硬盘统计
echo ""
echo "4. 测试硬盘统计..."
for disk in /sys/block/sd*; do
    if [[ -d "$disk" ]]; then
        disk_name=$(basename "$disk")
        stats_file="$disk/stat"
        if [[ -f "$stats_file" ]]; then
            read_ops=$(awk '{print $1}' "$stats_file")
            write_ops=$(awk '{print $5}' "$stats_file")
            echo "   $disk_name: 读操作=$read_ops, 写操作=$write_ops"
            
            if [[ "$read_ops" =~ ^[0-9]+$ ]] && [[ "$write_ops" =~ ^[0-9]+$ ]]; then
                echo "     ✓ $disk_name 统计格式正确"
            else
                echo "     ✗ $disk_name 统计格式错误"
            fi
        fi
    fi
done

# 测试智能监控脚本
echo ""
echo "5. 测试智能监控脚本..."
monitor_script="/opt/ugreen-led-controller/scripts/smart_status_monitor.sh"

if [[ -f "$monitor_script" ]]; then
    echo "   智能监控脚本存在"
    
    # 测试语法
    if bash -n "$monitor_script"; then
        echo "   ✓ 脚本语法检查通过"
        
        # 测试一次性运行
        echo "   正在测试一次性状态更新..."
        if timeout 10 bash "$monitor_script" -o -v; then
            echo "   ✓ 一次性运行测试成功"
        else
            echo "   ✗ 一次性运行测试失败"
        fi
    else
        echo "   ✗ 脚本语法检查失败"
    fi
else
    echo "   ✗ 智能监控脚本不存在"
fi

echo ""
echo "=== 验证完成 ==="

# 提供修复建议
echo ""
echo "如果发现问题，请尝试："
echo "1. 重新安装LLLED系统："
echo "   curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash"
echo ""
echo "2. 或手动更新智能监控脚本"
echo ""
echo "3. 如果问题持续，请提交Issue到GitHub项目页面"
