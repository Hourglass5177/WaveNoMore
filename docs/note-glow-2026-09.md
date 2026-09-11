# Tap 双押与 Hold 调频白光

2026-09-09，基于 develop `8aab695`。仅调整音符表现，不改谱面格式、判定、输入、成绩或音频时间映射。

## 当前效果

白光由表面提亮、近处亮边和向外衰减的柔光组成。表面光覆盖整个音符，原有配色、身体纹理和纹样仍然可辨。按本轮美术反馈，整体亮度比初版轮廓光更明显，外晕默认宽度调整为 30 个设计像素。

- 生、死两侧 Tap **同一 tick 或同一非空 group_id**，满足任一条件就带双押白光。两项条件都只在 Tap 之间匹配；Tap 与 Hold 同刻不算这类提示。各 Tap 按自身判定时间亮起。
- 双押 Tap 在判定前 0.60 秒开始渐亮，经过 0.15 秒达到全亮（判定前 0.45 秒）。成功按键时立即关闭白光及外圈，本体以 45% 亮度续行，声波接触后原地消散；漏击仍在 0.08 秒内淡出白光。两阶段反馈与美术接口见 [Tap 与 Tuning 表现说明](tap-feedback-tuning-radius.md)。
- Hold 仅在所属侧滑条实际接管时亮起，头、可见身体、尾一起发光。读取现有 `dragging` 与 Hold 关联；仅在窗口中、仅按住、错过或已经松开都不会使它持续发光。
- Hold 进入接管时 0.10 秒渐亮，离开时 0.08 秒淡出；不要求摇杆持续运动，也不额外检查 Perfect。连续滑条有效换接保持亮度。
- 光效跟随现有时钟：暂停冻结，预览定位按正式输入重演恢复，回收与换谱清除状态。

## 接入与参数

`ChartScheduler` 配置时索引完整谱面，生成事件中增加只读表现字段 `double_tap: bool`，不回写编译数据或 JSON。`NoteVisualHost` 负责传入 Tap 的绝对视觉时间和 Hold 实际调频接管状态。

音符表现接口：

| 接口 | 用途 |
| --- | --- |
| `set_note_glow_time(seconds, time_to_hit)` | Tap 按自身判定前的时间求亮度，`seconds` 为当前视觉时间 |
| `set_tuning_glow(active, seconds)` | Hold 接管状态过渡，`seconds` 为现有判定时钟 |
| `glow_amount` | 当前 0～1 视觉强度，只供表现和调试使用 |

`GrayboxNoteVisual` 的 **White Glow** Inspector 分组由 Hold 继承：

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `glow_width_px` | 30 px | 柔光绘制外扩宽度 |
| `glow_strength` | 1.0 | 整体光强倍率 |
| `tap_glow_lead_sec` | 0.60 s | Tap 渐亮提前量 |
| `tap_glow_rise_sec` | 0.15 s | Tap 渐亮时长 |
| `hold_glow_rise_sec` | 0.10 s | Hold 渐亮时长 |
| `glow_fall_sec` | 0.08 s | 松开、结束或失败的淡出时长 |

白光使用两个共享 `canvas_item` shader，每个绘制实例独立保存材质参数。Tap 和程序化头尾以真实轮廓距离绘制；贴图头尾采样透明度轮廓；身体沿当前动态脊线生成外扩网格。头身尾接合处收束光晕，避免分件出现额外亮边。身体光效独立于原身体材质，不覆盖纹理流动和自定义材质。

保持 Compatibility 渲染器；光效不使用全屏后处理、逐音符 SubViewport 或全局 `TIME`。没有新增游戏内提示文字。

## 检查

新增 `tests/visual/run_note_glow_tests.gd`，使用工程现有 SceneTree 测试方式：

```powershell
& $GodotExe --headless --path . --script res://tests/visual/run_note_glow_tests.gd -- --chart-editor
```

覆盖双押条件、渐亮时点、漏击淡出、单侧与双侧 Hold 接管、窗口结束、松开、重新接管、连续滑条和对象池复用；还通过正式 StageRoot 验证六个时间点的直接定位与连续播放一致。已有 `tests/editor/run_studio_tests.gd` 用于回归预览与原音符反馈。

去掉 `--headless` 后运行同一脚本，使用真实图形驱动检查 shader，并输出到 `builds/visual-review/note-glow/`：

- `glow-1280.png`、`glow-1920.png`：原样、渐亮、全亮及身体、透明贴图取样。
- `stage-*.png`：正式关卡预览中的 Tap、单侧／双侧调频 Hold。
- `dense-backgrounds.png`：红色与深色背景下的密集双押。

本轮不导出应用。测试图中临时使用的透明贴图只用于检查透明度采样，不是对正式音符素材的替换。

本轮结果：42 项白光状态及正式预览断言通过，已有写谱器文档／预览测试通过；Compatibility 图形驱动运行无 shader 错误。已查看 1280 与 1920 尺寸取样、正式双侧调频画面，以及密集双押在红色和深色背景下的效果。

## 性能调整

白光的轮廓、矩形、贴图范围和强度未变化时不重复上传；Hold 身体仅在脊线段数改变时重建网格，其余帧更新现有顶点与属性缓冲。首次关卡装配用一个 32×32 的临时视口绘制白光与 Ghost，完成后释放，每个进程仅一次。

Ghost 查询、绘制优化与实测边界见 [性能记录](note-effects-performance-2026-09.md)。
