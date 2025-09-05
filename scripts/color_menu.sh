#!/bin/bash

# LLLED 颜色配置菜单
# 支持电源键、LAN、硬盘灯颜色自定义设置
# 版本: 1# 颜色主题配置文件
# 格式: LED类型_状态=RGB颜色值

# 电源键颜色配置
POWER_NORMAL="255 255 255"      # 正常状态 - 白色
POWER_STANDBY="255 255 0"       # 待机状态 - 黄色
POWER_ERROR="255 0 0"           # 错误状态 - 红色

# 网络LED颜色配置
NETWORK_ACTIVE="0 255 0"        # 活动状态 - 绿色
NETWORK_IDLE="255 255 0"        # 空闲状态 - 黄色
NETWORK_ERROR="255 0 0"         # 错误状态 - 红色
NETWORK_OFFLINE="0 0 0"         # 离线状态 - 关闭

# 硬盘LED颜色配置
DISK_ACTIVE="0 255 0"           # 活动状态 - 绿色
DISK_IDLE="255 255 0"           # 空闲状态 - 黄色
DISK_ERROR="255 0 0"            # 错误状态 - 红色
DISK_OFFLINE="0 0 0"            # 离线状态 - 关闭PT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"
COLOR_CONFIG="$SCRIPT_DIR/config/color_themes.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

# 预定义颜色方案
declare -A COLOR_PRESETS
COLOR_PRESETS["红色"]="255 0 0"
COLOR_PRESETS["绿色"]="0 255 0"
COLOR_PRESETS["蓝色"]="0 0 255"
COLOR_PRESETS["白色"]="255 255 255"
COLOR_PRESETS["黄色"]="255 255 0"
COLOR_PRESETS["青色"]="0 255 255"
COLOR_PRESETS["紫色"]="255 0 255"
COLOR_PRESETS["橙色"]="255 165 0"
COLOR_PRESETS["粉色"]="255 192 203"
COLOR_PRESETS["浅绿"]="144 238 144"
COLOR_PRESETS["天蓝"]="135 206 235"
COLOR_PRESETS["金色"]="255 215 0"
COLOR_PRESETS["关闭"]="0 0 0"

# 状态模式定义
declare -A STATUS_MODES
STATUS_MODES["活动状态"]="on"
STATUS_MODES["空闲状态"]="on"
STATUS_MODES["错误状态"]="blink"
STATUS_MODES["离线状态"]="on"

# 亮度定义
declare -A STATUS_BRIGHTNESS
STATUS_BRIGHTNESS["活动状态"]="128"
STATUS_BRIGHTNESS["空闲状态"]="32"
STATUS_BRIGHTNESS["错误状态"]="255"
STATUS_BRIGHTNESS["离线状态"]="16"

# 初始化颜色配置文件
init_color_config() {
    if [[ ! -f "$COLOR_CONFIG" ]]; then
        cat > "$COLOR_CONFIG" << 'EOF'
# LLLED 颜色主题配置文件
# 格式: LED类型_状态=RGB颜色值

# 电源键颜色配置
POWER_NORMAL="255 255 255"      # 正常状态 - 白色
POWER_STANDBY="255 255 0"       # 待机状态 - 黄色
POWER_ERROR="255 0 0"           # 错误状态 - 红色

# 网络LED颜色配置
NETWORK_ACTIVE="0 255 0"        # 活动状态 - 绿色
NETWORK_IDLE="255 255 0"        # 空闲状态 - 黄色
NETWORK_ERROR="255 0 0"         # 错误状态 - 红色
NETWORK_OFFLINE="128 128 128"   # 离线状态 - 灰色

# 硬盘LED颜色配置
DISK_ACTIVE="0 255 0"           # 活动状态 - 绿色
DISK_IDLE="255 255 0"           # 空闲状态 - 黄色
DISK_ERROR="255 0 0"            # 错误状态 - 红色
DISK_OFFLINE="64 64 64"         # 离线状态 - 深灰色

# 当前选择的主题
CURRENT_THEME="default"
EOF
        echo -e "${GREEN}创建默认颜色配置文件${NC}"
    fi
    source "$COLOR_CONFIG"
}

# 显示颜色预览
show_color_preview() {
    local color_rgb="$1"
    local led_name="$2"
    
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: ugreen_leds_cli 未找到${NC}"
        return 1
    fi
    
    # 设置LED颜色预览（持续3秒）
    "$UGREEN_LEDS_CLI" "$led_name" -color $color_rgb -on -brightness 128 >/dev/null 2>&1
    echo -e "${CYAN}预览颜色: $color_rgb (3秒)${NC}"
    sleep 3
    "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
}

