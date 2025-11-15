#!/bin/bash

# UGREEN LED 控制器 - 卸载脚本
# 版本: 4.0.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 路径配置
INSTALL_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="/var/log/llled"
SERVICE_NAME="ugreen-led-monitor"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
COMMAND_LINKS=("/usr/local/bin/LLLED" "/usr/bin/LLLED" "/bin/LLLED")

# 从全局配置读取版本号（如果存在）
VERSION="4.0.0"
if [[ -f "$CONFIG_DIR/global_config.conf" ]]; then
    source "$CONFIG_DIR/global_config.conf" 2>/dev/null || true
    VERSION="${LLLED_VERSION:-$VERSION}"
fi

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { 
        echo -e "${RED}需要root权限: sudo bash $0${NC}"
        exit 1
    }
}

# 显示标题
show_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}UGREEN LED 控制器卸载工具 v${VERSION}${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
}

# 检查安装状态
check_installation() {
    local found=false
    
    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "${GREEN}✓ 安装目录存在: $INSTALL_DIR${NC}"
        found=true
    fi
    
    if systemctl list-unit-files 2>/dev/null | grep -q "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ 系统服务已安装${NC}"
        found=true
    fi
    
    for link in "${COMMAND_LINKS[@]}"; do
        if [[ -L "$link" || -f "$link" ]]; then
            echo -e "${GREEN}✓ 命令链接存在: $link${NC}"
            found=true
            break
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        echo -e "${YELLOW}未检测到安装，退出${NC}"
        exit 0
    fi
    echo
}

# 关闭所有LED
turn_off_leds() {
    echo -e "${BLUE}关闭所有LED...${NC}"
    
    if [[ -f "$INSTALL_DIR/ugreen_leds_cli" ]]; then
        "$INSTALL_DIR/ugreen_leds_cli" all -off >/dev/null 2>&1 || true
        
        # 备用方法
        local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
        for led in "${leds[@]}"; do
            "$INSTALL_DIR/ugreen_leds_cli" "$led" -off >/dev/null 2>&1 || true
        done
        echo -e "${GREEN}✓ LED已关闭${NC}"
    else
        echo -e "${YELLOW}  LED控制程序不存在，跳过${NC}"
    fi
}

# 停止并移除服务
remove_service() {
    echo -e "${BLUE}停止并移除系统服务...${NC}"
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
    fi
    
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}✓ 系统服务已移除${NC}"
}

# 移除命令链接
remove_command_links() {
    echo -e "${BLUE}移除命令链接...${NC}"
    
    local removed=false
    for link in "${COMMAND_LINKS[@]}"; do
        if [[ -L "$link" || -f "$link" ]]; then
            rm -f "$link" 2>/dev/null && removed=true
        fi
    done
    
    if [[ "$removed" == "true" ]]; then
        echo -e "${GREEN}✓ 命令链接已移除${NC}"
    else
        echo -e "${YELLOW}  未找到命令链接${NC}"
    fi
}

# 备份配置
backup_config() {
    local backup_dir="/tmp/llled_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$CONFIG_DIR" ]]; then
        echo -e "${BLUE}备份配置文件...${NC}"
        mkdir -p "$backup_dir"
        
        if cp -r "$CONFIG_DIR" "$backup_dir/" 2>/dev/null; then
            echo -e "${GREEN}✓ 配置已备份到: $backup_dir${NC}"
        else
            echo -e "${YELLOW}  备份失败，继续卸载${NC}"
        fi
    fi
}

