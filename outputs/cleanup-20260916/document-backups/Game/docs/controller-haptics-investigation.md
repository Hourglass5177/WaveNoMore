# 独立试玩无震动排查（2026-09-08）

## 当前结论

现场手柄为 8BitDo Ultimate 2C Wireless，枚举路径为蓝牙 HID（VID 2DC8、PID 301B）。当前连接在原生 SDL 后端下没有报告任何可用震动输出能力：`dual_strength`、`mono_periodic`、`mono_strength` 均为 false，`reported_backends` 为空。因此 ControllerHaptics 将该设备标为不可输出，Tap 和 Hold 不能产生震动。

这不是独立试玩被当作内嵌自动预览。通过工程内的相同 `--play-chart` 入口加载实际 `output/test.zip`，倒计时后测得：来源 trial、external_preview=false、PLAYING、窗口有焦点、未暂停、output_enabled=true、suspended=false，判定信号与震动反馈连接存在。

## 已核对内容

- 原生 ControllerHapticsBackend 类正常注册；工程运行和普通窗口设备查询结果一致。
- 最新配套游戏旁存在 `wnm_controller_haptics.dll`，与工程内原生 DLL 内容一致；此前配套 EXE 的独立加载检查通过。发行 EXE 不执行编辑器的 `--script` 诊断入口，不能把该次启动误记为执行了设备诊断脚本。
- 本机试玩设置没有另指定旧游戏路径，因此默认使用写谱器旁的 `game/minghe.exe`。
- 内嵌预览不打开震动输出，且按源码不会实例化并占用原生设备；独立试玩的门控确实开启。
- 当前游戏只在成功 Tap 判定时短震，Hold 的逻辑 holding 状态持续震动；空按或 MISS 不能当作有效验证。

8BitDo 官方将本型号的 Windows 连接方式列为 2.4G 和 USB 有线，蓝牙列为 Android。现场结果支持“当前蓝牙连接未提供本游戏可用震动接口”的判断，不据此断言所有蓝牙手柄、所有驱动或该设备所有连接方式都不能震动。[官方产品说明](https://www.8bitdo.com/ultimate-2c-wireless-controller/)

## 后续实机核对

改用本型号随附 2.4G 接收器或 USB 数据线后，重新枚举设备、核对至少一种输出能力，并用成功 Tap／持续 Hold 验证。当前尚未取得切换连接后的实测结果，不把物理震动验收标记为通过。

本次没有改变判定、玩法或硬件能力判断。诊断脚本和详细日志位于本机 `builds/haptics*`，不进入发行包；现有谱面未改动。
