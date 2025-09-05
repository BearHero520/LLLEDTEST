#!/bin/bash

# UGREEN LED 后台服务自动安装脚本
# 自动检测、下载并配置systemd服务

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
INSTALL_DIR="/opt/ugreen-led-controller"
SERVICE_NAME="ugreen-led-monitor"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_RAW="https://raw.githubusercontent.com/BearHero520/LLLED/main"

# 打印带颜色的消息
print_status() {
    echo -e "${CYAN}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查安装目录
check_install_dir() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "LLLED未安装，安装目录不存在: $INSTALL_DIR"
        print_status "请先运行: wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh | sudo bash"
        exit 1
    fi
    print_success "找到LLLED安装目录: $INSTALL_DIR"
}

# 检查并下载缺失文件
download_missing_files() {
    local missing_files=()
    
    # 检查systemd服务文件
    if [[ ! -f "$INSTALL_DIR/systemd/ugreen-led-monitor.service" ]]; then
        missing_files+=("systemd/ugreen-led-monitor.service")
    fi
    
    # 检查守护脚本
    if [[ ! -f "$INSTALL_DIR/scripts/led_daemon.sh" ]]; then
        missing_files+=("scripts/led_daemon.sh")
    fi
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        print_success "所有必需文件已存在"
        return 0
    fi
    
    print_warning "发现缺失文件，正在下载..."
    
    # 创建必要目录
    mkdir -p "$INSTALL_DIR/systemd"
    mkdir -p "$INSTALL_DIR/scripts"
    
    # 下载缺失文件
    for file in "${missing_files[@]}"; do
        print_status "下载: $file"
        if wget -q -O "$INSTALL_DIR/$file" "$GITHUB_RAW/$file"; then
            print_success "✓ $file"
        else
            print_error "✗ 下载失败: $file"
            return 1
        fi
    done
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null
    
    print_success "所有缺失文件下载完成"
}

# 安装systemd服务
install_systemd_service() {
    print_status "安装systemd服务..."
    
    # 复制服务文件
    if cp "$INSTALL_DIR/systemd/ugreen-led-monitor.service" "$SERVICE_FILE"; then
        print_success "服务文件已复制到: $SERVICE_FILE"
    else
        print_error "复制服务文件失败"
        return 1
    fi
    
    # 重载systemd配置
    print_status "重载systemd配置..."
    if systemctl daemon-reload; then
        print_success "systemd配置已重载"
    else
        print_error "重载systemd配置失败"
        return 1
    fi
    
    # 启用服务
    print_status "启用开机自启动..."
    if systemctl enable "$SERVICE_NAME"; then
        print_success "服务已设置为开机自启动"
    else
        print_error "启用服务失败"
        return 1
    fi
    
    # 启动服务
    print_status "启动服务..."
    if systemctl start "$SERVICE_NAME"; then
        print_success "服务已启动"
    else
        print_warning "服务启动失败，可能需要手动启动"
    fi
}

# 验证服务状态
verify_service() {
    print_status "验证服务状态..."
    
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        print_success "✓ 服务已启用（开机自启动）"
    else
        print_error "✗ 服务未启用"
    fi
    
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        print_success "✓ 服务正在运行"
    else
        print_warning "✗ 服务未运行"
    fi
    
    # 显示服务状态
    echo
    print_status "服务详细状态:"
    systemctl status "$SERVICE_NAME" --no-pager -l
}

# 显示使用说明
show_usage() {
    echo
    print_success "=== 服务安装完成 ==="
    echo
    echo -e "${CYAN}服务管理命令:${NC}"
    echo "  启动服务: sudo systemctl start $SERVICE_NAME"
    echo "  停止服务: sudo systemctl stop $SERVICE_NAME"
    echo "  重启服务: sudo systemctl restart $SERVICE_NAME"
    echo "  查看状态: sudo systemctl status $SERVICE_NAME"
    echo "  查看日志: sudo journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${CYAN}配置文件位置:${NC}"
    echo "  服务文件: $SERVICE_FILE"
    echo "  日志文件: /var/log/ugreen-led-monitor.log"
    echo "  PID文件: /var/run/ugreen-led-monitor.pid"
    echo
    echo -e "${GREEN}服务功能:${NC}"
    echo "  🔄 自动监控硬盘插拔（30秒扫描间隔）"
    echo "  💾 实时检测硬盘活动和休眠状态"
    echo "  🌟 SSH断开后继续自动工作"
    echo "  🚀 开机自启动"
    echo
    echo -e "${YELLOW}提示: 退出SSH后，插入硬盘对应的LED灯会自动亮起！${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        UGREEN LED 后台服务自动安装       ║${NC}"
    echo -e "${BLUE}║            Auto Service Installer        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo
    
    # 执行安装步骤
    check_root
    check_install_dir
    download_missing_files || exit 1
    install_systemd_service || exit 1
    verify_service
    show_usage
    
    echo
    print_success "🎉 后台服务安装完成！现在支持SSH断开后自动监控硬盘状态！"
}

# 运行主函数
main "$@"
