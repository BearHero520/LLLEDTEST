#!/bin/bash

# 测试硬盘热插拔检测功能
echo "=== 硬盘热插拔检测测试 ==="

# 检查当前硬盘数量
echo "当前检测到的硬盘设备："
for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
    if [[ -b "$disk" ]]; then
        echo "  $disk"
    fi
done

echo
echo "SATA设备："
ls -la /dev/sd[a-z] 2>/dev/null | wc -l
echo "个SATA设备"

echo
echo "NVMe设备："
ls -la /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l
echo "个NVMe设备"

echo
echo "监控硬盘变化（按Ctrl+C停止）..."
previous_count=$(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l)
echo "初始硬盘数量: $previous_count"

while true; do
    current_count=$(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l)
    if [[ $current_count -ne $previous_count ]]; then
        echo "$(date): 硬盘数量变化: $previous_count -> $current_count"
        echo "当前硬盘列表："
        ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] 2>/dev/null
        previous_count=$current_count
    fi
    sleep 2
done
