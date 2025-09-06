#!/bin/bash

# LED控制诊断脚本
# 用于测试不同LED的控制能力

UGREEN_CLI="/opt/ugreen-led-controller/ugreen_leds_cli"

echo "=== LED控制诊断脚本 ==="
echo "时间: $(date)"
echo "控制程序: $UGREEN_CLI"
echo

# 检查控制程序
if [[ ! -x "$UGREEN_CLI" ]]; then
    echo "错误: LED控制程序不可用"
    exit 1
fi

echo "1. 获取所有LED状态..."
"$UGREEN_CLI" all -status
echo

echo "2. 测试硬盘LED控制 (已知工作)..."
echo "   测试disk1..."
if "$UGREEN_CLI" disk1 -color "255 0 0" -brightness 64 -on; then
    echo "   ✓ disk1 控制成功"
    sleep 1
    "$UGREEN_CLI" disk1 -off
    echo "   ✓ disk1 关闭成功"
else
    echo "   ✗ disk1 控制失败"
fi
echo

echo "3. 测试电源LED控制..."
echo "   方法1: power -on"
if "$UGREEN_CLI" power -on; then
    echo "   ✓ power -on 成功"
else
    echo "   ✗ power -on 失败"
fi

echo "   方法2: power -color RGB -on"
if "$UGREEN_CLI" power -color "128 128 128" -on; then
    echo "   ✓ power -color RGB -on 成功"
else
    echo "   ✗ power -color RGB -on 失败"
fi

echo "   方法3: power -color RGB -on -brightness N (硬盘LED格式)"
if "$UGREEN_CLI" power -color "128 128 128" -on -brightness 64; then
    echo "   ✓ power -color RGB -on -brightness N 成功"
else
    echo "   ✗ power -color RGB -on -brightness N 失败"
fi

echo "   方法4: power -color RGB -brightness N -on"
if "$UGREEN_CLI" power -color "128 128 128" -brightness 64 -on; then
    echo "   ✓ power -color RGB -brightness N -on 成功"
else
    echo "   ✗ power -color RGB -brightness N -on 失败"
fi

echo "   方法5: power -off"
if "$UGREEN_CLI" power -off; then
    echo "   ✓ power -off 成功"
else
    echo "   ✗ power -off 失败"
fi
echo

echo "4. 测试网络LED控制..."
echo "   方法1: netdev -on"
if "$UGREEN_CLI" netdev -on; then
    echo "   ✓ netdev -on 成功"
else
    echo "   ✗ netdev -on 失败"
fi

echo "   方法2: netdev -color RGB -on"
if "$UGREEN_CLI" netdev -color "0 0 255" -on; then
    echo "   ✓ netdev -color RGB -on 成功"
else
    echo "   ✗ netdev -color RGB -on 失败"
fi

echo "   方法3: netdev -color RGB -brightness N -on"
if "$UGREEN_CLI" netdev -color "0 0 255" -brightness 64 -on; then
    echo "   ✓ netdev -color RGB -brightness N -on 成功"
else
    echo "   ✗ netdev -color RGB -brightness N -on 失败"
fi

echo "   方法4: netdev -off"
if "$UGREEN_CLI" netdev -off; then
    echo "   ✓ netdev -off 成功"
else
    echo "   ✗ netdev -off 失败"
fi
echo

echo "5. 测试all命令..."
echo "   all -on"
if "$UGREEN_CLI" all -on; then
    echo "   ✓ all -on 成功"
    sleep 2
else
    echo "   ✗ all -on 失败"
fi

echo "   all -off"
if "$UGREEN_CLI" all -off; then
    echo "   ✓ all -off 成功"
else
    echo "   ✗ all -off 失败"
fi
echo

echo "6. 检查LED是否在状态中显示..."
echo "获取当前状态:"
"$UGREEN_CLI" all -status | grep -E "(power|netdev)"

echo
echo "=== 诊断完成 ==="
echo "请查看以上结果，确定哪些LED控制方法有效"