# 选择颜色
select_color() {
    local prompt="$1"
    
    echo -e "${BLUE}$prompt${NC}"
    echo "可选颜色:"
    
    # 创建颜色列表数组
    local color_list=("红色" "绿色" "蓝色" "白色" "黄色" "青色" "紫色" "橙色" "粉色" "浅绿" "天蓝" "金色" "关闭")
    
    local i=1
    for color_name in "${color_list[@]}"; do
        local rgb_value="${COLOR_PRESETS[$color_name]}"
        echo "  $i) $color_name ($rgb_value)"
        ((i++))
    done
    echo "  $i) 自定义RGB"
    
    while true; do
        read -p "请选择颜色 (1-$i): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le $i ]]; then
            if [[ "$choice" -eq $i ]]; then
                # 自定义RGB
                echo "请输入RGB值 (格式: R G B, 范围 0-255):"
                read -p "红色值 (0-255): " r
                read -p "绿色值 (0-255): " g
                read -p "蓝色值 (0-255): " b
                
                if [[ "$r" =~ ^[0-9]+$ ]] && [[ "$g" =~ ^[0-9]+$ ]] && [[ "$b" =~ ^[0-9]+$ ]] && \
                   [[ "$r" -le 255 ]] && [[ "$g" -le 255 ]] && [[ "$b" -le 255 ]]; then
                    echo "$r $g $b"
                    return
                else
                    echo -e "${RED}无效的RGB值，请重试${NC}"
                fi
            else
                local selected_color="${color_list[$((choice-1))]}"
                echo "${COLOR_PRESETS[$selected_color]}"
                return
            fi
        else
            echo -e "${RED}无效选择，请重试${NC}"
        fi
    done
}

# 配置电源键颜色
configure_power_colors() {
    echo -e "${CYAN}=== 电源键LED颜色配置 ===${NC}"
    echo ""
    
    # 正常状态
    echo -e "${GREEN}配置电源键正常状态颜色:${NC}"
    local power_normal
    power_normal=$(select_color "选择电源键正常状态颜色:")
    
    # 预览颜色
    read -p "是否预览此颜色? (y/n): " preview
    if [[ "$preview" =~ ^[Yy] ]]; then
        show_color_preview "$power_normal" "power"
    fi
    
    # 待机状态
    echo -e "${YELLOW}配置电源键待机状态颜色:${NC}"
    local power_standby
    power_standby=$(select_color "选择电源键待机状态颜色:")
    
    # 错误状态
    echo -e "${RED}配置电源键错误状态颜色:${NC}"
    local power_error
    power_error=$(select_color "选择电源键错误状态颜色:")
    
    # 保存配置
    sed -i "s/^POWER_NORMAL=.*/POWER_NORMAL=\"$power_normal\"/" "$COLOR_CONFIG"
    sed -i "s/^POWER_STANDBY=.*/POWER_STANDBY=\"$power_standby\"/" "$COLOR_CONFIG"
    sed -i "s/^POWER_ERROR=.*/POWER_ERROR=\"$power_error\"/" "$COLOR_CONFIG"
    
    echo -e "${GREEN}✓ 电源键颜色配置已保存${NC}"
}

# 配置网络LED颜色
configure_network_colors() {
    echo -e "${CYAN}=== 网络LED颜色配置 ===${NC}"
    echo ""
    
    echo -e "${GREEN}🟢 活动状态: 绿色高亮 (正在传输)${NC}"
    local network_active
    network_active=$(select_color "选择网络活动状态颜色:")
    
    read -p "是否预览此颜色? (y/n): " preview
    if [[ "$preview" =~ ^[Yy] ]]; then
        show_color_preview "$network_active" "netdev"
    fi
    
    echo -e "${YELLOW}🟡 空闲状态: 黄色低亮 (待机)${NC}"
    local network_idle
    network_idle=$(select_color "选择网络空闲状态颜色:")
    
    echo -e "${RED}🔴 错误状态: 红色闪烁 (故障)${NC}"
    local network_error
    network_error=$(select_color "选择网络错误状态颜色:")
    
    echo -e "${GRAY}⚫ 离线状态: 灯光关闭 (未连接)${NC}"
    local network_offline
    network_offline=$(select_color "选择网络离线状态颜色:")
    
    # 保存配置
    sed -i "s/^NETWORK_ACTIVE=.*/NETWORK_ACTIVE=\"$network_active\"/" "$COLOR_CONFIG"
    sed -i "s/^NETWORK_IDLE=.*/NETWORK_IDLE=\"$network_idle\"/" "$COLOR_CONFIG"
    sed -i "s/^NETWORK_ERROR=.*/NETWORK_ERROR=\"$network_error\"/" "$COLOR_CONFIG"
    sed -i "s/^NETWORK_OFFLINE=.*/NETWORK_OFFLINE=\"$network_offline\"/" "$COLOR_CONFIG"
    
    echo -e "${GREEN}✓ 网络LED颜色配置已保存${NC}"
}

