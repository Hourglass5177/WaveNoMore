# 关卡性能与渲染分辨率

2026-09-14，`editor` 工作区，Godot 4.7.2 Compatibility。本次保留工作区已有的关卡编辑器、动画及音符光效修改。工程验证后按用户后续要求更新了三个程序，导出记录见 [构建目录](build-output.md)。

## 当前结果

2K 完整效果下，正式 `StageSession` 重负载谱段三轮 P99 为 **9.03～9.09 ms**，没有超过 16.67 ms 的帧。内嵌预览同段平均耗时由 **16.32～17.69 ms** 降为 **9.32～11.41 ms**，三轮共 1,800 帧中超过 33.3 ms 的帧由 **73 帧降为 0 帧**。

预览三轮中仍有一轮 P99 为 **22.35 ms**，因此还不能宣称所有运行方式都稳定达到 P99 ≤ 16.67 ms。整首 84 秒预览的另一轮采样 P99 为 **9.07 ms**、最大 **14.09 ms**。保留两种结果，不用整曲平均值覆盖重负载时的波动。

## 更新链路

- `StageSession.step()` 保留输入、领域推进和事件顺序，在帧尾生成一次完整快照、发布一次最终画面。按键命中、声波接触与消亡使用事件自身的微秒时间，回调结束后恢复调度器的帧时钟。
- `GameplayCoordinator.frame_snapshot()` 和内部快照信号共享只读数据；需要修改结果的外部调用继续使用 `snapshot()` 获取深复制。新输入或领域推进会替换运动快照，不能修改此前持有的嵌套数组。
- HUD 成绩统计只处理新增判定和乱按；Ghost 目标与结果历史仅在追加或重置时复制。结算、Replay 的完整记录保留，Ghost 候选算法未变。
- `TuningEngine` 配置时建立按起点排序的索引，仅遍历预告／交互窗口内的滑条。新条目加入时恢复编译顺序；移除条目不会改变优先级。回到较早时间会重建窗口，重试或清场会清空索引。
- 规则查询直接读取资源属性，去掉高频的 `get_property_list()` 分配。`TempoMap.us_to_tick()` 先从 BPM 段估计相邻 tick，再沿用正向换算的整数舍入校正邻近边界；不改时间定义和谱面偏移。
- 写谱器恢复保留 120 Hz 身体模拟；中间恢复步骤推进状态，最后提交可见几何。同刻输入只同步 Hold 控制与角色速度边界，避免再次积分整套音符。普通播放与定位恢复使用相同的身体采样规则。
- 未开启调试 HUD 时，不构造调试快照。相纹在最终画面帧统一提交，时间使用视觉时钟；折射材质只提交发生变化的配置与波前参数。

### 调频轨道与 Hold

`tuning_rail.gdshader` 和 `tuning_soft_glow.gdshader` 共用 `tuning_arc_distance.gdshaderinc`。底轨、填充及外轮廓在固定局部网格上计算圆弧胶囊距离，移动填充只改区间参数，不再逐帧做多边形膨胀与三角化。缩圈裁切结果由主线、托底及柔光共用。透明叠加、圆帽、折返、近圆起点预填和阵营色保持原有设计。

Hold 在一次身体推进后共用脊线及宽度采样。顶点、UV、索引数组复用；拓扑相同时通过 `surface_update_vertex_region` / `surface_update_attribute_region` 上传，段数变化才重建表面。同步更新动态包围盒，冻结或零时间推进不重复生成几何。上传需要的字节转换仍由 PackedArray 完成。

现有材质预热加入了轨道 shader。对象池首次遇到更高并发量仍会扩容：本次重负载首轮节点数从 316 增至 335，第二、三轮稳定在 335。它没有逐帧持续增长；本轮没有把所有可能的谱面并发量提前实例化。

## 分辨率与坐标

设置页增加“分辨率”，支持 **1280×720、1600×900、1920×1080、2560×1440、3840×2160**。默认 2560×1440；旧 `settings.cfg` 缺少 `display/resolution` 时使用该默认值。沿用“保存并返回”写入和应用配置。

