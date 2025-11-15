#!/bin/bash

# UGREEN LED 控制器 - 主控制脚本
# 版本: 4.0.0
# 简化重构版

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$INSTALL_DIR/config"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
UGREEN_CLI="$INSTALL_DIR/ugreen_leds_cli"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 加载配置
load_config() {
    if [[ -f "$CONFIG_DIR/global_config.conf" ]]; then
        source "$CONFIG_DIR/global_config.conf"
    fi
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        source "$CONFIG_DIR/led_config.conf"
    fi
    # 从配置读取版本号
    VERSION="${LLLED_VERSION:-${VERSION:-4.0.0}}"
}

# 检查安装
check_installation() {
    if [[ ! -f "$UGREEN_CLI" ]] || [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: LED控制程序未正确安装${NC}"
        echo "请运行安装脚本: sudo bash quick_install.sh"
        exit 1
    fi
}

# 获取所有LED
get_all_leds() {
    local all_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    local leds=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+): ]]; then
            leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$all_status"
    
    echo "${leds[@]}"
}

# 关闭所有LED
turn_off_all_leds() {
    echo -e "${CYAN}关闭所有LED...${NC}"
    local leds=($(get_all_leds))
    
    if [[ ${#leds[@]} -eq 0 ]]; then
        # 备用方法：先尝试 all 参数
        "$UGREEN_CLI" all -off >/dev/null 2>&1 || true
        
        # 如果 all 参数失败，尝试系统LED和常见硬盘LED
        for led in power netdev; do
            "$UGREEN_CLI" "$led" -off 2>/dev/null || true
        done
        
        # 从配置文件读取实际存在的硬盘LED
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    "$UGREEN_CLI" "disk$i" -off 2>/dev/null || true
                fi
            done
        fi
    else
        for led in "${leds[@]}"; do
            "$UGREEN_CLI" "$led" -off 2>/dev/null || true
        done
    fi
    
    # 确保所有LED关闭
    "$UGREEN_CLI" all -off >/dev/null 2>&1 || true
    
    echo -e "${GREEN}✓ 所有LED已关闭${NC}"
}

# 打开所有LED
turn_on_all_leds() {
    echo -e "${CYAN}打开所有LED...${NC}"
    local leds=($(get_all_leds))
    local color="${POWER_COLOR:-128 128 128}"
    local brightness="${DEFAULT_BRIGHTNESS:-64}"
    
    if [[ ${#leds[@]} -eq 0 ]]; then
        # 备用方法：从配置文件读取实际存在的LED
        for led in power netdev; do
            "$UGREEN_CLI" "$led" -color $color -brightness $brightness -on 2>/dev/null || true
        done
        
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    "$UGREEN_CLI" "disk$i" -color $color -brightness $brightness -on 2>/dev/null || true
                fi
            done
        fi
    else
        for led in "${leds[@]}"; do
            "$UGREEN_CLI" "$led" -color $color -brightness $brightness -on 2>/dev/null || true
        done
    fi
    
    echo -e "${GREEN}✓ 所有LED已打开${NC}"
}

# 节能模式
power_save_mode() {
    echo -e "${CYAN}启用节能模式...${NC}"
    local leds=($(get_all_leds))
    local color="64 64 64"  # 暗灰色
    local brightness="16"   # 低亮度
    
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -color $color -brightness $brightness -on 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ 节能模式已启用${NC}"
}

# 设置开机自启
enable_autostart() {
    echo -e "${CYAN}设置开机自启...${NC}"
    if systemctl enable ugreen-led-monitor.service >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 开机自启已启用${NC}"
    else
        echo -e "${RED}✗ 启用开机自启失败${NC}"
    fi
}

# 关闭开机自启
disable_autostart() {
    echo -e "${CYAN}关闭开机自启...${NC}"
    if systemctl disable ugreen-led-monitor.service >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 开机自启已关闭${NC}"
    else
        echo -e "${RED}✗ 关闭开机自启失败${NC}"
    fi
}

# 查看映射状态
show_mapping_status() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}LED映射状态${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    # 显示LED配置
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        echo -e "${BLUE}LED配置:${NC}"
        echo "  电源LED: ID ${POWER_LED:-0}"
        echo "  网络LED: ID ${NETDEV_LED:-1}"
        
        # 显示硬盘LED - 从配置文件读取实际存在的LED
        local disk_count=0
        local disk_leds=()
        
        # 优先从配置文件读取
        if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
            source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
            for i in {1..8}; do
                local var_name="DISK${i}_LED"
                if [[ -n "${!var_name:-}" ]]; then
                    echo "  硬盘${i}LED: ID ${!var_name}"
                    disk_leds+=("disk$i")
                    ((disk_count++))
                fi
            done
        fi
        
        # 如果配置文件没有，尝试从实际检测
        if [[ $disk_count -eq 0 ]]; then
            local detected_leds=($(get_all_leds))
            for led in "${detected_leds[@]}"; do
                if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                    echo "  检测到LED: $led"
                    disk_leds+=("$led")
                    ((disk_count++))
                fi
            done
        fi
        
        echo "  检测到 $disk_count 个硬盘LED"
        echo
    fi
    
    # 显示硬盘映射
    if [[ -f "$CONFIG_DIR/disk_mapping.conf" ]]; then
        echo -e "${BLUE}硬盘映射:${NC}"
        local mapping_count=0
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
                local device="${BASH_REMATCH[1]}"
                local mapping="${BASH_REMATCH[2]}"
                IFS='|' read -r hctl led serial model size <<< "$mapping"
                echo "  $device -> $led (HCTL: $hctl)"
                echo "    型号: ${model:-Unknown} | 序列号: ${serial:-N/A} | 大小: ${size:-N/A}"
                ((mapping_count++))
            fi
        done < "$CONFIG_DIR/disk_mapping.conf"
        
        if [[ $mapping_count -eq 0 ]]; then
            echo "  (无硬盘映射)"
        fi
        echo
    fi
    
    # 显示服务状态
    echo -e "${BLUE}服务状态:${NC}"
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        echo -e "  状态: ${GREEN}运行中${NC}"
    else
        echo -e "  状态: ${RED}未运行${NC}"
    fi
    
    if systemctl is-enabled --quiet ugreen-led-monitor.service; then
        echo -e "  开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "  开机自启: ${YELLOW}未启用${NC}"
    fi
    echo
}

# 智能设置菜单
show_smart_settings_menu() {
    while true; do
        # 重新加载配置
        load_config
        
        clear
        echo -e "${CYAN}================================${NC}"
        echo -e "${CYAN}智能设置${NC}"
        echo -e "${CYAN}================================${NC}"
        echo
        echo "1. 自动检测LED设备"
        echo "2. 自动检测硬盘映射"
        echo "3. 自动配置所有设置"
        echo "4. 恢复默认配置"
        echo "5. 返回主菜单"
        echo
        read -p "请选择功能 (1-5): " choice
        
        case $choice in
            1)
                auto_detect_leds
                ;;
            2)
                auto_detect_disk_mapping
                ;;
            3)
                auto_configure_all
                ;;
            4)
                restore_default_config
                ;;
            5)
                return 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
        
        if [[ $choice != 5 ]]; then
            echo
            read -p "按回车键继续..."
        fi
    done
}

