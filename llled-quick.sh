#!/bin/bash

# LLLED 快捷命令脚本
# 为颜色配置和智能监控提供便捷访问

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

INSTALL_DIR="/opt/ugreen-led-controller"

# 显示快捷菜单
show_quick_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           LLLED 快捷菜单             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}🎨 颜色配置功能:${NC}"
    echo -e "${GREEN}1)${NC} 颜色配置菜单 - 自定义LED颜色"
    echo -e "${GREEN}2)${NC} 智能状态监控 - 基于颜色配置的实时监控"
    echo -e "${GREEN}3)${NC} 应用颜色主题 - 立即应用当前颜色设置"
    echo -e "${GREEN}4)${NC} 测试状态效果 - 演示所有状态颜色"
    echo ""
    echo -e "${BLUE}💡 LED控制功能:${NC}"
    echo -e "${GREEN}5)${NC} 硬盘状态监控 - 智能硬盘LED显示"
    echo -e "${GREEN}6)${NC} 关闭所有LED - 关闭所有LED灯"
    echo -e "${GREEN}7)${NC} 彩虹效果 - LED彩虹效果演示"
    echo -e "${GREEN}8)${NC} 设备检测 - 检查设备兼容性"
    echo ""
    echo -e "${BLUE}⚙️  系统功能:${NC}"
    echo -e "${GREEN}9)${NC} LLLED主程序 - 启动完整LLLED系统"
    echo -e "${GREEN}10)${NC} 查看帮助 - 显示详细使用说明"
    echo -e "${GREEN}0)${NC} 退出"
    echo ""
}

# 执行功能
execute_function() {
    local choice="$1"
    
    case "$choice" in
        1)
            echo -e "${CYAN}启动颜色配置菜单...${NC}"
            sudo bash "$INSTALL_DIR/scripts/color_menu.sh"
            ;;
        2)
            echo -e "${CYAN}启动智能状态监控...${NC}"
            echo "选择监控模式:"
            echo "1) 持续监控模式"
            echo "2) 查看当前状态"
            echo "3) 运行一次更新"
            read -p "请选择 (1-3): " monitor_choice
            
            case "$monitor_choice" in
                1) sudo bash "$INSTALL_DIR/scripts/smart_status_monitor.sh" -m ;;
                2) sudo bash "$INSTALL_DIR/scripts/smart_status_monitor.sh" -s ;;
                3) sudo bash "$INSTALL_DIR/scripts/smart_status_monitor.sh" -o -v ;;
                *) echo "无效选择" ;;
            esac
            ;;
        3)
            echo -e "${CYAN}应用颜色主题...${NC}"
            sudo bash "$INSTALL_DIR/scripts/color_menu.sh" <<< "4"
            ;;
        4)
            echo -e "${CYAN}测试状态效果...${NC}"
            sudo bash "$INSTALL_DIR/scripts/color_menu.sh" <<< "5"
            ;;
        5)
            echo -e "${CYAN}启动硬盘状态监控...${NC}"
            sudo bash "$INSTALL_DIR/scripts/disk_status_leds.sh"
            ;;
        6)
            echo -e "${CYAN}关闭所有LED...${NC}"
            sudo bash "$INSTALL_DIR/scripts/turn_off_all_leds.sh"
            ;;
        7)
            echo -e "${CYAN}启动彩虹效果...${NC}"
            sudo bash "$INSTALL_DIR/scripts/rainbow_effect.sh"
            ;;
        8)
            echo -e "${CYAN}运行设备检测...${NC}"
            sudo bash "$INSTALL_DIR/verify_detection.sh"
            ;;
        9)
            echo -e "${CYAN}启动LLLED主程序...${NC}"
            sudo LLLED
            ;;
        10)
            show_help
            ;;
        0)
            echo -e "${GREEN}退出LLLED快捷菜单${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}=== LLLED 功能说明 ===${NC}"
    echo ""
    echo -e "${YELLOW}🎨 颜色配置功能:${NC}"
    echo "• 颜色配置菜单: 自定义电源、网络、硬盘LED的颜色"
    echo "  - 支持13种预设颜色 + 自定义RGB"
    echo "  - 分别配置4种状态: 活动/空闲/错误/离线"
    echo "  - 实时颜色预览功能"
    echo ""
    echo "• 智能状态监控: 基于用户颜色配置的实时状态显示"
    echo "  - 🟢 活动状态: 绿色高亮 (设备正在工作)"
    echo "  - 🟡 空闲状态: 黄色低亮 (设备待机)"
    echo "  - 🔴 错误状态: 红色闪烁 (设备故障)"
    echo "  - ⚫ 离线状态: 灯光关闭 (设备未检测到)"
    echo ""
    echo -e "${YELLOW}💡 LED控制功能:${NC}"
    echo "• 硬盘状态监控: 基于SMART状态和温度的智能LED显示"
    echo "• 彩虹效果: 动态彩虹LED效果演示"
    echo "• 关闭LED: 安全关闭所有LED灯"
    echo ""
    echo -e "${YELLOW}⚙️  技术特性:${NC}"
    echo "• 多盘位支持: 自动适配4/6/8盘位设备"
    echo "• HCTL智能检测: 自动识别硬盘位置"
    echo "• 动态LED映射: 运行时发现LED配置"
    echo "• 向后兼容: 支持传统配置文件"
    echo ""
    echo -e "${YELLOW}📁 配置文件位置:${NC}"
    echo "• LED映射配置: /opt/ugreen-led-controller/config/led_mapping.conf"
    echo "• 颜色主题配置: /opt/ugreen-led-controller/config/color_themes.conf"
    echo "• 日志文件: /var/log/llled_status_monitor.log"
    echo ""
}

# 检查安装
check_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo -e "${RED}错误: LLLED未安装${NC}"
        echo "请先运行安装脚本: curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash"
        exit 1
    fi
    
    if [[ ! -f "$INSTALL_DIR/scripts/color_menu.sh" ]]; then
        echo -e "${YELLOW}警告: 颜色配置功能未找到${NC}"
        echo "请重新运行安装脚本获取最新版本"
    fi
}

# 主程序
main() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 检查安装
    check_installation
    
    # 命令行参数处理
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "color"|"colors")
                sudo bash "$INSTALL_DIR/scripts/color_menu.sh"
                exit 0
                ;;
            "monitor")
                sudo bash "$INSTALL_DIR/scripts/smart_status_monitor.sh" -m
                exit 0
                ;;
            "status")
                sudo bash "$INSTALL_DIR/scripts/smart_status_monitor.sh" -s
                exit 0
                ;;
            "help"|"--help")
                show_help
                exit 0
                ;;
        esac
    fi
    
    # 交互式菜单
    while true; do
        show_quick_menu
        read -p "请选择功能 (0-10): " choice
        echo ""
        
        execute_function "$choice"
        
        if [[ "$choice" != "0" ]]; then
            echo ""
            read -p "按回车键返回菜单..."
        fi
    done
}

# 运行主程序
main "$@"