窗口模式优先使用所选尺寸，超过桌面可用空间时等比缩小窗口；渲染目标仍是所选像素尺寸。全屏保持显示器输出模式，16:9 画面等比铺满并留边。本机 2560×1600 屏幕上的五档窗口／全屏均检查了实际渲染纹理尺寸。

玩法始终使用 **1920×1080 设计坐标**。根 Window 保留 `CONTENT_SCALE_MODE_VIEWPORT`、设计尺寸和 `content_scale_factor = 1`，由 `SettingsService._apply_render_resolution()` 调整同一个根 Viewport 的 RenderingServer 目标像素与最终画布矩阵，没有新增玩法视口。直接修改 Window 缩放因子也会改变逻辑布局，故没有采用该做法。根窗口尺寸变化后会重新应用渲染尺寸，并同步字体 oversampling。

这个分离要求屏幕取样处显式换算，而领域坐标不需要重写：

| 数据或绘制 | 适配方式 |
|---|---|
| 钟、波源、真实波前、音符和判定几何 | 继续使用设计坐标与原波速，随画布矩阵一起显示 |
| 局部折射 | 使用 `render_pixel_scale × stretch_transform × canvas_pose`，把设计位移换算为真实取样像素 |
| 眼球追踪 | shader 从 `CANVAS_MATRIX` 获取像素比例，追踪距离与眼球偏移按同一比例换算 |
| 背景接缝合成 | 逆变换加入实际渲染比例，背景采样和世界位置一致 |
| HUD、GUI 与鼠标 | 布局继续为 1920×1080，Window 处理实际窗口／留边到逻辑画布的输入换算 |
| 写谱器、关卡编辑器 | 保持各自窗口与 UI 缩放；内嵌预览按面板实际像素分配，最高 2560×1440，设计覆盖仍为 1920×1080 |
| 独立试玩 | 使用正式游戏设置 |

分辨率图形测试验证了十种窗口／全屏组合的纹理大小、设计参考点落点、鼠标点击、逻辑画布及配置序列化。另在根窗口的 720p、2K、4K 下实际渲染同一道波：峰值均位于波源外 300 设计像素处，测得位移分别为 8.89、9.14、8.89 设计像素，波带外及波前经过的 HUD 像素保持稳定。已有眼球、折射图形测试继续覆盖缩放与留边。原始波源位置、频率、判定时刻、输入记录和 Replay 没有随分辨率改变。

## 测量方法

机器：Intel Core Ultra 9 185H、NVIDIA GeForce RTX 4060 Laptop GPU。渲染为 2560×1440、Compatibility、完整音符／调频／相纹／空间折射／Ghost 效果。使用本地谱面 `../Charts/charts/test/song.json`（未命名歌曲，normal，BPM 138），正式 s08 美术主题和墓地背景。

重负载区间为谱面时间 **29.668478～39.668478 秒**，每轮 600 帧，三轮。完整歌曲测量覆盖 **0～84 秒**，5,040 帧。采样关闭 VSync 和 FPS 限制，用固定 1/60 秒的歌曲步进驱动每个实际渲染帧；`StageSession` 模式注入带时间戳的语义输入并走正式 `step()`，预览模式保留固定步长重演。因此这些是实际渲染与代码开销测量，尚不等同于音频设备、人工操作、所有后台负载下的实时游玩保证。

`GameplayFrameProfile` 默认关闭，只在采样期间记录领域输入、推进、运动快照、完整快照、表现、身体几何及轨道绘制。测试入口另读 RenderingServer 的 GPU／渲染 CPU 时间，记录帧耗时、P95、P99、最大值、超预算帧数和节点数。数据保存在内存，结束后统一输出 JSON；测量阶段不截图、不逐帧写日志。

优化前采样已有 2K 实际渲染，但尚未展示前景 TextureRect 或记录窗口焦点。最新重负载采样显式展示同一预览画面，所有帧均处于前景；额外的显示取样和系统负载差异意味着这不是完全隔离变量的实验。早期中间轮次也保留在输出目录，没有删去其长帧。

