# LLLED 智能 LED 控制系统 v3.3.0

专为绿联 UGREEN 系列 NAS 设备设计的智能 LED 控制系统，支持 HCTL 自动映射、全局版本管理、智能颜色配置和增强的后台服务管理。

```bash
# 一键安装LLLED系统 v3.3.0
curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash

# 安装完成后，使用主入口命令：
sudo LLLED                # 🎛️ 主控制面板 (推荐)
```

## 🔧 支持设备

-   UGREEN DX4600 Pro (4 盘位)
-   UGREEN DX4700+ (4 盘位)
-   UGREEN DXP2800 (2 盘位)
-   UGREEN DXP4800 (4 盘位)
-   UGREEN DXP4800 Plus (4 盘位)
-   UGREEN DXP6800 Pro (6 盘位)
-   UGREEN DXP8800 Plus (8 盘位)
-   更多型号持续支持中...

## ✨ v3.3.0 全新功能特性

### 🔄 **服务稳定性增强**

-   全面超时保护：所有 LED 检测和控制操作均配备超时机制
-   信号处理优化：完善的 TERM/INT/QUIT 信号处理，防止僵尸进程
-   服务启动修复：修复 systemd 服务配置，确保稳定启动
-   循环保护：内置迭代限制，防止无限循环消耗资源

### 🆕 **全局版本管理**

-   **统一版本号**: 所有组件统一使用 v3.0.0 版本号
-   **版本追踪**: 每个配置文件和脚本都包含版本信息
-   **升级管理**: 智能版本检测和平滑升级

### 🆕 **HCTL 硬盘位置映射全局配置化**

-   **自动检测**: 运行时自动获取硬盘 HCTL 信息并保存
-   **智能映射**: 基于 HCTL 信息的精确硬盘到 LED 映射
-   **配置持久化**: 自动保存映射关系到配置文件
-   **增量更新**: 支持硬盘变化的自动检测和更新

### 🎨 **智能颜色配置系统**

#### 💡 **电源键灯光颜色**

-   **开机状态**: 淡白色 (128 128 128) - 不太亮，避免刺眼
-   **待机状态**: 关闭 (0 0 0) - 简化为两种状态
-   **休眠状态**: 关闭 (0 0 0) - 简化为两种状态
-   **关机状态**: 关闭 (0 0 0)

#### � **LAN 网络灯光颜色**

-   **网络连接**: 绿色 (0 255 0)
-   **网络活动**: 青色 (0 255 255)
-   **网络错误**: 红色 (255 0 0)
-   **网络断开**: 橙色 (255 165 0)

#### 💾 **硬盘活动颜色**

-   **硬盘活动**: 绿色 (0 255 0)
-   **硬盘空闲**: 浅绿色 (50 205 50)
-   **硬盘休眠**: 黄色 (255 255 0)
-   **硬盘错误**: 红色 (255 0 0)
-   **硬盘警告**: 橙色 (255 165 0)

### 🤖 **增强的后台服务管理**

#### 🔍 **智能硬盘状态检测**

-   **hdparm 检测**: 使用 `hdparm -C` 精确检测硬盘状态
-   **错误自愈**: 检测失败时自动调用 HCTL 重映射
-   **状态缓存**: 只在状态变化时更新 LED，提高效率
-   **定期更新**: 每小时自动更新 HCTL 映射关系

#### 🛠️ **服务管理功能**

-   **启动/停止/重启**: 完整的服务生命周期管理
-   **开机自启**: 支持 systemd 自启动配置
-   **状态监控**: 实时服务状态查看
-   **日志管理**: 详细的日志记录和查看功能
-   **实时预览**: 配置时立即预览 LED 效果

#### 📊 **智能状态模式**

-   🟢 **活动状态**: 绿色高亮 (正在工作)
-   🟡 **空闲状态**: 黄色低亮 (待机)
-   🔴 **错误状态**: 红色闪烁 (故障)
-   ⚫ **离线状态**: 灯光关闭 (未检测到)

#### 🤖 **智能监控系统**

