# UGREEN LED 控制器 v4.0.0

专为绿联 UGREEN 系列 NAS 设备设计的 LED 控制系统（简化重构版）

## 快速安装

```bash
# 一键安装
curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLEDTEST/main/quick_install.sh | sudo bash

# 安装完成后自动启动服务
# 使用主控制命令：
sudo LLLED
```

## 支持设备

-   UGREEN DX4600 Pro (4 盘位)
-   UGREEN DX4700+ (4 盘位)
-   UGREEN DXP2800 (2 盘位)
-   UGREEN DXP4800 (4 盘位)
-   UGREEN DXP4800 Plus (4 盘位)
-   UGREEN DXP6800 Pro (6 盘位)
-   UGREEN DXP8800 Plus (8 盘位)

## 主要功能

### 核心功能菜单

1. **关闭所有 LED** - 关闭所有 LED 指示灯
2. **打开所有 LED** - 打开所有 LED 指示灯
3. **节能模式** - 启用低亮度节能模式
4. **设置开机自启** - 启用系统服务开机自启
5. **关闭开机自启** - 禁用系统服务开机自启
6. **查看映射状态** - 查看 LED 和硬盘映射关系

### LED 映射说明

-   **4800plus 等设备**: 通常为 1 个电源灯 + 1 个网络灯 + 4 个机械硬盘灯
-   **M2 SSD**: 通常没有对应的 LED
-   **映射关系**: 在安装时自动检测并配置，基于 HCTL 顺序建立映射

### 颜色配置

所有颜色都可以在配置文件中自定义（`/opt/ugreen-led-controller/config/led_config.conf`）：

#### 电源 LED

-   `POWER_COLOR`: 电源灯颜色（默认: 128 128 128 淡白色）

#### 网络 LED

-   `NETWORK_COLOR_DISCONNECTED`: 断网状态（默认: 255 0 0 红色）
-   `NETWORK_COLOR_CONNECTED`: 联网状态（默认: 0 255 0 绿色）
-   `NETWORK_COLOR_INTERNET`: 连接外网状态（默认: 0 0 255 蓝色）

#### 硬盘 LED

-   `DISK_COLOR_HEALTHY`: 活跃/健康状态（默认: 255 255 255 白色）
-   `DISK_COLOR_STANDBY`: 休眠状态（默认: 200 200 200 淡白色）
-   `DISK_COLOR_UNHEALTHY`: 不健康状态（默认: 255 0 0 红色）
-   `DISK_COLOR_NO_DISK`: 无硬盘状态（默认: 0 0 0 关闭）

## 使用方法

### 交互式菜单

```bash
sudo LLLED
```

### 命令行模式

```bash
# 关闭所有LED
sudo LLLED off

# 打开所有LED
sudo LLLED on

# 启用节能模式
sudo LLLED power-save

# 设置开机自启
sudo LLLED enable

# 关闭开机自启
sudo LLLED disable

# 查看映射状态
sudo LLLED status

# 服务管理
sudo LLLED start    # 启动服务
sudo LLLED stop     # 停止服务
sudo LLLED restart  # 重启服务
```

## 配置文件

### 主要配置文件

-   `/opt/ugreen-led-controller/config/led_config.conf` - LED 配置和颜色设置
-   `/opt/ugreen-led-controller/config/disk_mapping.conf` - 硬盘映射关系
-   `/opt/ugreen-led-controller/config/global_config.conf` - 全局配置

### 自定义颜色

编辑 `/opt/ugreen-led-controller/config/led_config.conf`：

```bash
# 修改电源灯颜色（RGB值 0-255）
POWER_COLOR="128 128 128"

# 修改网络灯颜色
NETWORK_COLOR_DISCONNECTED="255 0 0"    # 断网 - 红色
NETWORK_COLOR_CONNECTED="0 255 0"        # 联网 - 绿色
NETWORK_COLOR_INTERNET="0 0 255"         # 外网 - 蓝色

# 修改硬盘灯颜色
DISK_COLOR_HEALTHY="255 255 255"         # 健康 - 白色
DISK_COLOR_STANDBY="200 200 200"         # 休眠 - 淡白色
DISK_COLOR_UNHEALTHY="255 0 0"           # 不健康 - 红色
```

修改后重启服务生效：

```bash
sudo systemctl restart ugreen-led-monitor.service
```

## 服务管理

### 查看服务状态

```bash
sudo systemctl status ugreen-led-monitor.service
```

### 查看日志

```bash
# 查看服务日志
sudo journalctl -u ugreen-led-monitor.service -f

# 查看日志文件
sudo tail -f /var/log/llled/ugreen-led-monitor.log
```

## 工作原理

1. **安装时**: 自动检测可用 LED 和硬盘，建立映射关系
2. **运行时**: 守护进程定期检测硬盘状态和网络状态
3. **状态更新**: 根据检测结果自动更新 LED 颜色和亮度

### 硬盘状态检测

-   使用 `hdparm -C` 检测硬盘活动/休眠状态
-   使用 `smartctl` 检测硬盘健康状态
-   无硬盘时自动关闭对应 LED

### 网络状态检测

-   断网: 无法获取路由
-   联网: 有路由但无法访问外网
-   连接外网: 可以 ping 通外网服务器

## 项目结构

```
/opt/ugreen-led-controller/
├── ugreen_led_controller.sh    # 主控制脚本
├── ugreen_leds_cli             # LED控制程序
├── config/                      # 配置文件目录
│   ├── led_config.conf          # LED配置
│   ├── disk_mapping.conf        # 硬盘映射
│   └── global_config.conf       # 全局配置
├── scripts/                     # 脚本目录
│   └── led_daemon.sh            # 守护进程
└── systemd/                     # 服务文件
    └── ugreen-led-monitor.service
```

## 常见问题

### Q: 如何重新检测 LED 和硬盘映射？

A: 重新运行安装脚本，或手动编辑配置文件。

### Q: 如何修改 LED 颜色？

A: 编辑 `/opt/ugreen-led-controller/config/led_config.conf`，然后重启服务。

### Q: 服务无法启动怎么办？

A: 检查日志：`sudo journalctl -u ugreen-led-monitor.service -n 50`

### Q: M2 SSD 有 LED 吗？

A: 通常 M2 SSD 没有对应的 LED，只有机械硬盘槽位有 LED。

## 版本历史

### v4.0.0 (重构版)

-   简化项目结构
-   重构配置文件系统
-   简化功能菜单
-   删除彩虹灯功能
-   优化守护进程
-   安装后自动启动服务

## 许可证

MIT License

## 参考

-   [原始项目](https://github.com/miskcoo/ugreen_leds_controller)
-   [博客文章](https://blog.miskcoo.com/2024/05/ugreen-dx4600-pro-led-controller)
