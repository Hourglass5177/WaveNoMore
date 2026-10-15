# 手柄震动实机排查（2026-10-15）

本轮只检查设备、协议与输出，没有修改80ms短震时长、强度参数或玩法代码。

## USB有线实测

用户确认使用USB有线。Windows总线名称为 `8BitDo Ultimate 2C Wireless (WUKONG)`，VID/PID为 `2DC8:310A`，经微软驱动识别为Xbox 360兼容手柄。项目实际原生后端枚举为 `XInput Controller #1`、路径 `XInput#0`。Windows保留的蓝牙配对设备条目不能据此当作当前活动连接。

原生后端只报告 `sdl_joystick_rumble`，双路强度可用，单路正弦及独立频率不可用。六次80ms请求全部接受，错误为空；停止调用约在79.4～80.2ms，没有延长测试脉冲。通过正式原生DLL直接诊断，不经过关卡与玩家设置。

| 请求 | 强度倍率 | 提交到SDL的左/右强度 |
| --- | ---: | --- |
| 普通基础0.35，界面默认50% | 1 | 0.349996 / 0.349996 |
| 普通基础0.35，界面100% | 2 | 0.700008 / 0.700008 |
| Perfect基础1，界面默认50% | 1 | 1 / 1 |
| Perfect基础1，界面100% | 2 | 1 / 1 |
| 仅左侧满幅 | 1 | 1 / 0 |
| 仅右侧满幅 | 1 | 0 / 1 |

这些是软件提交值和驱动接受状态，不是马达振幅、功率或加速度测量。没有证据表明当前USB路径被软件额外削弱；不能仅凭成功返回解释所有主观偏弱现象。

当前路径用16位整数0～65535传递两个马达的强度。它不发送可自由指定的Hz，日志中的请求120Hz不会变成真实120Hz输出。SDL所称左右路分别是低频/高频马达，同样数值并不保证两边相同体感。关卡中生钟走左路、死钟走右路；设置试震同时驱动两路。

## 蓝牙与2.4G

[官方产品页](https://www.8bitdo.com/ultimate-2c-wireless-controller/)将Windows支持方式列为USB/2.4G，蓝牙列给Android。因此Windows上蓝牙能收按键，不代表它同时提供兼容的震动输出。下面9月记录中，蓝牙301B设备未报告任何可用震动后端；本轮已请用户切换蓝牙，尚未完成新对照。2.4G本轮也尚未实测。

不能推广为所有蓝牙手柄都弱或不支持震动：[SDL的Xbox驱动](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_xboxone.c)包含专门的蓝牙震动输出。影响能力的是型号、模式、驱动及API组合，传输方式只是其中一层。

本轮日志：`builds/haptics-20261015/usb-output.json`。临时诊断脚本位于同目录，不进入发行包。后端能力参见[SDL_RumbleJoystick文档](https://wiki.libsdl.org/SDL3/SDL_RumbleJoystick)。未升级固件、替换驱动或原生DLL。

---

# 历史记录：独立试玩无震动排查（2026-09-08）

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