# 自动检测LED设备
auto_detect_leds() {
    echo -e "${CYAN}正在自动检测LED设备...${NC}"
    echo
    
    local detected_leds=($(get_all_leds))
    local led_count=${#detected_leds[@]}
    
    if [[ $led_count -eq 0 ]]; then
        echo -e "${YELLOW}未检测到LED设备，尝试使用备用方法...${NC}"
        # 尝试检测系统LED
        for led in power netdev; do
            if "$UGREEN_CLI" "$led" -status >/dev/null 2>&1; then
                detected_leds+=("$led")
                ((led_count++))
            fi
        done
        
        # 尝试检测硬盘LED
        for i in {1..8}; do
            if "$UGREEN_CLI" "disk$i" -status >/dev/null 2>&1; then
                detected_leds+=("disk$i")
                ((led_count++))
            fi
        done
    fi
    
    if [[ $led_count -gt 0 ]]; then
        echo -e "${GREEN}✓ 检测到 $led_count 个LED设备:${NC}"
        for led in "${detected_leds[@]}"; do
            echo "  - $led"
        done
        echo
        echo -e "${CYAN}LED设备检测完成${NC}"
    else
        echo -e "${RED}✗ 未检测到任何LED设备${NC}"
        echo "请检查LED控制程序是否正确安装"
    fi
}

# 自动检测硬盘映射
auto_detect_disk_mapping() {
    echo -e "${CYAN}正在自动检测硬盘映射...${NC}"
    echo
    
    if [[ ! -f "$UGREEN_CLI" ]]; then
        echo -e "${RED}✗ LED控制程序不存在${NC}"
        return 1
    fi
    
    # 检测所有块设备
    local disk_count=0
    local detected_disks=()
    
    while IFS= read -r disk; do
        if [[ -b "$disk" ]] && [[ "$disk" =~ ^/dev/sd[a-z]$ ]] || [[ "$disk" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]]; then
            # 跳过分区，只检测磁盘
            if ! [[ "$disk" =~ [0-9]+$ ]]; then
                detected_disks+=("$disk")
                ((disk_count++))
            fi
        fi
    done < <(lsblk -d -n -o NAME | sed 's|^|/dev/|')
    
    if [[ $disk_count -gt 0 ]]; then
        echo -e "${GREEN}✓ 检测到 $disk_count 个硬盘:${NC}"
        for disk in "${detected_disks[@]}"; do
            local model=$(lsblk -d -n -o MODEL "$disk" 2>/dev/null | head -1)
            local size=$(lsblk -d -n -o SIZE "$disk" 2>/dev/null | head -1)
            echo "  - $disk: ${model:-Unknown} (${size:-N/A})"
        done
        echo
        echo -e "${CYAN}硬盘检测完成${NC}"
        echo -e "${YELLOW}提示: 硬盘映射关系需要在安装时自动配置${NC}"
    else
        echo -e "${YELLOW}未检测到硬盘设备${NC}"
    fi
}

# 初始化所有LED
initialize_all_leds() {
    echo -e "${CYAN}正在初始化LED...${NC}"
    
    # 重新加载配置
    load_config
    
    # 获取所有LED
    local leds=($(get_all_leds))
    local initialized=0
    
    # 初始化电源LED
    if [[ -n "$UGREEN_CLI" ]] && [[ -x "$UGREEN_CLI" ]]; then
        echo "  初始化电源LED..."
        "$UGREEN_CLI" power -color ${POWER_COLOR:-128 128 128} -brightness ${DEFAULT_BRIGHTNESS:-64} -on >/dev/null 2>&1 && ((initialized++)) || true
        
        # 初始化网络LED（根据当前网络状态）
        echo "  初始化网络LED..."
        local network_status=$(check_network_status 2>/dev/null || echo "connected")
        local network_color
        case "$network_status" in
            "internet")
                network_color="${NETWORK_COLOR_INTERNET:-0 0 255}"
                ;;
            "connected")
                network_color="${NETWORK_COLOR_CONNECTED:-0 255 0}"
                ;;
            "disconnected")
                network_color="${NETWORK_COLOR_DISCONNECTED:-255 0 0}"
                ;;
            *)
                network_color="${NETWORK_COLOR_CONNECTED:-0 255 0}"
                ;;
        esac
        "$UGREEN_CLI" netdev -color $network_color -brightness ${DEFAULT_BRIGHTNESS:-64} -on >/dev/null 2>&1 && ((initialized++)) || true
        
        # 初始化硬盘LED
        if [[ -f "$CONFIG_DIR/disk_mapping.conf" ]]; then
            echo "  初始化硬盘LED..."
            local disk_count=0
            while IFS= read -r line; do
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line// }" ]] && continue
                
                if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
                    local device="${BASH_REMATCH[1]}"
                    local mapping="${BASH_REMATCH[2]}"
                    IFS='|' read -r hctl led_name serial model size <<< "$mapping"
                    
                    if [[ -n "$led_name" && "$led_name" != "none" ]]; then
                        # 检查硬盘状态并设置LED
                        if [[ -b "$device" ]]; then
                            # 硬盘存在，设置为健康状态颜色
                            "$UGREEN_CLI" "$led_name" -color ${DISK_COLOR_HEALTHY:-255 255 255} -brightness ${DEFAULT_BRIGHTNESS:-64} -on >/dev/null 2>&1 && ((initialized++)) || true
                        else
                            # 硬盘不存在，关闭LED
                            "$UGREEN_CLI" "$led_name" -off >/dev/null 2>&1 || true
                        fi
                        ((disk_count++))
                    fi
                fi
            done < "$CONFIG_DIR/disk_mapping.conf"
            
            # 处理未映射的LED（如disk4，当只有3个硬盘但检测到4个LED时）
            # 收集所有已映射的LED名称
            local mapped_leds=()
            while IFS= read -r line; do
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line// }" ]] && continue
                
                if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
                    local mapping="${BASH_REMATCH[2]}"
                    IFS='|' read -r hctl led_name serial model size <<< "$mapping"
                    if [[ -n "$led_name" && "$led_name" != "none" ]]; then
                        mapped_leds+=("$led_name")
                    fi
                fi
            done < "$CONFIG_DIR/disk_mapping.conf"
            
            # 关闭未映射的硬盘LED
            for led in "${leds[@]}"; do
                if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                    local found=false
                    for mapped_led in "${mapped_leds[@]}"; do
                        if [[ "$mapped_led" == "$led" ]]; then
                            found=true
                            break
                        fi
                    done
                    
                    # 如果LED不在映射中，关闭它
                    if [[ "$found" == "false" ]]; then
                        echo "  关闭未映射的LED: $led"
                        "$UGREEN_CLI" "$led" -off >/dev/null 2>&1 || true
                    fi
                fi
            done
        fi
    fi
    
    if [[ $initialized -gt 0 ]]; then
        echo -e "${GREEN}✓ 已初始化 $initialized 个LED${NC}"
    else
        echo -e "${YELLOW}警告: 未能初始化LED，请检查LED控制程序${NC}"
    fi
}

