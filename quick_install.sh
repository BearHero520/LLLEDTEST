#!/bin/bash

# 绿联LED控制工具 - 一键安装脚本
# 版本: 3.0.0
# 更新时间: 2025-09-06
# 唯一安装入口: 本脚本是LLLED系统的唯一安装方式

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLEDTEST"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"
LOG_DIR="/var/log/llled"

# 全局版本号
LLLED_VERSION="3.0.6"

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
echo -e "${CYAN}LLLED 一键安装工具 v${LLLED_VERSION}${NC}"
echo -e "${CYAN}================================${NC}"
echo "更新时间: 2025-09-06"
echo -e "${BLUE}新增功能:${NC}"
echo "  • 全局版本号管理"
echo "  • HCTL硬盘位置映射全局配置化"
echo "  • 智能颜色配置(电源/网络/硬盘)"
echo "  • 增强的后台服务管理"
echo "  • 自动硬盘状态检测与重映射"
echo
echo -e "${YELLOW}支持的UGREEN设备:${NC}"
for model in "${SUPPORTED_MODELS[@]}"; do
    echo "  - $model"
done
echo
echo "正在安装..."

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log_install() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INSTALL] $1" | tee -a "$LOG_DIR/install.log"
}

# 清理旧版本
cleanup_old_version() {
    log_install "检查并清理旧版本..."
    
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
log_install "安装必要依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y wget curl i2c-tools smartmontools bc sysstat util-linux lsblk hdparm -qq
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget curl i2c-tools smartmontools bc sysstat util-linux lsblk hdparm -q
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget curl i2c-tools smartmontools bc sysstat util-linux lsblk hdparm -q
else
    log_install "WARNING: 请手动安装: wget curl i2c-tools smartmontools bc sysstat util-linux"
fi

# 加载i2c模块
modprobe i2c-dev 2>/dev/null

# 创建安装目录并下载文件
log_install "创建目录结构..."
mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
mkdir -p "$LOG_DIR"
cd "$INSTALL_DIR"

log_install "下载LLLED v$LLLED_VERSION文件..."
files=(
    "ugreen_led_controller.sh"
    "ugreen_led_controller_optimized.sh"
    "uninstall.sh"
    "verify_detection.sh"
    "ugreen_leds_cli"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/smart_disk_activity_hctl.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/led_test.sh"
    "scripts/configure_mapping.sh"
    "scripts/configure_mapping_optimized.sh"
    "scripts/led_daemon.sh"
    "config/global_config.conf"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
    "config/hctl_mapping.conf"
    "systemd/ugreen-led-monitor.service"
)

# 添加时间戳防止缓存
TIMESTAMP=$(date +%s)
log_install "时间戳: $TIMESTAMP (防缓存)"

download_success=0
download_total=${#files[@]}

for file in "${files[@]}"; do
    echo -n "下载: $file ... "
    # 添加时间戳参数防止缓存，并禁用缓存
    if wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
        echo -e "${GREEN}✓${NC}"
        ((download_success++))
    else
        echo -e "${RED}✗${NC}"
        log_install "WARNING: 无法下载 $file"
    fi
done

log_install "下载完成: $download_success/$download_total 文件成功"

# 验证核心文件
log_install "验证核心文件..."
core_files=("ugreen_leds_cli" "scripts/led_daemon.sh" "scripts/smart_disk_activity_hctl.sh" "config/global_config.conf")
missing_files=()

for file in "${core_files[@]}"; do
    if [[ ! -f "$file" || ! -s "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_install "ERROR: 关键文件缺失: ${missing_files[*]}"
    echo -e "${RED}安装失败：关键文件下载失败${NC}"
    echo "缺失文件："
    for file in "${missing_files[@]}"; do
        echo "  - $file"
    done
    echo
    echo "请检查网络连接或手动下载文件"
    exit 1
fi

# 验证LED控制程序
log_install "验证LED控制程序..."
if [[ -f "ugreen_leds_cli" && -s "ugreen_leds_cli" ]]; then
    log_install "SUCCESS: LED控制程序下载成功"
else
    log_install "ERROR: LED控制程序下载失败"
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
log_install "设置文件权限..."
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接 - 优先使用新版本
log_install "创建命令链接..."
if [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    log_install "SUCCESS: LLLED命令创建成功 (v$LLLED_VERSION)"
else
    log_install "ERROR: 主控制脚本未找到"
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 初始化HCTL映射
log_install "初始化HCTL硬盘映射..."
if [[ -x "scripts/smart_disk_activity_hctl.sh" ]]; then
    log_install "执行初始HCTL检测..."
    if "scripts/smart_disk_activity_hctl.sh" --update-mapping --save-config; then
        log_install "SUCCESS: HCTL映射初始化成功"
    else
        log_install "WARNING: HCTL映射初始化失败，将在首次运行时重试"
    fi
else
    log_install "WARNING: HCTL脚本不存在，跳过初始化"
fi

# 安装systemd服务
log_install "安装systemd服务..."
if [[ -f "systemd/ugreen-led-monitor.service" ]]; then
    cp "systemd/ugreen-led-monitor.service" /etc/systemd/system/
    systemctl daemon-reload
    log_install "SUCCESS: Systemd服务已安装"
else
    log_install "WARNING: Systemd服务文件不存在，手动创建..."
    # 创建服务文件
    cat > /etc/systemd/system/ugreen-led-monitor.service << EOF
[Unit]
Description=LLLED智能LED监控服务 v$LLLED_VERSION
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/scripts/led_daemon.sh start
ExecStop=$INSTALL_DIR/scripts/led_daemon.sh stop
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    log_install "SUCCESS: 手动创建Systemd服务成功"
fi

log_install "LLLED v$LLLED_VERSION 安装完成！"

# 显示完成信息
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🎉 LLLED v$LLLED_VERSION 安装完成！         ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  使用命令: sudo LLLED                 ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  🆕 新增功能:                         ║${NC}"
echo -e "${CYAN}║  ✨ 全局版本号管理                    ║${NC}"
echo -e "${CYAN}║  � HCTL硬盘智能映射                  ║${NC}"
echo -e "${CYAN}║  🎨 智能颜色配置                      ║${NC}"
echo -e "${CYAN}║  🚀 增强后台服务                      ║${NC}"
echo -e "${CYAN}║  🔄 自动硬盘状态检测                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"

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
echo -e "${CYAN}📖 使用说明${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "${GREEN}使用命令: sudo LLLED${NC}        # �️ LED控制面板"
echo ""
echo -e "${YELLOW}项目地址: https://github.com/${GITHUB_REPO}${NC}"
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🎉 安装完成！立即使用 sudo LLLED     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
