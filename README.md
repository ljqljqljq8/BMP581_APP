# BMP581_APP

用于连接 `JingQiBMP / BMP581` 蓝牙气压板卡的 iPhone App，基于 `SwiftUI + CoreBluetooth` 实现。

## 功能

- 扫描并选择 BLE 设备连接
- 发送 `S / P / C / BAT` 指令
- 实时显示气压、传感器状态、电量和曲线
- 显示 BLE 日志
- 导出 CSV

## 目录

- iOS 工程：`AirPressure.xcodeproj`
- App 代码：`AirPressure/`
- 板卡固件：`Source_Files/JingqiBMP581/JingqiBMP581.ino`

## 使用

1. 用 Xcode 打开 `AirPressure.xcodeproj`
2. 在 `Signing & Capabilities` 中选择自己的 Team
3. 将 `JingqiBMP581.ino` 烧录到板卡并上电
4. 在手机 App 中点击 `Scan`，选择设备后连接
5. 点击 `Start` 开始采集，点击 `Save CSV` 导出数据

## 说明

- 默认 BLE 名称为 `JingQiBMP`
- 电量查询命令为 `BAT`
- 电量计默认按 `0x36` 的 MAX17048 / MAX17049 兼容寄存器读取