# 检查网络状态（用于初始化）
check_network_status() {
    local test_host="${NETWORK_TEST_HOST:-8.8.8.8}"
    local timeout="${NETWORK_TIMEOUT:-3}"
    
    # 检查是否有网络接口
    if ! ip route get "$test_host" >/dev/null 2>&1; then
        echo "disconnected"
        return 2
    fi
    
    # 检查是否能连接外网
    if ping -c 1 -W "$timeout" "$test_host" >/dev/null 2>&1; then
        echo "internet"
        return 0
    fi
    
    # 有路由但无法访问外网
    echo "connected"
    return 1
}

# 自动配置所有设置
auto_configure_all() {
    echo -e "${CYAN}正在自动配置所有设置...${NC}"
    echo
    
    # 1. 检测LED设备
    echo "步骤 1/4: 检测LED设备..."
    auto_detect_leds
    echo
    
    # 2. 检测硬盘映射
    echo "步骤 2/4: 检测硬盘映射..."
    auto_detect_disk_mapping
    echo
    
    # 3. 初始化LED
    echo "步骤 3/4: 初始化LED..."
    initialize_all_leds
    echo
    
    # 4. 检查并重启服务
    echo "步骤 4/4: 检查服务状态..."
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        echo -e "${GREEN}✓ 服务正在运行，正在重启以应用配置...${NC}"
        systemctl restart ugreen-led-monitor.service >/dev/null 2>&1 && \
            sleep 2 && \
            echo -e "${GREEN}✓ 服务已重启${NC}" || \
            echo -e "${YELLOW}警告: 服务重启失败，但配置已保存${NC}"
    else
        echo -e "${YELLOW}服务未运行，正在启动...${NC}"
        systemctl start ugreen-led-monitor.service >/dev/null 2>&1 && \
            sleep 2 && \
            echo -e "${GREEN}✓ 服务已启动${NC}" || \
            echo -e "${RED}✗ 服务启动失败${NC}"
    fi
    
    echo
    echo -e "${GREEN}✓ 自动配置完成${NC}"
    echo -e "${CYAN}提示: LED已根据当前状态初始化，守护进程将持续监控并更新LED状态${NC}"
}