# 配置硬盘LED颜色
configure_disk_colors() {
    echo -e "${CYAN}=== 硬盘LED颜色配置 ===${NC}"
    echo ""
    
    echo -e "${GREEN}🟢 活动状态: 绿色高亮 (正在读写)${NC}"
    local disk_active
    disk_active=$(select_color "选择硬盘活动状态颜色:")
    
    # 选择一个硬盘LED进行预览
    read -p "是否预览此颜色? (y/n): " preview
    if [[ "$preview" =~ ^[Yy] ]]; then
        show_color_preview "$disk_active" "disk1"
    fi
    
    echo -e "${YELLOW}🟡 空闲状态: 黄色低亮 (待机)${NC}"
    local disk_idle
    disk_idle=$(select_color "选择硬盘空闲状态颜色:")
    
    echo -e "${RED}🔴 错误状态: 红色闪烁 (故障)${NC}"
    local disk_error
    disk_error=$(select_color "选择硬盘错误状态颜色:")
    
    echo -e "${GRAY}⚫ 离线状态: 灯光关闭 (未检测到)${NC}"
    local disk_offline
    disk_offline=$(select_color "选择硬盘离线状态颜色:")
    
    # 保存配置
    sed -i "s/^DISK_ACTIVE=.*/DISK_ACTIVE=\"$disk_active\"/" "$COLOR_CONFIG"
    sed -i "s/^DISK_IDLE=.*/DISK_IDLE=\"$disk_idle\"/" "$COLOR_CONFIG"
    sed -i "s/^DISK_ERROR=.*/DISK_ERROR=\"$disk_error\"/" "$COLOR_CONFIG"
    sed -i "s/^DISK_OFFLINE=.*/DISK_OFFLINE=\"$disk_offline\"/" "$COLOR_CONFIG"
    
    echo -e "${GREEN}✓ 硬盘LED颜色配置已保存${NC}"
}

# 应用颜色主题
apply_color_theme() {
    echo -e "${CYAN}=== 应用当前颜色主题 ===${NC}"
    
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: ugreen_leds_cli 未找到，请先运行安装脚本${NC}"
        return 1
    fi
    
    source "$COLOR_CONFIG"
    
    echo "正在应用颜色主题..."
    
    # 设置电源键为正常状态
    "$UGREEN_LEDS_CLI" power -color $POWER_NORMAL -on -brightness 64 >/dev/null 2>&1
    echo -e "${GREEN}✓ 电源键: $POWER_NORMAL${NC}"
    
    # 设置网络LED为空闲状态
    "$UGREEN_LEDS_CLI" netdev -color $NETWORK_IDLE -on -brightness 32 >/dev/null 2>&1
    echo -e "${GREEN}✓ 网络LED: $NETWORK_IDLE${NC}"
    
    # 设置所有硬盘LED为空闲状态
    local disk_count=0
    for disk_num in {1..8}; do
        if "$UGREEN_LEDS_CLI" "disk$disk_num" -color $DISK_IDLE -on -brightness 32 >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 硬盘${disk_num}LED: $DISK_IDLE${NC}"
            ((disk_count++))
        fi
    done
    
    echo -e "${CYAN}主题应用完成！设置了 $disk_count 个硬盘LED${NC}"
}

