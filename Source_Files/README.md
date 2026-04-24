# Source_Files

这里保存板卡侧源码和辅助脚本。

## 文件

- `JingqiBMP581/JingqiBMP581.ino`：BMP581 蓝牙采集固件
- `Launch_Arduino_UTF8.command`：用于处理 Arduino IDE 的 Python/Click 编码问题

## 电量查询

- 电量计地址：`0x36`
- App 发送：`BAT`
- 成功返回：`BAT:<percent>,<voltage>`
- 失败返回：`BAT:ERR`
- `Check` 会额外返回 `FG:OK` 或 `FG:ERR`

## 说明

- 当前实现默认电量计兼容 MAX17048 / MAX17049
- 若 Arduino IDE 出现 Click 的 ASCII 编码报错，可先运行 `Launch_Arduino_UTF8.command` 再编译
