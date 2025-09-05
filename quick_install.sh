#!/bin/bash

# 绿联LED控制工具 - 一键安装脚本 (增强版)
# 版本: 2.1.0 (集成颜色自定义功能)
# 更新时间: 2025-09-06
# 唯一安装入口: 本脚本是LLLED系统的唯一安装方式

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLEDTEST"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"

# 支持的UGREEN设备列表
SUPPORTED_MODELS=(
    "UGREEN DX4600 Pro"
    "UGREEN DX4700+"
    "UGREEN DXP2800"
    "UGREEN DXP4800"
    "UGREEN DXP4800 Plus"
    "UGREEN DXP6800 Pro" 
    "UGREEN DXP8800 Plus"
)

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}LLLED 一键安装工具 v2.1.0${NC}"
echo -e "${CYAN}(增强版 - 颜色自定义+智能监控)${NC}"
echo -e "${CYAN}================================${NC}"
echo "更新时间: 2025-09-06"
echo -e "${YELLOW}⚠️  注意: 这是LLLED系统的唯一安装入口${NC}"
echo
echo -e "${YELLOW}支持的UGREEN设备:${NC}"
for model in "${SUPPORTED_MODELS[@]}"; do
    echo "  - $model"
done
echo
echo "正在安装..."

# 清理旧版本
cleanup_old_version() {
    echo "检查并清理旧版本..."
    
    # 停止可能运行的服务
    systemctl stop ugreen-led-monitor.service 2>/dev/null || true
    systemctl disable ugreen-led-monitor.service 2>/dev/null || true
    
    # 删除旧的服务文件
    rm -f /etc/systemd/system/ugreen-led-monitor.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # 删除旧的命令链接
    rm -f /usr/local/bin/LLLED 2>/dev/null || true
    rm -f /usr/bin/LLLED 2>/dev/null || true
    rm -f /bin/LLLED 2>/dev/null || true
    
    # 备份旧的配置文件（如果存在）
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "发现旧版本，正在备份配置..."
        backup_dir="/tmp/llled-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # 备份配置文件
        if [[ -d "$INSTALL_DIR/config" ]]; then
            cp -r "$INSTALL_DIR/config" "$backup_dir/" 2>/dev/null || true
            echo "配置已备份到: $backup_dir"
        fi
        
        # 删除旧安装目录
        rm -rf "$INSTALL_DIR"
    fi
    
    echo "旧版本清理完成"
}

# 执行清理
cleanup_old_version

# 安装依赖
echo "安装必要依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y wget i2c-tools smartmontools bc sysstat util-linux -qq
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget i2c-tools smartmontools bc sysstat util-linux -q
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget i2c-tools smartmontools bc sysstat util-linux -q
else
    echo -e "${YELLOW}请手动安装: wget i2c-tools smartmontools bc sysstat util-linux${NC}"
fi

# 加载i2c模块
modprobe i2c-dev 2>/dev/null

# 创建安装目录并下载文件
echo "创建目录..."
mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
cd "$INSTALL_DIR"

echo "下载主程序..."
files=(
    "ugreen_led_controller_optimized.sh"
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "verify_detection.sh"
    "ugreen_leds_cli"
    "llled-quick.sh"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/led_test.sh"
    "scripts/configure_mapping.sh"
    "scripts/configure_mapping_optimized.sh"
    "scripts/color_menu.sh"
    "scripts/smart_status_monitor.sh"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
)

# 添加时间戳防止缓存
TIMESTAMP=$(date +%s)
echo "时间戳: $TIMESTAMP (防缓存)"

for file in "${files[@]}"; do
    echo "下载: $file"
    # 添加时间戳参数防止缓存，并禁用缓存
    if ! wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
        echo -e "${YELLOW}警告: 无法下载 $file${NC}"
    fi
done

# 验证LED控制程序
echo "验证LED控制程序..."
if [[ -f "ugreen_leds_cli" && -s "ugreen_leds_cli" ]]; then
    echo -e "${GREEN}✓ LED控制程序下载成功${NC}"
else
    echo -e "${RED}错误: LED控制程序下载失败${NC}"
    echo "正在创建临时解决方案..."
    
    # 创建一个临时的LED控制程序提示
    cat > "ugreen_leds_cli" << 'EOF'
#!/bin/bash
echo "LED控制程序未正确安装"
echo "请手动下载: https://github.com/miskcoo/ugreen_leds_controller/releases"
echo "下载后放置到: /opt/ugreen-led-controller/ugreen_leds_cli"
exit 1
EOF
    
    echo -e "${YELLOW}已创建临时文件，请手动下载LED控制程序${NC}"