# 测试所有状态效果
test_status_effects() {
    echo -e "${CYAN}=== 测试状态效果演示 ===${NC}"
    
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: ugreen_leds_cli 未找到${NC}"
        return 1
    fi
    
    source "$COLOR_CONFIG"
    
    echo "开始状态效果演示（每种状态持续3秒）..."
    echo ""
    
    # 测试网络LED状态
    echo -e "${BLUE}网络LED状态演示:${NC}"
    
    echo -e "${GREEN}🟢 活动状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" netdev -color $NETWORK_ACTIVE -on -brightness 128 >/dev/null 2>&1
    sleep 3
    
    echo -e "${YELLOW}🟡 空闲状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" netdev -color $NETWORK_IDLE -on -brightness 32 >/dev/null 2>&1
    sleep 3
    
    echo -e "${RED}🔴 错误状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" netdev -color $NETWORK_ERROR -blink 500 500 -brightness 255 >/dev/null 2>&1
    sleep 3
    
    echo -e "${GRAY}⚫ 离线状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" netdev -color $NETWORK_OFFLINE -on -brightness 16 >/dev/null 2>&1
    sleep 3
    
    # 测试硬盘LED状态（使用disk1）
    echo -e "${BLUE}硬盘LED状态演示:${NC}"
    
    echo -e "${GREEN}🟢 活动状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" disk1 -color $DISK_ACTIVE -on -brightness 128 >/dev/null 2>&1
    sleep 3
    
    echo -e "${YELLOW}🟡 空闲状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" disk1 -color $DISK_IDLE -on -brightness 32 >/dev/null 2>&1
    sleep 3
    
    echo -e "${RED}🔴 错误状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" disk1 -color $DISK_ERROR -blink 200 200 -brightness 255 >/dev/null 2>&1
    sleep 3
    
    echo -e "${GRAY}⚫ 离线状态 (3秒)${NC}"
    "$UGREEN_LEDS_CLI" disk1 -color $DISK_OFFLINE -on -brightness 16 >/dev/null 2>&1
    sleep 3
    
    # 关闭测试LED
    "$UGREEN_LEDS_CLI" netdev -off >/dev/null 2>&1
    "$UGREEN_LEDS_CLI" disk1 -off >/dev/null 2>&1
    
    echo -e "${GREEN}状态效果演示完成${NC}"
}

# 显示当前配置
show_current_config() {
    echo -e "${CYAN}=== 当前颜色配置 ===${NC}"
    echo ""
    
    if [[ -f "$COLOR_CONFIG" ]]; then
        source "$COLOR_CONFIG"
        
        echo -e "${BLUE}电源键配置:${NC}"
        echo "  正常状态: $POWER_NORMAL"
        echo "  待机状态: $POWER_STANDBY"
        echo "  错误状态: $POWER_ERROR"
        echo ""
        
        echo -e "${BLUE}网络LED配置:${NC}"
        echo "  🟢 活动状态: $NETWORK_ACTIVE"
        echo "  🟡 空闲状态: $NETWORK_IDLE"
        echo "  🔴 错误状态: $NETWORK_ERROR"
        echo "  ⚫ 离线状态: $NETWORK_OFFLINE"
        echo ""
        
        echo -e "${BLUE}硬盘LED配置:${NC}"
        echo "  🟢 活动状态: $DISK_ACTIVE"
        echo "  🟡 空闲状态: $DISK_IDLE"
        echo "  🔴 错误状态: $DISK_ERROR"
        echo "  ⚫ 离线状态: $DISK_OFFLINE"
    else
        echo -e "${YELLOW}颜色配置文件不存在，将使用默认配置${NC}"
    fi
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║        LLLED 颜色配置菜单          ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}1)${NC} 配置电源键颜色"
        echo -e "${BLUE}2)${NC} 配置网络LED颜色"
        echo -e "${BLUE}3)${NC} 配置硬盘LED颜色"
        echo -e "${BLUE}4)${NC} 应用当前主题"
        echo -e "${BLUE}5)${NC} 测试状态效果"
        echo -e "${BLUE}6)${NC} 查看当前配置"
        echo -e "${BLUE}7)${NC} 重置为默认颜色"
        echo -e "${BLUE}0)${NC} 退出"
        echo ""
        
        read -p "请选择操作 (0-7): " choice
        
        case "$choice" in
            1)
                configure_power_colors
                read -p "按回车键继续..."
                ;;
            2)
                configure_network_colors
                read -p "按回车键继续..."
                ;;
            3)
                configure_disk_colors
                read -p "按回车键继续..."
                ;;
            4)
                apply_color_theme
                read -p "按回车键继续..."
                ;;
            5)
                test_status_effects
                read -p "按回车键继续..."
                ;;
            6)
                show_current_config
                read -p "按回车键继续..."
                ;;
            7)
                rm -f "$COLOR_CONFIG"
                init_color_config
                echo -e "${GREEN}已重置为默认颜色配置${NC}"
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "${GREEN}退出颜色配置菜单${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 检查依赖
check_dependencies() {
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${YELLOW}警告: ugreen_leds_cli 未找到${NC}"
        echo "某些功能（如颜色预览和应用主题）将不可用"
        echo "请先运行 quick_install.sh 安装LLLED系统"
        echo ""
    fi
}

# 主程序
main() {
    echo -e "${CYAN}LLLED 颜色配置工具${NC}"
    echo "支持电源键、网络、硬盘LED颜色自定义"
    echo ""
    
    check_dependencies
    init_color_config
    main_menu
}

# 运行主程序
main "$@"
