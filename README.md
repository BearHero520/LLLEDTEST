# 绿联 LED 控制工具 - 优化版 v2.0.0

专为绿联 UGREEN 系列 NAS 设备设计的 LED 控制工具，支持 HCTL 智能映射、多 LED 检测和智能硬盘状态监控。

## 🔧 支持设备

-   UGREEN DX4600 Pro
-   UGREEN DX4700+
-   UGREEN DXP2800
-   UGREEN DXP4800
-   UGREEN DXP4800 Plus
-   UGREEN DXP6800 Pro
-   UGREEN DXP8800 Plus

## ✨ 功能特性

### 🆕 **v2.0.0 优化功能**

-   🔆 **HCTL 智能映射**: 基于硬盘 HCTL (Host:Channel:Target:LUN) 信息精确映射 LED 位置
-   🔍 **智能多 LED 检测**: 自动检测和适配不同型号设备的 LED 配置 (支持 4-8 个硬盘 LED)
-   📊 **优化状态显示**: 增强的硬盘状态监控，支持详细的设备信息显示
-   ⚙️ **交互式映射配置**: 多种映射方式可选，支持手动精确配置
-   �️ **智能错误处理**: 先检测 LED 再检测硬盘，优化检测流程
-   📈 **实时状态统计**: 显示活动/空闲/错误/离线硬盘数量统计

### 💾 **硬盘状态监控**

-   🟢 **活动状态**: 绿色高亮 (255 亮度) - 硬盘正在读写
-   🟡 **空闲状态**: 黄色低亮 (64 亮度) - 硬盘空闲待命
-   🔴 **错误状态**: 红色闪烁 - 硬盘 SMART 检测异常
-   ⚫ **离线状态**: 灰色微亮 (32 亮度) - 硬盘离线或未连接

### 🌈 **LED 效果模式**

-   🎨 **彩虹效果**: 7 色 LED 循环跑马灯
-   🌙 **夜间模式**: 全部 LED 白色低亮度
-   💤 **节能模式**: 仅保持系统 LED，关闭硬盘 LED
-   ⚡ **实时监控**: 2 秒刷新间隔的实时硬盘活动显示

### 🔧 **高级功能**

-   📋 **硬盘映射管理**: 显示详细的 HCTL 信息、序列号、型号、容量
-   🔄 **自动重映射**: 基于 HCTL 优化的自动映射算法
-   🎯 **手动精确配置**: 逐个硬盘的 LED 位置配置
-   🗑️ **一键卸载**: 完全清理安装文件和配置

## 📋 系统要求

-   Linux 系统 (Debian/Ubuntu/TrueNAS 等)
-   已加载 `i2c-dev` 模块
-   Root 权限
-   绿联 UGREEN 系列设备

## 🚀 快速安装

### 一键安装 (推荐)

```bash
# 方法1: 使用wget (防缓存版本)
wget -O- "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash

# 方法2: 使用curl (防缓存版本)
curl -sSL "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash

# 安装完成后，直接使用
sudo LLLED
```

### 手动安装 LED 控制程序

如果自动安装失败，可手动安装 LED 控制程序：

```bash
# 切换到root用户
sudo -i

# 下载LED控制程序到/usr/bin
cd /usr/bin
wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
chmod +x ugreen_leds_cli

# 测试是否可用 (成功会输出LED状态)
./ugreen_leds_cli all -status

# 退出root用户
exit
```

## 💡 使用方法

### 启动交互式控制面板

```bash
sudo LLLED
```

### 快速命令

```bash
sudo LLLED --disk-status    # 智能硬盘状态显示
sudo LLLED --monitor        # 实时硬盘活动监控
sudo LLLED --mapping        # 显示硬盘映射详情
sudo LLLED --on             # 打开所有LED
sudo LLLED --off            # 关闭所有LED
sudo LLLED --system         # 恢复系统LED (电源+网络)
sudo LLLED --version        # 显示版本信息
sudo LLLED --help           # 查看完整帮助
```

## 📋 控制面板菜单

```
================================
绿联LED控制工具 v2.0.0
(优化版 - HCTL映射+智能检测)
================================

支持的UGREEN设备型号:
  - UGREEN DX4600 Pro
  - UGREEN DX4700+
  - UGREEN DXP2800
  - UGREEN DXP4800
  - UGREEN DXP4800 Plus
  - UGREEN DXP6800 Pro
  - UGREEN DXP8800 Plus

可用LED: power netdev disk1 disk2 disk3 disk4
硬盘数量: 4

1) 关闭所有LED
2) 打开所有LED
3) 智能硬盘状态显示        ⭐ 推荐
4) 实时硬盘活动监控        ⭐ 推荐
5) 彩虹效果
6) 节能模式
7) 夜间模式
8) 显示硬盘映射            📊 优化
9) 配置硬盘映射            🔧 新功能
d) 删除脚本 (卸载)         🗑️ 安全卸载
s) 恢复系统LED (电源+网络)
0) 退出
==================================
```

