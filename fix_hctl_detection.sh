#!/bin/bash

# LLLED v3.0.0 HCTL硬盘检测修复脚本
# 修复LED检测和硬盘状态显示的问题

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  LLLED v3.0.0 HCTL硬盘检测修复${NC}"
echo -e "${CYAN}========================================${NC}"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限运行此修复脚本${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 定义路径
INSTALL_DIR="/opt/ugreen-led-controller"
BACKUP_DIR="/tmp/llled-backup-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${RED}LLLED未安装或安装路径不正确${NC}"
    echo "请先运行: wget -O - https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash"
    exit 1
fi

echo -e "${CYAN}创建备份...${NC}"
mkdir -p "$BACKUP_DIR"
cp -r "$INSTALL_DIR" "$BACKUP_DIR/" 2>/dev/null
echo -e "${GREEN}✓ 备份已创建: $BACKUP_DIR${NC}"

echo -e "\n${CYAN}下载最新版本的修复文件...${NC}"

# 下载修复后的主要文件
files_to_update=(
    "ugreen_led_controller.sh"
    "scripts/smart_disk_activity_hctl.sh"
    "scripts/led_test.sh"
    "scripts/turn_off_all_leds.sh"
)

cd "$INSTALL_DIR"

for file in "${files_to_update[@]}"; do
    echo "更新 $file..."
    if wget -q "https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/$file" -O "$file.new"; then
        mv "$file.new" "$file"
        chmod +x "$file"
        echo -e "${GREEN}✓ $file 更新成功${NC}"
    else
        echo -e "${YELLOW}⚠ $file 更新失败，使用现有版本${NC}"
    fi
done

echo -e "\n${CYAN}验证修复效果...${NC}"

# 测试LED控制程序
if [[ -x "$INSTALL_DIR/ugreen_leds_cli" ]]; then
    echo -e "${GREEN}✓ LED控制程序存在${NC}"
    
    # 测试基本功能
    if "$INSTALL_DIR/ugreen_leds_cli" all -status >/dev/null 2>&1; then
        echo -e "${GREEN}✓ LED控制程序可以正常工作${NC}"
    else
        echo -e "${YELLOW}⚠ LED控制程序可能需要加载i2c模块${NC}"
        echo "尝试加载i2c-dev模块..."
        modprobe i2c-dev 2>/dev/null
    fi
else
    echo -e "${RED}✗ LED控制程序不存在${NC}"
fi

# 测试HCTL脚本
if [[ -x "$INSTALL_DIR/scripts/smart_disk_activity_hctl.sh" ]]; then
    echo -e "${GREEN}✓ HCTL硬盘检测脚本存在${NC}"
else
    echo -e "${RED}✗ HCTL硬盘检测脚本不存在${NC}"
fi

echo -e "\n${CYAN}修复说明:${NC}"
echo "1. 修复了LED检测的正则表达式问题"
echo "2. 修复了硬盘状态显示调用错误的脚本"
echo "3. 确保HCTL检测不依赖LED状态"
echo "4. 添加了默认LED配置的备用方案"

echo -e "\n${CYAN}测试修复效果:${NC}"
echo "现在可以测试以下功能："
echo "1. 运行主控制面板: sudo LLLED"
echo "2. 选择 '硬盘设置' -> '1. 智能硬盘状态显示'"
echo "3. 或直接运行: sudo $INSTALL_DIR/scripts/smart_disk_activity_hctl.sh"

echo -e "\n${CYAN}预期结果:${NC}"
echo "- 应该能检测到您的硬盘 (通过HCTL)"
echo "- 应该能正确映射硬盘到LED"
echo "- 不应该因为LED检测失败而停止"

echo -e "\n${GREEN}修复完成！${NC}"
echo -e "${YELLOW}如果还有问题，请检查:${NC}"
echo "1. 硬件是否支持 (UGREEN NAS)"
echo "2. i2c-dev模块是否正确加载"
echo "3. 是否有root权限"

echo -e "\n备份位置: $BACKUP_DIR"
echo "如需恢复，可以: sudo cp -r $BACKUP_DIR/ugreen-led-controller/* $INSTALL_DIR/"