-   **网络活动监控**: 实时检测网络传输状态
-   **硬盘读写监控**: 基于 I/O 统计的实时硬盘活动检测
-   **系统负载监控**: 根据 CPU 负载调整电源 LED 状态
-   **SMART 健康检测**: 监控硬盘健康状态并及时报警

### 🔧 **v2.0.0 核心优化功能**

#### 🔆 **HCTL 智能映射系统**

-   基于硬盘 HCTL (Host:Channel:Target:LUN) 信息精确映射 LED 位置
-   三层保护机制：动态检测 → 配置映射 → 智能推断
-   支持 4/6/8 盘位设备自动适配

#### 🔍 **多盘位智能检测**

-   自动检测和适配不同型号设备的 LED 配置
-   支持 4-8 个硬盘 LED 动态识别
-   向后兼容传统配置文件

#### 📊 **增强状态监控**

-   详细的硬盘信息显示 (型号/容量/健康状态)
-   实时状态统计 (活动/空闲/错误/离线数量)
-   SMART 温度监控和阈值报警

## 🎯 **主要功能**

### 💾 **硬盘状态监控**

基于用户自定义颜色配置的智能硬盘状态显示：

-   **读写活动**: 用户自定义活动颜色，高亮显示
-   **空闲待机**: 用户自定义空闲颜色，低亮显示
-   **SMART 异常**: 用户自定义错误颜色，闪烁警告
-   **设备离线**: 灯光关闭，无 LED 显示

### 🌐 **网络状态监控**

实时网络活动检测和 LED 状态显示：

-   **数据传输**: 检测网络流量变化，活动状态显示
-   **网络空闲**: 网络连通但无活动，空闲状态显示
-   **连接错误**: 网络不通或故障，错误状态闪烁
-   **接口离线**: 网络接口未激活，灯光关闭

### ⚡ **电源状态监控**

基于系统负载的智能电源 LED 控制：

-   **高负载**: 系统繁忙时显示正常状态颜色
-   **低负载**: 系统空闲时显示待机状态颜色
-   **系统异常**: 错误状态颜色显示

### 🌈 **LED 效果模式**

-   🎨 **彩虹效果**: 7 色 LED 循环跑马灯 (支持动态 LED 检测)
-   🌙 **夜间模式**: 全部 LED 白色低亮度
-   💤 **节能模式**: 仅保持系统 LED，关闭硬盘 LED
-   ⚡ **实时监控**: 可配置刷新间隔的实时状态显示

## 🎮 **使用界面**

### 📱 **LLLED 快捷菜单** (主入口)

```bash
sudo llled-menu
```

-   🎨 颜色配置菜单 - 自定义 LED 颜色
-   🤖 智能状态监控 - 基于颜色配置的实时监控
-   🎭 应用颜色主题 - 立即应用当前颜色设置
-   🌈 测试状态效果 - 演示所有状态颜色
-   💡 LED 控制功能 - 硬盘状态、彩虹效果等
-   ⚙️ 系统功能 - 完整 LLLED 系统访问

### 🎨 **颜色配置界面**

```bash
sudo llled-menu color
# 或
sudo bash /opt/ugreen-led-controller/scripts/color_menu.sh
```

-   电源键 LED 颜色配置 (正常/待机/错误)
-   网络 LED 颜色配置 (活动/空闲/错误/离线)
-   硬盘 LED 颜色配置 (活动/空闲/错误/离线)
-   实时颜色预览和效果测试
-   颜色主题保存和应用

### 🤖 **智能监控界面**

```bash
sudo llled-menu monitor
# 或
sudo bash /opt/ugreen-led-controller/scripts/smart_status_monitor.sh -m
```

-   持续监控模式 (后台运行)
-   状态查看模式 (当前状态显示)
-   一次性更新模式 (立即更新 LED 状态)

## 📋 系统要求

-   **操作系统**: Linux 系统 (Debian/Ubuntu/TrueNAS/Unraid 等)
-   **内核模块**: 已加载 `i2c-dev` 模块
-   **权限要求**: 需要 root 权限访问 I2C 设备
-   **硬件要求**: 支持的 UGREEN NAS 设备
-   **依赖工具**: `smartctl` (可选，用于硬盘健康检测)

## 📥 安装方法