### 帧耗时

单位 ms；每个重负载行 600 帧。

| 链路 | 轮次 | 平均 | P95 | P99 | 最大 | >16.67 | >33.3 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 优化前预览 | 1 | 16.32 | 30.86 | 46.39 | 54.05 | 195 | 26 |
| 优化前预览 | 2 | 17.69 | 31.58 | 46.91 | 62.91 | 259 | 25 |
| 优化前预览 | 3 | 16.41 | 30.46 | 40.56 | 50.42 | 228 | 22 |
| 优化后预览 | 1 | 9.32 | 13.70 | 16.38 | 18.32 | 3 | 0 |
| 优化后预览 | 2 | 10.19 | 14.24 | 16.41 | 17.86 | 5 | 0 |
| 优化后预览 | 3 | 11.41 | 17.44 | 22.35 | 28.63 | 39 | 0 |
| 正式 StageSession | 1 | 6.38 | 8.10 | 9.09 | 10.55 | 0 | 0 |
| 正式 StageSession | 2 | 6.35 | 7.87 | 9.03 | 10.67 | 0 | 0 |
| 正式 StageSession | 3 | 6.60 | 7.96 | 9.03 | 10.38 | 0 | 0 |
| 整曲预览，5,040 帧 | 1 | 4.89 | 7.72 | 9.07 | 14.09 | 0 | 0 |

三轮预览合计平均帧耗时降低约 **39%**；超 16.67 ms 从 682 帧降为 47 帧。GPU 平均仍约 4 ms，主要收益来自 CPU 链路。整曲记录没有出现随历史判定增长而持续变慢的趋势；此结论仅覆盖本次实际谱面长度。

![重负载帧耗时](../builds/gameplay-performance/frame-time-comparison.png)

![整曲帧耗时](../builds/gameplay-performance/full-song-frame-time.png)

### 当前热点与首次显示

下表是三轮合计后平均每渲染帧的计时；**项目之间存在嵌套，不能相加当作总帧耗时**。例如身体几何包含在表现更新中，运动快照可能包含在完整快照中。轨道 `_draw` 在实际绘制阶段计时，也不能直接当作 `preview.advance()` 的占比。

| 分段 | 正式 StageSession | 内嵌预览 |
|---|---:|---:|
| 领域输入 | 0.083 | 使用带时间戳的预览输入 |
| 领域推进 | 0.115 | 0.277 |
| 运动快照 | 0.144 | 0.513 |
| 完整快照 | 0.185 | 0.184 |
| 角色更新 | 0.318 | 0.978 |
| 音符表现 | 0.563 | 1.211 |
| Hold 几何（包含于表现） | 0.197 | 0.249 |
| 调频绘制 | 0.540 | 0.680 |

预览要在每个运动子步保留角色速度、Hold 弯曲和输入边界，角色及音符更新仍比正式运行多。正式模式的完整快照为每轮 **600 次／600 帧**。后续如果继续优化预览，应优先量化这些子步的剩余开销，不减少真实波前或降低判定更新频率。

加载／定位准备不计入正常游玩统计。重负载开始后首秒最大帧耗时：正式三轮 **8.22 / 10.22 / 8.96 ms**，预览 **10.11 / 12.06 / 14.07 ms**。这些只是准备后的首次显示窗口，不代表每一种未见素材的冷启动峰值。完整冷启动加载和全新并发量的资源首次触发仍是测量边界。

## 验证

本轮直接相关验证：

