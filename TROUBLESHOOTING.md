# LLLED v3.0.0 故障排除指南

## LED控制功能失效问题

### 问题描述
用户报告LED控制功能失效，主要表现为：
1. "打开所有LED" 功能变成了LED检测，不实际控制LED
2. "节能模式" 没有反应
3. "关闭所有LED" 功能无效果

### 问题原因分析

#### 1. LED检测逻辑问题
**原因**: `turn_off_all_leds.sh` 和 `led_test.sh` 中的正则表达式不匹配实际LED状态输出格式
**表现**: 无法正确检测到可用LED，导致控制失败

#### 2. 硬编码LED列表问题  
**原因**: 主控制器中节能模式等功能使用硬编码的LED列表 (`disk1`, `disk2`, etc.)
**表现**: 如果实际硬件LED命名不同，控制会失败

#### 3. 脚本参数处理问题
**原因**: `led_test.sh` 缺少实际的LED控制功能，只有检测功能
**表现**: 调用 `--all-on` 参数时只执行检测，不控制LED

### 修复措施

#### 1. 修复LED检测正则表达式
```bash
# 原来的错误正则
if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then

# 修复后的正确正则  
if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*= ]]; then
```

#### 2. 添加动态LED检测功能
在主控制器中添加 `get_available_leds()` 和 `set_all_leds()` 函数，动态获取可用LED列表

#### 3. 增强脚本参数支持
为 `led_test.sh` 添加实际的LED控制功能:
- `--all-on`: 打开所有LED
- `--all-off`: 关闭所有LED  
- `--detect`: 检测LED状态

#### 4. 增加备用控制方法
为所有LED控制功能添加多重备用方案：
- 方法1: 动态检测后逐个控制
- 方法2: 使用 `all` 参数一次性控制
- 方法3: 尝试常见LED名称列表

### 验证方法

#### 1. 快速功能测试
```bash
# 运行快速测试脚本
sudo /opt/ugreen-led-controller/quick_led_test.sh
```

#### 2. 手动验证LED控制
```bash
# 检查LED状态
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status

# 手动控制测试
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -on
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -off
```

#### 3. 检查i2c模块
```bash
# 检查模块是否加载
lsmod | grep i2c_dev

# 如果未加载，手动加载
sudo modprobe i2c-dev
```

### 常见问题解决

#### Q1: "未检测到任何LED" 错误
**解决方案**:
1. 检查是否有root权限
2. 确认i2c-dev模块已加载
3. 验证硬件支持
4. 使用备用控制方法

#### Q2: LED控制程序无响应
**解决方案**:
1. 检查ugreen_leds_cli程序是否存在且可执行
2. 验证硬件兼容性
3. 重启LED服务: `sudo systemctl restart ugreen-led-monitor`

#### Q3: 部分LED无法控制
**解决方案**:
1. 检查具体LED名称是否正确
2. 尝试不同的亮度和颜色值
3. 检查硬件连接

### 预防措施

#### 1. 定期检查
```bash
# 添加到crontab的健康检查
*/30 * * * * /opt/ugreen-led-controller/quick_led_test.sh --silent
```

#### 2. 日志监控
```bash
# 检查系统日志
journalctl -u ugreen-led-monitor -f
```

#### 3. 配置备份
```bash
# 定期备份配置
sudo tar -czf /backup/llled-config-$(date +%Y%m%d).tar.gz /opt/ugreen-led-controller/config/
```

### 版本历史

#### v3.0.0 (2025-09-06)
- 修复LED检测正则表达式问题
- 添加动态LED检测功能
- 增强脚本参数支持
- 新增快速测试工具
- 完善故障排除机制

### 联系支持

如果问题持续存在，请提供以下信息：
1. 硬件型号 (UGREEN NAS具体型号)
2. 系统信息 (`uname -a`)
3. LED检测输出 (`sudo ugreen_leds_cli all -status`)
4. 错误日志 (`journalctl -u ugreen-led-monitor`)
5. 测试脚本输出 (`sudo quick_led_test.sh`)