### 🚀 **推荐方式：一键安装** (仅此一种安装方式)

```bash
# 在UGREEN设备上运行以下命令：
curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash
```

安装完成后会自动创建以下命令：

-   `sudo llled-menu` - 主入口菜单 (推荐)
-   `sudo LLLED` - 传统 LLLED 主程序

## 🎯 **快速开始**

### 1️⃣ **安装系统**

```bash
curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash
```

### 2️⃣ **打开功能菜单**

```bash
sudo llled-menu
```

### 3️⃣ **配置 LED 颜色**

选择菜单中的"颜色配置菜单"，按照提示自定义各种 LED 颜色

### 4️⃣ **启动智能监控**

选择菜单中的"智能状态监控"，享受个性化的 LED 状态显示

## 💡 **使用技巧**

### 🎨 **颜色配置建议**

-   **活动状态**: 建议使用绿色或蓝色，亮度 128
-   **空闲状态**: 建议使用黄色或白色，亮度 32
-   **错误状态**: 建议使用红色，亮度 255+闪烁
-   **离线状态**: 建议选择"关闭"，完全不亮

### 🔧 **高级配置**

```bash
# 配置文件位置
/opt/ugreen-led-controller/config/led_mapping.conf      # LED映射配置
/opt/ugreen-led-controller/config/color_themes.conf     # 颜色主题配置

# 日志文件
/var/log/llled_status_monitor.log                       # 智能监控日志
```

### 🚨 **故障排除**

```bash
# 验证设备兼容性
sudo bash /opt/ugreen-led-controller/verify_detection.sh

# 检查LED控制程序
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status

# 测试单个LED
sudo /opt/ugreen-led-controller/ugreen_leds_cli disk1 -color "255 0 0" -on
```

## 🔄 **更新日志**

### v2.1.0 (2025-09-06) - 颜色自定义版

-   ✅ 全新 LED 颜色配置菜单系统
-   ✅ 13 种预设颜色 + 自定义 RGB 支持
-   ✅ 4 种状态模式的完整颜色配置
-   ✅ 实时颜色预览和效果测试
-   ✅ 智能状态监控系统
-   ✅ LLLED 快捷菜单主入口
-   ✅ 完全重构的用户界面

### v2.0.0 (2025-09-05) - HCTL 优化版

-   ✅ HCTL 智能映射系统
-   ✅ 多盘位动态检测 (4-8 盘位)
-   ✅ 三层保护检测机制
-   ✅ 优化的硬盘状态监控
-   ✅ 智能错误处理和恢复

## 🔧 **故障排除**

### LED 控制功能失效

如果遇到 LED 控制不工作的问题，请按以下步骤排查：

#### 1. 快速测试

```bash
# 运行快速LED功能测试
sudo /opt/ugreen-led-controller/quick_led_test.sh
```

#### 2. 检查系统环境

```bash
# 检查i2c模块
lsmod | grep i2c_dev

# 如果未加载，手动加载
sudo modprobe i2c-dev

# 检查LED状态
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status
```

#### 3. 手动控制测试

```bash
# 测试LED控制
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -on
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -off
```

### 常见问题

-   **权限问题**: 确保使用 `sudo` 运行所有 LED 控制命令
-   **硬件兼容性**: 确认使用的是支持的 UGREEN NAS 型号
-   **模块加载**: 确保 `i2c-dev` 模块已正确加载

详细故障排除指南请参考: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 🤝 **贡献和支持**

### 📞 **获取帮助**

-   **GitHub Issues**: [提交问题](https://github.com/BearHero520/LLLEDTEST/issues)
-   **项目主页**: https://github.com/BearHero520/LLLEDTEST

### 🔗 **相关项目**

-   **ugreen_leds_controller**: https://github.com/miskcoo/ugreen_leds_controller
-   **UGREEN 官方支持**: https://www.ugreen.com/

## 📄 **许可证**

本项目基于 MIT 许可证开源，详见 [LICENSE](LICENSE) 文件。

---

**🎯 让你的 UGREEN NAS 拥有个性化的 LED 灯光效果！**

**💡 一键安装，开箱即用，支持完全自定义的 LED 颜色配置！**