# 恢复默认配置
restore_default_config() {
    echo -e "${YELLOW}警告: 此操作将恢复所有LED配置为默认值${NC}"
    read -p "确定要继续吗? (y/N): " confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        echo "已取消"
        return 0
    fi
    
    echo -e "${CYAN}正在恢复默认配置...${NC}"
    
    # 备份当前配置
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        cp "$CONFIG_DIR/led_config.conf" "$CONFIG_DIR/led_config.conf.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # 恢复默认颜色配置
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        # 使用sed更新配置值
        sed -i 's/^POWER_COLOR=.*/POWER_COLOR="128 128 128"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^NETWORK_COLOR_DISCONNECTED=.*/NETWORK_COLOR_DISCONNECTED="255 0 0"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^NETWORK_COLOR_CONNECTED=.*/NETWORK_COLOR_CONNECTED="0 255 0"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^NETWORK_COLOR_INTERNET=.*/NETWORK_COLOR_INTERNET="0 0 255"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^DISK_COLOR_HEALTHY=.*/DISK_COLOR_HEALTHY="255 255 255"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^DISK_COLOR_STANDBY=.*/DISK_COLOR_STANDBY="200 200 200"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^DISK_COLOR_UNHEALTHY=.*/DISK_COLOR_UNHEALTHY="255 0 0"/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^DEFAULT_BRIGHTNESS=.*/DEFAULT_BRIGHTNESS=64/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
        sed -i 's/^LOW_BRIGHTNESS=.*/LOW_BRIGHTNESS=32/' "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ 默认配置已恢复${NC}"
    echo -e "${YELLOW}提示: 请重启服务使配置生效: sudo systemctl restart ugreen-led-monitor.service${NC}"
}