| 入口 | 结果／范围 |
|---|---|
| `run_tempo_inverse_tests.gd` | 3,000 次与原二分反算结果精确相等；含变 BPM、负时间、偏移与微秒边界 |
| `run_gameplay_performance_regressions.gd` | 13 项通过；精确事件时刻、活动索引与全谱扫描对照、增量与完整结算、30／60／120 FPS 和不规则步长的一致性 |
| `run_preview_motion_regressions.gd` | 40 秒连续推进及多次定位，对照优化前运动更新路径，姿态与 Hold 脊线 0 差异 |
| `run_display_resolution_tests.gd` | 63 项实际渲染检查通过，包含根窗口真实波前取样 |
| `run_tap_feedback_tests.gd` | 185 项通过 |
| `run_mixed_double_tests.gd` | 156 项通过 |
| `run_note_glow_tests.gd` | 0 失败，含 Hold 接管白光、暂停、Seek 及回收 |
| `run_timing_cue_tests.gd` | 68 项通过 |
| `run_tuning_style_tests.gd` | 41 项实际图形检查通过，普通填充实际 alpha 0.788 |
| `run_wave_distortion_tests.gd` | 46 项实际像素检查通过 |
| `tests/integration/stage/run_tap_eye_tests.gd` | 0 失败，眼球、瞳孔提亮与中性睫毛保持 |
| `tests/editor/run_tuning_delivery_tests.gd` | 0 失败，半径保存／导出／恢复与预览 Ghost、Seek |

未列全路径的入口位于 `tests/visual/`。回归时发现“同刻输入后省略全部表现同步”会改变 Hold 白光过渡的起点，已改为仅同步控制状态；最新发光与运动对照均通过。

仓库旧的大范围套件并非全部通过：`run_stage_runtime_tests.gd` 和 `run_input_replay_v3_tests.gd` 引用已不存在的 `InputRouter`／旧输入枚举，存在解析错误；`run_domain_tests.gd` 输出 11/131 失败，其调频圆弧部分另有 24/101 失败。它们尚未完成基线归因，不能据此宣称全仓库回归通过，也没有删除断言或改写预期来绕过失败。原日志保留在测量目录。本轮新增的完整实际谱面、全扫描参考与多帧率对照均通过。

## 复现与素材

在 `Game` 目录运行，先关闭其他 Godot 图形检查，避免并行采样相互影响。测试使用的外部谱面需保留在上述本机路径。

```powershell
$godotExe = 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/visual/measure_gameplay_performance.gd -- --chart-editor --visible --label=review --runs=3
& $godotExe --path . --script tests/visual/measure_gameplay_performance.gd -- --chart-editor --visible --label=review --mode=session --runs=3
& $godotExe --path . --script tests/visual/measure_gameplay_performance.gd -- --chart-editor --visible --label=whole-song --start=0 --seconds=84 --runs=1
& $godotExe --path . --script tests/visual/run_display_resolution_tests.gd -- --chart-editor
```

`--chart-editor` 在这些测试中避免自动加载／写入玩家日常设置；测试直接设置自己的渲染目标。`--headless` 仅用于不等待真实绘制的状态测试。像素检查、截图和性能测试需 Compatibility 实际渲染。

输出目录为 `builds/gameplay-performance/`（Git 忽略）：

- 原始采样：[优化前预览](../builds/gameplay-performance/before-preview.json)、[优化后预览](../builds/gameplay-performance/optimized-preview.json)、[正式运行](../builds/gameplay-performance/foreground-session.json)、[整曲预览](../builds/gameplay-performance/full-song-preview.json)。包含逐帧数据，早期中间轮次也保留。
- [调频演示，60 fps](../builds/gameplay-performance/tuning-demo-60fps.mp4)：10 秒、1280×720 输出，来源为 2K 玩法画面，以固定 60 fps Movie Maker 录制并配回对应音乐。按歌曲正常速度播放；录制与编码过程不作为性能证据。
- [正式背景第 60 帧](../builds/gameplay-performance/gameplay-060.png)、[第 180 帧](../builds/gameplay-performance/gameplay-180.png)、[第 360 帧](../builds/gameplay-performance/gameplay-360.png)：2560×1440 原始截图，含双侧滑条、Hold 消耗和 Ghost。

相关参数说明：[音符效果](note-effects.md)、[调频轨道](tuning-visual-style.md)、[计时提示](timing-cue-style.md)。