fi

# 设置权限
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接 - 使用优化版本
if [[ -f "$INSTALL_DIR/ugreen_led_controller_optimized.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller_optimized.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功 (优化版)${NC}"
    
    # 如果优化版本不存在，回退到标准版本
elif [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功 (标准版)${NC}"
else
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 创建快捷命令
if [[ -f "$INSTALL_DIR/llled-quick.sh" ]]; then
    ln -sf "$INSTALL_DIR/llled-quick.sh" /usr/local/bin/llled-menu
    echo -e "${GREEN}✓ LLLED快捷菜单命令创建成功${NC}"
fi

echo -e "${GREEN}✓ 安装完成！${NC}"

# 显示主入口信息
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            🎉 安装完成！               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📍 主入口命令:${NC}"
echo -e "${GREEN}   sudo llled-menu${NC}  # 🎨 颜色配置 + LED控制 (推荐)"
echo -e "${GREEN}   sudo LLLED${NC}       # 🔧 完整LLLED系统"
echo ""
echo -e "${CYAN}🎨 全新颜色配置功能:${NC}"
echo "   • 自定义电源、网络、硬盘LED颜色"
echo "   • 支持4种状态模式:"
echo "     🟢 活动状态: 绿色高亮 (正在工作)"
echo "     🟡 空闲状态: 黄色低亮 (待机)"
echo "     🔴 错误状态: 红色闪烁 (故障)"  
echo "     ⚫ 离线状态: 灯光关闭 (未检测到)"
echo "   • 实时颜色预览和状态演示"
echo "   • 智能状态监控"
echo ""
echo -e "${BLUE}🚀 快速开始:${NC}"
echo -e "   sudo llled-menu          # 打开功能菜单"
echo -e "   sudo llled-menu color    # 直接进入颜色配置"
echo -e "   sudo llled-menu monitor  # 启动智能监控"

# 最终验证
echo -e "\n${CYAN}================================${NC}"
echo -e "${CYAN}安装验证${NC}"
echo -e "${CYAN}================================${NC}"
echo "安装目录: $INSTALL_DIR"
echo "优化版主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller_optimized.sh" 2>/dev/null || echo "未找到")"
echo "标准版主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"
echo

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}📖 详细使用说明${NC}"
echo -e "${CYAN}================================${NC}"
echo ""
echo -e "${YELLOW}🎯 主入口命令 (推荐):${NC}"
echo -e "${GREEN}   sudo llled-menu${NC}              # 打开LLLED功能菜单"
echo -e "${GREEN}   sudo llled-menu color${NC}        # 直接进入颜色配置"
echo -e "${GREEN}   sudo llled-menu monitor${NC}      # 启动智能监控"
echo -e "${GREEN}   sudo llled-menu status${NC}       # 查看当前状态"
echo ""
echo -e "${YELLOW}🔧 传统命令:${NC}"
echo "   sudo LLLED                     # LLLED主程序"
echo "   sudo LLLED --disk-status       # 智能硬盘状态"
echo "   sudo LLLED --monitor           # 实时监控"
echo "   sudo LLLED --mapping           # 显示映射"
echo ""
echo -e "${YELLOW}🎨 颜色配置 (新功能):${NC}"
echo "   sudo bash /opt/ugreen-led-controller/scripts/color_menu.sh"
echo "   ↳ 完整的LED颜色自定义界面"
echo "   ↳ 支持电源键、网络、硬盘LED分别设置"
echo "   ↳ 13种预设颜色 + 自定义RGB"
echo "   ↳ 实时颜色预览功能"
echo ""
echo -e "${YELLOW}🤖 智能监控:${NC}"
echo "   sudo bash /opt/ugreen-led-controller/scripts/smart_status_monitor.sh"
echo "   ↳ 基于用户颜色配置的智能状态显示"
echo "   ↳ 自动检测设备状态并更新LED颜色"
echo "   ↳ 支持网络活动、硬盘读写、系统负载监控"
echo ""
echo -e "${YELLOW}🔍 设备检测:${NC}"
echo "   sudo bash /opt/ugreen-led-controller/verify_detection.sh"
echo "   ↳ 验证设备兼容性和HCTL映射"
echo

echo -e "${YELLOW}项目地址: https://github.com/${GITHUB_REPO}${NC}"
echo -e "${YELLOW}如有问题，请查看项目文档或提交Issue${NC}"
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🎉 LLLED v2.1.0 安装完成！           ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  主入口命令: sudo llled-menu           ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  立即体验全新的LED颜色自定义功能！     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