# 灯光设置菜单
show_led_settings_menu() {
    while true; do
        # 重新加载配置以确保显示最新值
        load_config
        
        clear
        echo -e "${CYAN}================================${NC}"
        echo -e "${CYAN}灯光设置${NC}"
        echo -e "${CYAN}================================${NC}"
        echo
        echo "1. 设置电源LED颜色"
        echo "2. 设置网络LED颜色"
        echo "3. 设置硬盘LED颜色"
        echo "4. 设置亮度"
        echo "5. 查看当前配置"
        echo "6. 测试LED效果"
        echo "7. 返回主菜单"
        echo
        read -p "请选择功能 (1-7): " choice
        
        case $choice in
            1)
                set_power_led_color
                ;;
            2)
                set_network_led_color
                ;;
            3)
                set_disk_led_color
                ;;
            4)
                set_brightness
                ;;
            5)
                show_current_led_config
                ;;
            6)
                test_led_effects
                ;;
            7)
                return 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
        
        if [[ $choice != 7 ]]; then
            echo
            read -p "按回车键继续..."
        fi
    done
}

# 设置电源LED颜色
set_power_led_color() {
    # 重新加载配置
    load_config
    
    echo -e "${CYAN}设置电源LED颜色${NC}"
    echo
    echo "当前颜色: ${POWER_COLOR:-128 128 128}"
    echo "格式: R G B (每个值 0-255，用空格分隔)"
    echo "示例: 255 0 0 (红色), 0 255 0 (绿色), 0 0 255 (蓝色)"
    echo
    read -p "请输入RGB值 (留空使用默认值 128 128 128): " rgb_input
    
    if [[ -z "$rgb_input" ]]; then
        rgb_input="128 128 128"
    fi
    
    # 验证RGB格式
    if [[ ! "$rgb_input" =~ ^[0-9]+\ +[0-9]+\ +[0-9]+$ ]]; then
        echo -e "${RED}✗ 格式错误，请输入三个0-255之间的数字，用空格分隔${NC}"
        return 1
    fi
    
    # 验证RGB值范围
    local r g b
    read -r r g b <<< "$rgb_input"
    if [[ $r -lt 0 || $r -gt 255 || $g -lt 0 || $g -gt 255 || $b -lt 0 || $b -gt 255 ]]; then
        echo -e "${RED}✗ RGB值必须在0-255之间${NC}"
        return 1
    fi
    
    # 更新配置文件
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        if grep -q "^POWER_COLOR=" "$CONFIG_DIR/led_config.conf"; then
            sed -i "s|^POWER_COLOR=.*|POWER_COLOR=\"$rgb_input\"|" "$CONFIG_DIR/led_config.conf"
        else
            echo "POWER_COLOR=\"$rgb_input\"" >> "$CONFIG_DIR/led_config.conf"
        fi
        echo -e "${GREEN}✓ 电源LED颜色已更新为: $rgb_input${NC}"
        echo -e "${YELLOW}提示: 请重启服务使配置生效: sudo systemctl restart ugreen-led-monitor.service${NC}"
    else
        echo -e "${RED}✗ 配置文件不存在${NC}"
        return 1
    fi
}

# 设置网络LED颜色
set_network_led_color() {
    # 重新加载配置
    load_config
    
    echo -e "${CYAN}设置网络LED颜色${NC}"
    echo
    echo "当前配置:"
    echo "  断网状态: ${NETWORK_COLOR_DISCONNECTED:-255 0 0}"
    echo "  联网状态: ${NETWORK_COLOR_CONNECTED:-0 255 0}"
    echo "  外网状态: ${NETWORK_COLOR_INTERNET:-0 0 255}"
    echo
    echo "请选择要设置的状态:"
    echo "1. 断网状态 (默认: 255 0 0 红色)"
    echo "2. 联网状态 (默认: 0 255 0 绿色)"
    echo "3. 外网状态 (默认: 0 0 255 蓝色)"
    read -p "请选择 (1-3): " state_choice
    
    local config_var=""
    local default_value=""
    local state_name=""
    
    case $state_choice in
        1)
            config_var="NETWORK_COLOR_DISCONNECTED"
            default_value="255 0 0"
            state_name="断网状态"
            ;;
        2)
            config_var="NETWORK_COLOR_CONNECTED"
            default_value="0 255 0"
            state_name="联网状态"
            ;;
        3)
            config_var="NETWORK_COLOR_INTERNET"
            default_value="0 0 255"
            state_name="外网状态"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    echo
    echo "当前${state_name}颜色: ${!config_var:-$default_value}"
    read -p "请输入RGB值 (留空使用默认值 $default_value): " rgb_input
    
    if [[ -z "$rgb_input" ]]; then
        rgb_input="$default_value"
    fi
    
    # 验证RGB格式
    if [[ ! "$rgb_input" =~ ^[0-9]+\ +[0-9]+\ +[0-9]+$ ]]; then
        echo -e "${RED}✗ 格式错误，请输入三个0-255之间的数字，用空格分隔${NC}"
        return 1
    fi
    
    # 验证RGB值范围
    local r g b
    read -r r g b <<< "$rgb_input"
    if [[ $r -lt 0 || $r -gt 255 || $g -lt 0 || $g -gt 255 || $b -lt 0 || $b -gt 255 ]]; then
        echo -e "${RED}✗ RGB值必须在0-255之间${NC}"
        return 1
    fi
    
    # 更新配置文件
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        if grep -q "^${config_var}=" "$CONFIG_DIR/led_config.conf"; then
            sed -i "s|^${config_var}=.*|${config_var}=\"$rgb_input\"|" "$CONFIG_DIR/led_config.conf"
        else
            echo "${config_var}=\"$rgb_input\"" >> "$CONFIG_DIR/led_config.conf"
        fi
        echo -e "${GREEN}✓ ${state_name}颜色已更新为: $rgb_input${NC}"
        echo -e "${YELLOW}提示: 请重启服务使配置生效: sudo systemctl restart ugreen-led-monitor.service${NC}"
    else
        echo -e "${RED}✗ 配置文件不存在${NC}"
        return 1
    fi
}

