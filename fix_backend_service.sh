#!/bin/bash

# LLLED 后台服务修复测试脚本
# 用于验证修复后的后台服务功能

echo "LLLED 后台服务修复测试"
echo "========================"

echo "1. 重新安装服务（启用开机自启）..."
if systemctl stop ugreen-led-monitor 2>/dev/null; then
    echo "   已停止旧服务"
fi

if systemctl disable ugreen-led-monitor 2>/dev/null; then
    echo "   已禁用旧服务"
fi

# 创建新的服务文件
cat > /etc/systemd/system/ugreen-led-monitor.service << EOF
[Unit]
Description=LLLED智能LED监控服务 v3.0.0
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=/opt/ugreen-led-controller/scripts/led_daemon.sh start
ExecStop=/opt/ugreen-led-controller/scripts/led_daemon.sh stop
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "2. 重新加载systemd配置..."
systemctl daemon-reload

echo "3. 启用开机自启..."
if systemctl enable ugreen-led-monitor; then
    echo "   ✓ 开机自启已启用"
else
    echo "   ✗ 开机自启启用失败"
fi

echo "4. 启动服务..."
if systemctl start ugreen-led-monitor; then
    echo "   ✓ 服务启动成功"
else
    echo "   ✗ 服务启动失败"
fi

echo "5. 检查服务状态..."
systemctl status ugreen-led-monitor --no-pager -l

echo "6. 检查开机自启状态..."
if systemctl is-enabled ugreen-led-monitor >/dev/null 2>&1; then
    echo "   ✓ 开机自启已启用"
else
    echo "   ✗ 开机自启未启用"
fi

echo ""
echo "修复完成！现在重启系统后服务应该会自动启动。"
echo "可以使用以下命令查看服务日志："
echo "  journalctl -u ugreen-led-monitor -f"