## 🔧 硬盘映射配置

### HCTL 智能映射原理

系统基于硬盘的 HCTL (Host:Channel:Target:LUN) 信息自动映射到对应 LED：

```bash
# 查看系统硬盘HCTL信息
lsblk -S -x hctl -o name,hctl,serial,model,size

# 示例输出:
NAME HCTL       SERIAL          MODEL           SIZE
sda  0:0:0:0    WL2042QT        ST2000DM008     1.8T
sdb  1:0:0:0    Z1Z5LKT4        WD20EFRX        1.8T
sdc  2:0:0:0    WD-WMC130E15K5E WD30EFRX        2.7T
sdd  3:0:0:0    V6JLAW9V        ST4000DM004     3.6T
```

**映射规则:**

-   HCTL `0:0:0:0` → `disk1` LED
-   HCTL `1:0:0:0` → `disk2` LED
-   HCTL `2:0:0:0` → `disk3` LED
-   HCTL `3:0:0:0` → `disk4` LED

### 交互式映射配置

选择菜单项 `9) 配置硬盘映射`，提供多种配置方式：

1. **自动重新映射** - 基于 HCTL 优化重新分配
2. **手动配置每个硬盘** - 逐个指定 LED 位置
3. **恢复默认映射** - 按检测顺序分配
4. **清除所有映射** - 移除所有硬盘 LED 映射

### 硬盘状态显示示例

```
=== 智能硬盘状态显示 ===
时间: 2025-09-05 14:30:25
=====================================
设备         LED      状态      HCTL         设备信息
---------------------------------------------------------------------
/dev/sda     disk1    ●活动     0:0:0:0
    HCTL:0:0:0:0 Serial:WL2042QT Model:ST2000DM008 Size:1.8T

/dev/sdb     disk2    ●空闲     1:0:0:0
    HCTL:1:0:0:0 Serial:Z1Z5LKT4 Model:WD20EFRX Size:1.8T

/dev/sdc     disk3    ●空闲     2:0:0:0
    HCTL:2:0:0:0 Serial:WD-WMC130E15K5E Model:WD30EFRX Size:2.7T

/dev/sdd     disk4    ●离线     3:0:0:0
    HCTL:3:0:0:0 Serial:V6JLAW9V Model:ST4000DM004 Size:3.6T

=====================================
状态统计:
  活动: 1 | 空闲: 2 | 错误: 0 | 离线: 1
  总计: 4 个硬盘，4 个LED可用
✓ 智能硬盘状态已更新到LED显示
```

NAME HCTL SERIAL
sda 0:0:0:0 WL2042QT -> disk1
sdb 1:0:0:0 Z1Z5LKT4 -> disk2
sdc 2:0:0:0 WD-WMC130E15K5E -> disk3
sdd 3:0:0:0 V6JLAW9V -> disk4

````

### 交互式配置

在控制面板中选择 "9) 配置硬盘映射" 进行交互式配置：

-   自动检测所有可用 LED 和硬盘
-   支持 HCTL 智能自动映射
-   支持手动逐个配置
-   支持 LED 测试功能
-   自动备份旧配置

## 🎯 智能功能

### 硬盘状态显示

-   🟢 **活动状态**: 绿色高亮 (正在读写)
-   🟡 **空闲状态**: 黄色低亮 (待机)
-   🔴 **错误状态**: 红色闪烁 (故障)
-   ⚫ **离线状态**: 灰色微亮 (未检测到)

### 系统状态显示

-   💚 **电源 LED**: 绿色常亮 (系统正常)
-   🔵 **网络 LED**: 蓝色常亮 (已连接) / 🟠 橙色常亮 (未连接)

## 🛠️ 高级功能

### 命令行工具

除了交互式界面，还支持命令行直接操作：