# 设置硬盘LED颜色
set_disk_led_color() {
    # 重新加载配置
    load_config
    
    echo -e "${CYAN}设置硬盘LED颜色${NC}"
    echo
    echo "当前配置:"
    echo "  健康状态: ${DISK_COLOR_HEALTHY:-255 255 255}"
    echo "  休眠状态: ${DISK_COLOR_STANDBY:-200 200 200}"
    echo "  不健康状态: ${DISK_COLOR_UNHEALTHY:-255 0 0}"
    echo "  无硬盘状态: ${DISK_COLOR_NO_DISK:-0 0 0}"
    echo
    echo "请选择要设置的状态:"
    echo "1. 健康状态 (默认: 255 255 255 白色)"
    echo "2. 休眠状态 (默认: 200 200 200 淡白色)"
    echo "3. 不健康状态 (默认: 255 0 0 红色)"
    echo "4. 无硬盘状态 (默认: 0 0 0 关闭)"
    read -p "请选择 (1-4): " state_choice
    
    local config_var=""
    local default_value=""
    local state_name=""
    
    case $state_choice in
        1)
            config_var="DISK_COLOR_HEALTHY"
            default_value="255 255 255"
            state_name="健康状态"
            ;;
        2)
            config_var="DISK_COLOR_STANDBY"
            default_value="200 200 200"
            state_name="休眠状态"
            ;;
        3)
            config_var="DISK_COLOR_UNHEALTHY"
            default_value="255 0 0"
            state_name="不健康状态"
            ;;
        4)
            config_var="DISK_COLOR_NO_DISK"
            default_value="0 0 0"
            state_name="无硬盘状态"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    echo
    echo "当前${state_name}颜色: ${!config_var:-$default_value}"
    read -p "请输入RGB值 (留空使用默认值 $default_value): " rgb_input
    
    if [[ -z "$rgb_input" ]]; then
        rgb_input="$default_value"
    fi
    
    # 验证RGB格式
    if [[ ! "$rgb_input" =~ ^[0-9]+\ +[0-9]+\ +[0-9]+$ ]]; then
        echo -e "${RED}✗ 格式错误，请输入三个0-255之间的数字，用空格分隔${NC}"
        return 1
    fi
    
    # 验证RGB值范围
    local r g b
    read -r r g b <<< "$rgb_input"
    if [[ $r -lt 0 || $r -gt 255 || $g -lt 0 || $g -gt 255 || $b -lt 0 || $b -gt 255 ]]; then
        echo -e "${RED}✗ RGB值必须在0-255之间${NC}"
        return 1
    fi
    
    # 更新配置文件
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        if grep -q "^${config_var}=" "$CONFIG_DIR/led_config.conf"; then
            sed -i "s|^${config_var}=.*|${config_var}=\"$rgb_input\"|" "$CONFIG_DIR/led_config.conf"
        else
            echo "${config_var}=\"$rgb_input\"" >> "$CONFIG_DIR/led_config.conf"
        fi
        echo -e "${GREEN}✓ ${state_name}颜色已更新为: $rgb_input${NC}"
        echo -e "${YELLOW}提示: 请重启服务使配置生效: sudo systemctl restart ugreen-led-monitor.service${NC}"
    else
        echo -e "${RED}✗ 配置文件不存在${NC}"
        return 1
    fi
}