# 移除安装目录
remove_install_dir() {
    local mode="$1"
    
    echo -e "${BLUE}移除安装目录...${NC}"
    
    case "$mode" in
        "complete")
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
                echo -e "${GREEN}✓ 安装目录已完全删除${NC}"
            fi
            ;;
        "keep-config")
            if [[ -d "$INSTALL_DIR" ]]; then
                # 删除程序文件，保留配置
                rm -f "$INSTALL_DIR"/*.sh 2>/dev/null
                rm -f "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null
                rm -rf "$INSTALL_DIR/scripts" 2>/dev/null
                rm -rf "$INSTALL_DIR/systemd" 2>/dev/null
                echo -e "${GREEN}✓ 程序文件已删除，配置已保留${NC}"
            fi
            ;;
        "stop-only")
            echo -e "${YELLOW}  保留所有文件，仅停用服务${NC}"
            ;;
    esac
}

# 清理进程
cleanup_processes() {
    echo -e "${BLUE}清理相关进程...${NC}"
    
    local pids=$(pgrep -f "led_daemon\|ugreen.*led" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
        sleep 1
        # 强制kill
        kill -9 $pids 2>/dev/null || true
        echo -e "${GREEN}✓ 进程已清理${NC}"
    else
        echo -e "${YELLOW}  未发现相关进程${NC}"
    fi
}

# 显示卸载选项
show_uninstall_menu() {
    echo -e "${YELLOW}卸载选项:${NC}"
    echo "1. 完全卸载 (删除所有文件和配置)"
    echo "2. 保留配置卸载 (保留配置文件)"
    echo "3. 仅停止服务 (保留所有文件)"
    echo "4. 取消"
    echo
    
    while true; do
        read -p "请选择 (1-4): " choice
        case "$choice" in
            1)
                UNINSTALL_MODE="complete"
                BACKUP_CONFIG=true
                break
                ;;
            2)
                UNINSTALL_MODE="keep-config"
                BACKUP_CONFIG=false
                break
                ;;
            3)
                UNINSTALL_MODE="stop-only"
                BACKUP_CONFIG=false
                break
                ;;
            4)
                echo -e "${GREEN}卸载已取消${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
    done
    echo
}

# 确认卸载
confirm_uninstall() {
    echo -e "${RED}警告: 即将卸载 UGREEN LED 控制器${NC}"
    echo
    read -p "确认卸载? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}卸载已取消${NC}"
        exit 0
    fi
    echo
}

# 显示卸载结果
show_result() {
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}卸载完成${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    case "$UNINSTALL_MODE" in
        "complete")
            echo -e "${GREEN}✓ 完全卸载完成${NC}"
            echo "  • 所有程序文件已删除"
            echo "  • 所有配置文件已删除"
            echo "  • 系统服务已移除"
            echo "  • 命令链接已移除"
            ;;
        "keep-config")
            echo -e "${GREEN}✓ 程序已卸载，配置已保留${NC}"
            echo "  • 程序文件已删除"
            echo "  • 配置文件已保留在: $CONFIG_DIR"
            echo "  • 系统服务已移除"
            echo "  • 命令链接已移除"
            ;;
        "stop-only")
            echo -e "${GREEN}✓ 服务已停用${NC}"
            echo "  • 系统服务已停止和禁用"
            echo "  • 所有文件已保留"
            echo "  • 可使用 $INSTALL_DIR/ugreen_led_controller.sh 手动启动"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}如需重新安装:${NC}"
    echo "  curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash"
    echo
}

# 主函数
main() {
    show_header
    check_root
    check_installation
    show_uninstall_menu
    confirm_uninstall
    
    echo -e "${CYAN}开始卸载...${NC}"
    echo
    
    # 执行卸载步骤
    if [[ "$BACKUP_CONFIG" == "true" ]]; then
        backup_config
    fi
    
    turn_off_leds
    cleanup_processes
    remove_service
    remove_command_links
    remove_install_dir "$UNINSTALL_MODE"
    
    show_result
}

# 处理命令行参数
case "${1:-}" in
    "--force")
        check_root
        check_installation
        UNINSTALL_MODE="complete"
        BACKUP_CONFIG=true
        backup_config
        turn_off_leds
        cleanup_processes
        remove_service
        remove_command_links
        remove_install_dir "$UNINSTALL_MODE"
        echo -e "${GREEN}强制卸载完成${NC}"
        ;;
    "--help"|"-h")
        echo "UGREEN LED 控制器卸载工具 v$VERSION"
        echo
        echo "用法: sudo $0 [选项]"
        echo
        echo "选项:"
        echo "  --force    强制完全卸载，不询问确认"
        echo "  --help     显示帮助信息"
        echo
        echo "交互式卸载: sudo $0"
        ;;
    *)
        main
        ;;
esac