```bash
# 显示版本和支持设备
sudo LLLED --version

# 系统检测
sudo LLLED --mapping       # 显示当前硬盘映射

# LED控制
sudo LLLED --off           # 关闭所有LED
sudo LLLED --on            # 打开所有LED

# 智能监控
sudo LLLED --disk-status   # 智能硬盘状态显示
sudo LLLED --monitor       # 实时硬盘活动监控

# 系统恢复
sudo LLLED --system        # 恢复系统LED状态
````

### 硬盘映射配置工具

```bash
# 使用优化版配置工具
sudo /opt/ugreen-led-controller/scripts/configure_mapping_optimized.sh --auto      # HCTL自动映射
sudo /opt/ugreen-led-controller/scripts/configure_mapping_optimized.sh --configure # 交互式配置
sudo /opt/ugreen-led-controller/scripts/configure_mapping_optimized.sh --test disk1 # 测试LED
```

## 脚本说明

## 📁 项目结构

| 文件/目录                                | 功能描述                   |
| ---------------------------------------- | -------------------------- |
| `ugreen_led_controller_optimized.sh`     | 优化版主控制脚本 ⭐ 新版本 |
| `ugreen_led_controller.sh`               | 标准版主控制脚本           |
| `quick_install.sh`                       | 一键安装脚本               |
| `uninstall.sh`                           | 卸载脚本                   |
| `scripts/configure_mapping_optimized.sh` | 优化版硬盘映射配置工具     |
| `scripts/configure_mapping.sh`           | 标准版硬盘映射配置工具     |
| `scripts/disk_status_leds.sh`            | 硬盘状态监控显示           |
| `scripts/turn_off_all_leds.sh`           | 关闭所有 LED               |
| `scripts/rainbow_effect.sh`              | 彩虹跑马灯效果             |
| `scripts/smart_disk_activity.sh`         | 智能硬盘活动监控           |
| `config/disk_mapping.conf`               | 硬盘映射配置文件           |
| `config/led_mapping.conf`                | LED 映射配置文件           |

## 🔧 故障排除

### LED 控制程序未找到

如果提示找不到 LED 控制程序，请手动安装：

```bash
sudo -i
cd /usr/bin
wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
chmod +x ugreen_leds_cli
./ugreen_leds_cli all -status  # 测试
exit
```

### 硬盘映射不正确

1. 使用交互式配置工具：

```bash
sudo LLLED  # 选择菜单 "9) 配置硬盘映射"
```

2. 或使用优化版配置工具：

```bash
sudo /opt/ugreen-led-controller/scripts/configure_mapping_optimized.sh --auto
```

3. 查看硬盘 HCTL 信息：

```bash
lsblk -S -x hctl -o name,hctl,serial
```

### 权限问题

确保以 root 权限运行：

```bash
sudo LLLED
```

### I2C 模块未加载

手动加载 I2C 模块：

```bash
sudo modprobe i2c-dev
```

## 🗑️ 卸载

### 完全卸载

```bash
# 方法1: 使用控制面板卸载
sudo LLLED  # 选择菜单 "d) 删除脚本 (卸载)"

# 方法2: 使用安装目录的卸载脚本
sudo /opt/ugreen-led-controller/uninstall.sh

# 方法3: 直接下载卸载脚本
wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/uninstall.sh | sudo bash

# 方法4: 强制卸载 (不询问确认)
sudo /opt/ugreen-led-controller/uninstall.sh --force
```

卸载会：

-   删除所有程序文件
-   删除命令链接
-   可选择保留或删除配置文件
-   恢复系统 LED 状态

## 🆕 更新日志

### v2.0.0 (优化版) - 2025-09-05

-   ✨ 新增 HCTL 智能硬盘映射
-   🔍 智能检测可用 LED 和硬盘设备
-   📋 优化交互式配置界面
-   🎯 支持更多 UGREEN 设备型号
-   🛠️ 增强错误处理和用户体验
-   🗑️ 增加一键卸载功能

### v1.2.0 - 2025-09-04

-   🚀 一键安装脚本
-   🔧 改进配置文件管理
-   � 完善文档说明

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发环境

```bash
git clone https://github.com/BearHero520/LLLED.git
cd LLLED
```

### 测试

```bash
# 测试LED控制程序
sudo ./ugreen_leds_cli all -status

# 测试主程序
sudo ./ugreen_led_controller_optimized.sh --help
```

## 📄 许可证

本项目基于 MIT 许可证开源。

## 🙏 致谢

-   [miskcoo/ugreen_leds_controller](https://github.com/miskcoo/ugreen_leds_controller) - 提供核心 LED 控制程序
-   UGREEN 社区 - 提供设备支持和反馈

## 📞 支持

-   🐛 [提交 Bug](https://github.com/BearHero520/LLLED/issues)
-   💡 [功能请求](https://github.com/BearHero520/LLLED/issues)
-   📖 [查看文档](https://github.com/BearHero520/LLLED/wiki)
-   💬 [讨论交流](https://github.com/BearHero520/LLLED/discussions)

---

**⭐ 如果这个项目对您有帮助，请给个 Star 支持一下！**