# 设置亮度
set_brightness() {
    # 重新加载配置
    load_config
    
    echo -e "${CYAN}设置LED亮度${NC}"
    echo
    echo "当前配置:"
    echo "  默认亮度: ${DEFAULT_BRIGHTNESS:-64}"
    echo "  低亮度: ${LOW_BRIGHTNESS:-32}"
    echo "  高亮度: ${HIGH_BRIGHTNESS:-128}"
    echo
    echo "请选择要设置的亮度类型:"
    echo "1. 默认亮度 (0-255，默认: 64)"
    echo "2. 低亮度 (0-255，默认: 32)"
    echo "3. 高亮度 (0-255，默认: 128)"
    read -p "请选择 (1-3): " brightness_choice
    
    local config_var=""
    local default_value=""
    local brightness_name=""
    
    case $brightness_choice in
        1)
            config_var="DEFAULT_BRIGHTNESS"
            default_value="64"
            brightness_name="默认亮度"
            ;;
        2)
            config_var="LOW_BRIGHTNESS"
            default_value="32"
            brightness_name="低亮度"
            ;;
        3)
            config_var="HIGH_BRIGHTNESS"
            default_value="128"
            brightness_name="高亮度"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    echo
    echo "当前${brightness_name}: ${!config_var:-$default_value}"
    read -p "请输入亮度值 (0-255，留空使用默认值 $default_value): " brightness_input
    
    if [[ -z "$brightness_input" ]]; then
        brightness_input="$default_value"
    fi
    
    # 验证亮度值
    if ! [[ "$brightness_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ 请输入0-255之间的数字${NC}"
        return 1
    fi
    
    if [[ $brightness_input -lt 0 || $brightness_input -gt 255 ]]; then
        echo -e "${RED}✗ 亮度值必须在0-255之间${NC}"
        return 1
    fi
    
    # 更新配置文件
    if [[ -f "$CONFIG_DIR/led_config.conf" ]]; then
        if grep -q "^${config_var}=" "$CONFIG_DIR/led_config.conf"; then
            sed -i "s|^${config_var}=.*|${config_var}=$brightness_input|" "$CONFIG_DIR/led_config.conf"
        else
            echo "${config_var}=$brightness_input" >> "$CONFIG_DIR/led_config.conf"
        fi
        echo -e "${GREEN}✓ ${brightness_name}已更新为: $brightness_input${NC}"
        echo -e "${YELLOW}提示: 请重启服务使配置生效: sudo systemctl restart ugreen-led-monitor.service${NC}"
    else
        echo -e "${RED}✗ 配置文件不存在${NC}"
        return 1
    fi
}

# 查看当前LED配置
show_current_led_config() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}当前LED配置${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    if [[ ! -f "$CONFIG_DIR/led_config.conf" ]]; then
        echo -e "${RED}配置文件不存在${NC}"
        return 1
    fi
    
    # 重新加载配置
    source "$CONFIG_DIR/led_config.conf" 2>/dev/null || true
    
    echo -e "${BLUE}电源LED:${NC}"
    echo "  颜色: ${POWER_COLOR:-128 128 128}"
    echo
    
    echo -e "${BLUE}网络LED:${NC}"
    echo "  断网: ${NETWORK_COLOR_DISCONNECTED:-255 0 0}"
    echo "  联网: ${NETWORK_COLOR_CONNECTED:-0 255 0}"
    echo "  外网: ${NETWORK_COLOR_INTERNET:-0 0 255}"
    echo
    
    echo -e "${BLUE}硬盘LED:${NC}"
    echo "  健康: ${DISK_COLOR_HEALTHY:-255 255 255}"
    echo "  休眠: ${DISK_COLOR_STANDBY:-200 200 200}"
    echo "  不健康: ${DISK_COLOR_UNHEALTHY:-255 0 0}"
    echo "  无硬盘: ${DISK_COLOR_NO_DISK:-0 0 0}"
    echo
    
    echo -e "${BLUE}亮度设置:${NC}"
    echo "  默认: ${DEFAULT_BRIGHTNESS:-64}"
    echo "  低亮度: ${LOW_BRIGHTNESS:-32}"
    echo "  高亮度: ${HIGH_BRIGHTNESS:-128}"
    echo
}

# 测试LED效果
test_led_effects() {
    # 重新加载配置
    load_config
    
    echo -e "${CYAN}测试LED效果${NC}"
    echo
    echo "此功能将依次测试各个LED，每个LED显示3秒"
    echo
    read -p "确定要继续吗? (y/N): " confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        echo "已取消"
        return 0
    fi
    
    local test_colors=("255 0 0" "0 255 0" "0 0 255" "255 255 255" "255 255 0" "255 0 255" "0 255 255")
    local color_names=("红色" "绿色" "蓝色" "白色" "黄色" "紫色" "青色")
    
    # 测试电源LED
    echo -e "${CYAN}测试电源LED...${NC}"
    for i in "${!test_colors[@]}"; do
        echo "  显示 ${color_names[$i]}..."
        "$UGREEN_CLI" power -color ${test_colors[$i]} -brightness 64 -on 2>/dev/null || true
        sleep 1
    done
    # 恢复默认
    "$UGREEN_CLI" power -color ${POWER_COLOR:-128 128 128} -brightness ${DEFAULT_BRIGHTNESS:-64} -on 2>/dev/null || true
    echo
    
    # 测试网络LED
    echo -e "${CYAN}测试网络LED...${NC}"
    for i in "${!test_colors[@]}"; do
        echo "  显示 ${color_names[$i]}..."
        "$UGREEN_CLI" netdev -color ${test_colors[$i]} -brightness 64 -on 2>/dev/null || true
        sleep 1
    done
    # 恢复默认
    "$UGREEN_CLI" netdev -color ${NETWORK_COLOR_CONNECTED:-0 255 0} -brightness ${DEFAULT_BRIGHTNESS:-64} -on 2>/dev/null || true
    echo
    
    # 测试硬盘LED
    echo -e "${CYAN}测试硬盘LED...${NC}"
    local disk_leds=($(get_all_leds))
    for led in "${disk_leds[@]}"; do
        if [[ "$led" =~ ^disk[0-9]+$ ]]; then
            echo "  测试 $led..."
            for i in "${!test_colors[@]}"; do
                "$UGREEN_CLI" "$led" -color ${test_colors[$i]} -brightness 64 -on 2>/dev/null || true
                sleep 0.5
            done
            # 恢复默认
            "$UGREEN_CLI" "$led" -color ${DISK_COLOR_HEALTHY:-255 255 255} -brightness ${DEFAULT_BRIGHTNESS:-64} -on 2>/dev/null || true
        fi
    done
    
    echo
    echo -e "${GREEN}✓ LED测试完成${NC}"
}

# 主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}UGREEN LED 控制器 v${VERSION}${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo "1. 关闭所有LED"
    echo "2. 打开所有LED"
    echo "3. 节能模式"
    echo "4. 设置开机自启"
    echo "5. 关闭开机自启"
    echo "6. 查看映射状态"
    echo "7. 智能设置"
    echo "8. 灯光设置"
    echo "9. 退出"
    echo
    read -p "请选择功能 (1-9): " choice
    
    case $choice in
        1)
            turn_off_all_leds
            ;;
        2)
            turn_on_all_leds
            ;;
        3)
            power_save_mode
            ;;
        4)
            enable_autostart
            ;;
        5)
            disable_autostart
            ;;
        6)
            show_mapping_status
            ;;
        7)
            show_smart_settings_menu
            ;;
        8)
            show_led_settings_menu
            ;;
        9)
            echo -e "${GREEN}感谢使用！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 处理命令行参数
case "${1:-}" in
    "off"|"关闭")
        load_config
        check_installation
        turn_off_all_leds
        ;;
    "on"|"打开")
        load_config
        check_installation
        turn_on_all_leds
        ;;
    "power-save"|"节能")
        load_config
        check_installation
        power_save_mode
        ;;
    "enable"|"启用")
        enable_autostart
        ;;
    "disable"|"禁用")
        disable_autostart
        ;;
    "status"|"状态")
        load_config
        show_mapping_status
        ;;
    "start")
        systemctl start ugreen-led-monitor.service
        ;;
    "stop")
        systemctl stop ugreen-led-monitor.service
        ;;
    "restart")
        systemctl restart ugreen-led-monitor.service
        ;;
    "--help"|"-h")
        echo "UGREEN LED 控制器 v$VERSION"
        echo
        echo "用法: sudo LLLED [命令]"
        echo
        echo "命令:"
        echo "  off, 关闭        - 关闭所有LED"
        echo "  on, 打开         - 打开所有LED"
        echo "  power-save, 节能 - 启用节能模式"
        echo "  enable, 启用     - 设置开机自启"
        echo "  disable, 禁用    - 关闭开机自启"
        echo "  status, 状态     - 查看映射状态"
        echo "  start            - 启动服务"
        echo "  stop             - 停止服务"
        echo "  restart          - 重启服务"
        echo
        echo "不使用参数则进入交互模式"
        ;;
    "")
        load_config
        check_installation
        while true; do
            show_main_menu
        done
        ;;
    *)
        echo "未知参数: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac
