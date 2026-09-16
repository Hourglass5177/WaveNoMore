# 《冥河，冥河！》Godot MVP 程序架构

> 文档状态：已补当前实现对照，原方案保留参考  
> 引擎：Godot 4.7，GDScript  
> 目标平台：移动端横屏、PC 手柄  
> 开发测试输入：PC 鼠标左/右键敲钟，双键按住并移动鼠标调频  
> 更新日期：2026-09-06；原方案日期：2026-08-23  
> 玩法基线：[立项说明书](../Product/立项说明书.pdf)  
> 配套文档：`《冥河，冥河！》MVP写谱器架构.md`、`《冥河，冥河！》MVP美术资产与演出接入规范.md`

## 当前实现对照（2026-09-06）

以下为现状；后续章节保留 2026-08-23 的 MVP 目标方案，资源示意和接口名须对照代码使用。

| 模块 | 当前实现 |
| --- | --- |
| 工程 | Godot 4.7；content / domain / runtime / presentation 分层，领域逻辑与表现分开 |
| 流程 | 标题、五关选关、异步加载、关卡、结算、暂停重试、设置、手动偏移校准、单随从装备及存档 |
| 内容 | 五张 120 BPM 灰盒测试关，均开启不致死调试、关闭奖励，使用程序节拍音；正式 BGM 与美术待交付 |
| 调频 | 每侧独立有限圆弧；每程在尾拍前进入末端 3% 即成功，原定尾拍结算 Perfect / Miss；成组双侧只计一次判定与 Combo |
| 时间与回放 | TempoMap 整数微秒换算、SongClock 分离时间域、语义输入 Replay v3，共用 GameplaySimulation |
| 内容包 | 六文件关卡包，另引用公共 GameplayRuleSet；Catalog 同时支持目录扫描 |
| 工具 | 写谱器可编辑 SongChart / StageShow，正式预览复用 StageRoot；ArtLab 已能实例化资产检查状态与锚点 |

尚未完整落地的部分包括正式关卡交付、自动校准、SongAuthoringProfile、完整变拍网格与歌曲元数据编辑、Actor / Audio 演出处理及部分主题槽。疾振逻辑保留，但当前测试关未使用。

操作、实际类名、默认数值和已知写谱器问题见[工程代码导览](./《冥河，冥河！》Godot工程代码导览.md)。

## 原方案（2026-08-23）

## 1. 本轮结论

MVP 不沿用 Web 原型的视觉设计。Web 3.0 只保留已经验证过的输入、时序和判定经验，其圆点音符、滑槽、钟体、HUD、酒红几何背景都不进入 Godot 的表现方案。

工程采用以下五条主线：

1. 游戏与写谱器共用同一套时间、谱面、判定和校验核心。
2. 判定数据、演出时间轴、美术资产包分开保存。
3. 生界和死界是两个独立表现实例，构图保持 180° 中心对称，行为不强制对称。
4. 音符、怪物、角色、编钟、相纹和边界全部通过可替换场景接入，程序不规定其最终外形。
5. MVP 先完整做通一关；第二关使用同一架构制作，是内容扩展项，不另写一套逻辑。

## 2. MVP 范围

| 模块 | MVP 交付 |
| --- | --- |
| 局内玩法 | 朱/玄 Tap、朱/玄 Hold、普通双押、素音调频、双钟疾振、判定、连击、得分、血量、失败、暂停、重试、结算 |
| 应用流程 | 启动、主界面、选关、加载、关卡、结算、设置与校准 |
| 内容 | 1 个完整关卡；条件允许时增加第 2 关；每关一个正式难度 |
| 随从 | 每个正式关卡对应 1 个随从；FC 获得基础形态，AP 获得进阶形态；同时装备 1 个 |
| 存档 | 关卡解锁、最好成绩、FC/AP、随从状态、当前装备、设置与偏移 |
| 工具 | 能独立完成正式谱面的写谱器，包括全部音符、演出轨、预览、校验、撤销、备份和恢复 |
| 开发谱 | 校准谱、全机制自动测试谱，不进入正式选关流程 |

MVP 不做二十八关完整内容、多难度正式谱、联网、云存档、UGC 发布、自由移动、复杂战斗 AI 和通用关卡编辑器。Boss 若出现在首关，只作为随歌曲推进的演出对象，不建立自由战斗系统。

## 3. 总体分层

```text
应用层
  主界面 / 选关 / 关卡加载 / 结算 / 设置
        │
内容层
  StageDefinition / SongChart / StageShow / StageVisualTheme / PetDefinition
        │
共享核心
  TempoMap / ChartCompiler / ChartValidator / JudgeEngine / TuningEngine
  RapidEngine / ScoreEngine / ResultEvaluator / Replay
        │
运行时适配层
  SongClock / InputRouter / ChartScheduler / StageSession / SaveService
        │
表现层
  WorldPair / NoteVisualHost / StageDirector / InterferenceRenderer
  VfxDirector / AudioFeedback / HUD

写谱器 ───────────────┘
  直接复用内容层和共享核心，通过 PreviewBridge 启动同一套 StageSession
```

依赖只能向下：

- 共享核心不读取场景树、贴图、Shader 或音符屏幕位置。
- 表现层只读取语义事件，不反向修改判定结果。
- 写谱器不能复制一套简化判定；预览必须调用正式运行时。
- 运行中的状态不能写回共享 `.tres` 资源。

## 4. 关卡内容合同

一个关卡由以下资源组合：

```text
StageDefinition
├─ SongDefinition       发行 BGM、选关预览段、首拍偏移
├─ SongChart            判定与玩家交互
├─ StageShow            同 tick 的角色、怪物、镜头、场景和特效演出
├─ StageVisualTheme     PackedScene、贴图、材质、动画和表现预设
└─ RewardDefinition     解锁条件与随从奖励
```

制谱 WAV 和波形缓存属于编辑器侧 `SongAuthoringProfile`，不由 `StageDefinition` 引用，避免被打进发行包。

### 4.1 SongChart

```text
SongChart
├─ schema_version / chart_id / difficulty_id
├─ ppq = 480
├─ timing_track
│  ├─ tempo_events
│  ├─ meter_events
│  └─ chart_offset_ticks
├─ note_events          朱/玄 Tap、Hold
├─ tuning_regions       双钟保持与调频区域
├─ su_targets           素音判定点
├─ rapid_regions        双钟疾振区域
└─ sections             乐段、教程与书签
```

所有时间以整数 tick 保存。每个事件有稳定字符串 ID；同 tick 事件按类型、轨道和 ID 确定性排序。

### 4.2 StageShow

`StageShow` 与谱面共用 `TempoMap`，但不参与得分。它包含：

- 角色动作、怪物入场和退场；
- 背景层、关卡核心物、边界和调色变化；
- 镜头、屏幕特效、音效提示；
- 教学提示和演出段落；
- 可预见事件，例如 Boss 显形、场景坍塌和曲终演出。

命中、Miss、掉血等结果型表现由语义事件触发，不提前写死在 `StageShow` 中。

### 4.3 StageVisualTheme

`StageVisualTheme` 只保存表现资源和映射：

- 生/死世界场景；
- 生/死角色与编钟；
- 朱、玄、素、Hold、疾振的表现集；
- 怪物、随从、边界、相纹、VFX 和 UI 主题；
- 动画名、锚点、材质参数和质量档。

同一份 `SongChart` 可以加载灰模主题或正式主题。更换主题不得改变 Replay 结果。

## 5. 应用流程

```text
Boot
  → Title
  → StageSelect
  → StageLoading
  → Stage
  → Result
  → StageSelect
```

设置、校准、暂停和随从选择使用 Modal 层，不另建平行路由。

页面场景：

| 场景 | 主要内容 |
| --- | --- |
| `TitleScreen` | 开始、设置、校准、退出 |
| `StageSelectScreen` | 关卡卡片、试听、锁定状态、最好成绩、FC/AP、对应随从和装备入口 |
| `StageLoadingScreen` | 异步资源加载、取消和错误提示 |
| `ResultScreen` | 原始判定、得分、魂火、FC/AP、奖励和下一步 |

所有页面使用 Control 容器、明确的手柄焦点链和横屏安全区。玩法触点与 UI 触点分层，暂停按钮不能被左/右敲钟输入误触。

建议的全局服务只有：

| Autoload | 职责 |
| --- | --- |
| `AppRouter` | 页面切换、过渡和 RouteContext |
| `ContentCatalog` | 关卡、歌曲、随从和规则资源索引 |
| `SaveService` | 原子存档、迁移和备份 |
| `SettingsService` | 输入、音频、显示、辅助功能和偏移 |
| `MenuAudioService` | 菜单音乐、选关试听和 UI 音效 |

局内时钟、分数、血量、判定和演出事件都属于当前 `StageRoot`，不做 Autoload。局内通讯使用类型化 signal 或局部 `StageEventHub`，不建立一个接收所有事件的全局总线。

## 6. StageRoot

```text
StageRoot
├─ Session
│  ├─ SongClock
│  ├─ InputRouter
│  ├─ ChartScheduler
│  ├─ GameplayCoordinator
│  ├─ ScoreRuntime
│  ├─ HealthRuntime
│  ├─ PetRuntime
│  └─ StageEventHub
├─ Presentation
│  ├─ WorldPairView
│  │  ├─ LifeWorldSlot
│  │  └─ DeathWorldSlot
│  ├─ NoteVisualHost
│  ├─ FieldLayer
│  │  ├─ LifeWaveSlot
│  │  ├─ DeathWaveSlot
│  │  ├─ InterferenceSlot
│  │  └─ RapidSlot
│  ├─ StageDirector
│  ├─ VfxDirector
│  ├─ AudioFeedbackDirector
│  └─ CameraRig
├─ HudLayer
├─ PauseLayer
└─ DebugLayer
```

关卡状态：

```text
LOADING → READY → PREROLL → PLAYING → FINISHING → RESULT
                         ↕
                       PAUSED
                         \
                          → FAILING → RESULT
```

暂停时冻结歌曲位置和玩法状态。恢复前给短倒计时；正在进行的 Hold 或调频进入 `resume_rearm`，玩家在倒计时内重新按住所需输入，不额外触发头判。

## 7. 时间系统

`SongClock` 公开四个值：

| 时间 | 用途 |
| --- | --- |
| `audio_time_raw` | 监测音频播放位置和漂移 |
| `song_time` | 单调递增的关卡权威时间 |
| `judge_time` | `song_time` 应用玩家输入补偿后的判定时间 |
| `visual_time` | 平滑并应用视觉偏移后的表现时间 |

歌曲时间不能用 `_process(delta)` 累加。播放开始时用单调系统时钟建立原点，并补偿下一混音块和缓存的输出延迟；`AudioStreamPlayer.get_playback_position()` 加 `AudioServer.get_time_since_last_mix()` 只作为音频观测。输出延迟在开播或输出设备变化时刷新，不能每帧查询。

视觉可以平滑，判定不使用视觉滤波。暂停、Seek、重试和写谱器预览都走同一套 Clock 接口。

## 8. 输入与判定

### 8.1 统一输入语义

运行时只认识：

```text
life_pressed / life_released
death_pressed / death_released
tune_vector_changed(Vector2)
focus_cancelled
```

设备适配器：

- 触屏：左、右两个输入区，各自锁定 Touch ID；完成双按的触点成为本段调频指针。
- 手柄：左肩键敲死钟，右肩键敲生钟，摇杆输出 `tune_vector`。
- PC 开发：鼠标左键/F 敲死钟，右键/J 敲生钟；双键同时按住时，鼠标位移输出 `tune_vector`。

设备映射如下。表中的按键只存在于适配层，谱面和判定代码不得直接查询鼠标键、触点或手柄键：

| 玩法语义 | 移动端 | 手柄 | PC 开发测试 |
| --- | --- | --- | --- |
| 生钟按下/松开 | 右侧生钟输入区按下/松开 | 右肩键按下/松开 | 鼠标右键或 J 按下/松开 |
| 死钟按下/松开 | 左侧死钟输入区按下/松开 | 左肩键按下/松开 | 鼠标左键或 F 按下/松开 |
| 调频 | 双触点成立后拖动指定触点 | 摇杆 | 双键按住后移动鼠标 |
| 暂停/返回 | 界面按钮 | Start / B | Esc |

PC 鼠标方案按 Web 原型的操作习惯保留，但只用于开发期和桌面试玩包。进入双按调频后，`InputRouter` 读取 `InputEventMouseMotion.relative`，经过灵敏度、死区和范围归一化后输出调频向量；不使用屏幕绝对坐标，也不让鼠标位置影响谱面数据。调频期间可捕获或限制光标，退出调频、暂停、结算和离开关卡时恢复普通光标。

Godot `InputMap` 使用 `bell_life`、`bell_death`、`pause` 等玩法动作名，不使用 `left_click`、`button_a` 之类的设备名。局内输入在 `_unhandled_input()` 处理，让暂停菜单等 UI 先消费事件；被玩法接收后立即标记为已处理，避免右键或一次点击被多个系统重复响应。窗口失焦、打开 Modal、设备断开或关卡中止时统一发出 `focus_cancelled`，清空双钟保持和调频状态，防止“卡键”。

每次事件在进入 `InputRouter` 时记录单调时间戳。连续调频保存带时间戳的样本，`TuningEngine` 在固定音乐 tick 上插值采样；不能按渲染帧累计位移。

谱面保存归一化目标和引导方向，不保存鼠标像素距离、Hz 或音名。

### 8.2 输入所有权

同一输入只能由一个系统消费：

```text
激活的疾振区
  > 已起手的调频区
  > 普通 Tap / Hold
```

`ChartValidator` 禁止各系统的有效判定窗重叠。表现可以叠加，输入归属不能含糊。

### 8.3 音符合同

| 玩法 | 数据表达 | 判定结果 |
| --- | --- | --- |
| 朱/玄 Tap | `NoteEvent(kind=tap, affinity)` | 按下时判定一次 |
| 普通双押 | 同 tick 的两个 Note，共用 `group_id` | 两侧独立判定；组只负责共同受击、伤害和表现 |
| 朱/玄 Hold | `NoteEvent(kind=hold, duration)` | 头、持续、尾取最低等级 |
| 素音调频 | `TuningRegion + TuneCurve + SuTarget[]` | 起手、双按间隔、持续、目标误差和尾判取最低等级 |
| 双钟疾振 | `RapidRegion(required_strikes)` | 只统计符合交替规则的有效敲击，区域结束结算 |

MVP 使用 `PERFECT / GOOD / PASS / MISS`。`PASS` 算命中，保留 FC，但不能获得 AP；分值不得为零。所有窗口、伤害和分值放进 `GameplayRuleSet.tres`，不散落在脚本常量中。

FC 要求所有判定单位都不是 Miss，且没有散响导致的连击中断。AP 要求每个 Tap、Hold 整体、调频整体和疾振区域均为 Perfect。随从只影响奖励、血量或附加分，不能改写原始 `JudgmentRecord` 和 FC/AP。

### 8.4 血量

- 两界共用一条魂火。
- Miss 按 `damage_group_id` 扣一次血，避免双押或多段对象重复扣血。
- 空敲不扣血，但可中断连击；规则由 `GameplayRuleSet` 配置。
- 魂火归零立即进入 `FAILING`，音乐和演出短暂收束后结算失败。

## 9. 共享核心

建议的纯逻辑模块：

| 模块 | 职责 |
| --- | --- |
| `TempoMap` | tick、秒、小节和拍号换算 |
| `ChartMigrator` | 旧 schema 升级 |
| `ChartValidator` | ID、引用、区间、冲突、曲线和资源检查 |
| `ChartCompiler` | 生成只读、按时间排序的 `CompiledChart` |
| `NoteJudgeEngine` | Tap、双押和 Hold 状态机 |
| `TuningEngine` | 双按、保持、连续调频、素音目标和尾判 |
| `RapidEngine` | 交替、防抖、封顶和区域结算 |
| `ScoreEngine` | 基础分、连击与额外分分离 |
| `HealthEngine` | 伤害组与失败条件 |
| `PetEffectEngine` | 被动效果，不改原始判定 |
| `ResultEvaluator` | 通关、FC、AP、解锁和随从奖励 |
| `ReplayRunner` | 用时间戳输入重放完整状态机 |

这些模块使用可注入 Clock，在 headless 测试中不依赖真实音频设备。

## 10. 美术与表现接口

Web 原型不能作为白模画面参考。新的白模使用一套 `GrayboxVisualTheme`，它和正式美术包实现相同接口：

- 生界左上、死界右下；基础场景按中心旋转派生，允许死界覆盖层。
- HUD、文字、时机提示保持正向，不随死界旋转。
- 音符和怪物是可替换 `PackedScene`，程序只提供进度、状态、路径、判定和属相。
- Hold 的长度、相纹密度和疾振层数由程序生成，美术提供头尾、笔刷、纹理、遮罩和关键形象。
- 相纹 Renderer 输出可供美术重构的场或遮罩，不固定为圆点、波圈或直线滑槽。
- `StageShow` 驱动角色、怪物、场景、镜头和 VFX，减少逐关手工制作整段动画的工作量。

第一轮表现验证采用一段 10～15 秒的美术尖峰：朱 Tap、玄 Hold、素调频、疾振、Miss 掉血和一次随从触发。该段必须使用接近成片的层级、锚点、材质和构图。

详细素材格式、锚点、动画清单和 ArtLab 见 `《冥河，冥河！》MVP美术资产与演出接入规范.md`。

## 11. 写谱器

写谱器采用“可复用 Workspace + 薄 EditorPlugin 宿主”：

```text
ChartEditorWorkspace.tscn
├─ 独立工具场景入口
└─ Godot 主屏 EditorPlugin 入口
```

Workspace 负责时间线、波形、编辑命令、校验和预览；插件只负责嵌入 Godot、保存提示和编辑器生命周期。独立入口用于 UI 测试和故障回退。

正式关卡必须由该工具完成。若谱师仍需改 GDScript、手写 `.tres` 或进 Inspector 才能做完一张含全部机制和演出的谱，工具不算交付。

详细架构和验收见 `《冥河，冥河！》MVP写谱器架构.md`。

## 12. 存档与随从

```text
SaveData
├─ schema_version
├─ unlocked_stage_ids[]
├─ stage_records{score, rank, cleared, fc, ap}
├─ pets{pet_id, tier, acquired}
├─ equipped_pet_id
├─ tutorial_flags
└─ calibration_and_settings
```

存档先写临时文件，重读校验后替换正式文件，并保留最近一次备份。所有内容引用使用稳定 ID，不依赖数组下标。

## 13. 工程目录

```text
Game/
├─ addons/                               # Godot 编辑器插件入口；不放游戏规则
│  └─ minghe_chart_editor/               # 写谱器主屏插件、注册代码和插件图标
├─ assets/                               # 发行包会使用的原始导出素材
│  ├─ art/                               # PNG、WebP、SVG、序列帧等美术导出物
│  │  ├─ common/                         # 纸纹、噪声、通用遮罩和跨关卡共用底图
│  │  ├─ characters/                     # 生/死角色、编钟及其分层导出图
│  │  ├─ stages/                         # 按 s01、s02 分关的背景层、前景和关卡物件
│  │  ├─ notes/                          # 朱、玄、素、Hold、疾振所需贴图和图集
│  │  ├─ enemies/                        # 小怪、Boss 与受击/消散序列帧
│  │  ├─ followers/                      # 随从基础形态、进阶形态和触发反馈
│  │  ├─ ui/                             # HUD、面板、印章、图标等界面导出图
│  │  └─ vfx/                            # 粒子贴图、笔刷、流场纹理和特效遮罩
│  ├─ audio/                             # 发行版使用的音乐和音效
│  │  ├─ music/                          # 关卡 BGM、菜单音乐和选关试听音频
│  │  ├─ sfx/                            # 敲钟瞬态、判定、UI、受击等短音效
│  │  └─ ambience/                       # 风声、祭场底噪等可循环环境声
│  ├─ fonts/                             # 字体文件、Fallback 字体和许可证
│  └─ ui/                                # Godot Theme、StyleBox、光标等界面资源
├─ editor_assets/                        # 仅供制谱和调试，发行预设明确排除
│  ├─ authoring_profiles/                # SongAuthoringProfile 与音频路径配置
│  ├─ audio_proxy/                       # 便于精确看波形的 PCM WAV 制谱副本
│  ├─ waveform_cache/                    # 自动生成的波形峰值缓存，不手工编辑
│  └─ templates/                         # 新谱、演出轨和测试段落模板
├─ content/                              # 有游戏语义的自定义 Resource 数据
│  ├─ catalogs/                          # ContentCatalog 及稳定 ID 到资源的索引
│  ├─ rules/                             # 判定窗、计分、伤害、调频和疾振规则集
│  ├─ stages/                            # 按关卡 ID 组织可加载的完整内容包
│  │  ├─ s01/                            # 第一关的定义、歌曲、谱面、演出与奖励
│  │  └─ s02/                            # 可选第二关；结构与 s01 完全相同
│  ├─ pets/                              # PetDefinition、进阶条件和被动效果参数
│  └─ visual/                            # 由程序/技术美术组装的表现映射资源
│     ├─ characters/                     # 角色场景、动画名和锚点映射
│     ├─ stages/                         # Graybox/正式 StageVisualTheme
│     ├─ note_sets/                      # 各音符族对应的可替换 VisualSet
│     ├─ followers/                      # 随从场景与触发表现配置
│     └─ vfx_banks/                      # 语义事件到 VFX/材质预设的映射
├─ scenes/                               # 节点组合与可实例化场景，不保存规则常量
│  ├─ app/                               # Boot、Main、ScreenHost 和 ModalHost
│  ├─ screens/                           # Title、StageSelect、Loading、Result 页面
│  ├─ stage/                             # StageRoot、Session、HUD 等局内场景骨架
│  ├─ presentation/                      # 与判定解耦的局内画面实例
│  │  ├─ actors/                         # 生/死角色、编钟、怪物、随从场景
│  │  ├─ worlds/                         # 生界、死界、边界和中心对称容器
│  │  ├─ notes/                          # 音符宿主与各类默认/灰模表现
│  │  ├─ fields/                         # 声波、相纹、调频和疾振场表现
│  │  └─ vfx/                            # 命中、Miss、掉血、转场等特效场景
│  ├─ ui/                                # 可复用的 Control 场景
│  │  ├─ components/                     # 按钮、卡片、数值、提示等基础组件
│  │  ├─ hud/                            # 分数、连击、魂火、进度和调频引导
│  │  └─ modals/                         # 暂停、设置、校准、确认与错误弹窗
│  └─ tools/                             # 可独立运行的开发工具场景
│     ├─ chart_editor/                   # ChartEditorWorkspace 及编辑面板场景
│     └─ art_lab/                        # 美术资产、锚点、动画和 VFX 检视场景
├─ src/                                  # GDScript 源码；目录按职责而非场景名划分
│  ├─ app/                               # 应用流程、页面协调和 RouteContext
│  ├─ content/                           # Resource 类、目录加载、编译、迁移和校验
│  ├─ domain/                            # 不依赖场景树的可测试玩法核心
│  │  ├─ timing/                         # TempoMap、tick/秒换算和时间段查询
│  │  ├─ chart/                          # 谱面事件、CompiledChart 与调度查询
│  │  ├─ judgment/                       # Tap、双押、Hold 判定状态机
│  │  ├─ tuning/                         # 双按成立、连续调频和素音目标判定
│  │  ├─ rapid/                          # 疾振交替、防抖、计数与区域结算
│  │  ├─ score/                          # 判定分、连击和附加分计算
│  │  ├─ health/                         # 魂火、伤害组和失败条件
│  │  ├─ pets/                           # 随从被动效果与奖励修正
│  │  └─ results/                        # 通关、FC、AP、解锁和奖励汇总
│  ├─ runtime/                           # 一次关卡会话中的有状态协调对象
│  │  ├─ clock/                          # SongClock、延迟补偿、暂停和 Seek
│  │  ├─ input/                          # InputRouter 与触屏/手柄/PC 设备适配器
│  │  ├─ scheduler/                      # ChartScheduler、预生成和回收时机
│  │  ├─ session/                        # GameplayCoordinator 与关卡状态机
│  │  └─ replay/                         # 输入记录、回放和确定性核验
│  ├─ presentation/                      # 将语义事件翻译为画面、镜头和声音
│  │  ├─ directors/                      # Stage、VFX、相机和音频反馈导演
│  │  ├─ adapters/                       # Domain 状态到场景节点属性的适配
│  │  ├─ audio/                          # 局内音频反馈、Bus 和混音控制
│  │  └─ pooling/                        # 音符、怪物和特效对象池
│  ├─ services/                          # 跨页面、长生命周期的应用服务
│  │  ├─ navigation/                     # AppRouter 与页面过渡
│  │  ├─ catalog/                        # 内容索引、异步加载和错误报告
│  │  ├─ save/                           # 存档、迁移、备份和恢复
│  │  └─ settings/                       # 音频、画面、输入、校准和辅助设置
│  └─ tools/                             # 工具逻辑，共享 domain 而不复制判定
│     ├─ chart_editor/                   # 时间线、命令、选区、预览和导出逻辑
│     ├─ art_lab/                        # Manifest 检查、换肤和演出测试逻辑
│     └─ validators/                     # 谱面、内容引用和美术交付批量检查
├─ shaders/                              # 版本化的 Shader 与可复用 ShaderInclude
│  ├─ fields/                            # 声波、相纹、调频场和疾振场
│  ├─ materials/                         # 角色、场景、音符的局部材质效果
│  └─ screen_fx/                         # 调色、受击、转场等全屏效果
└─ tests/                                # 自动测试；不进入发行包
   ├─ unit/                              # 单模块纯逻辑测试
   │  ├─ timing/                         # tick/秒、BPM、拍号和 offset
   │  ├─ judgment/                       # 各音符判定窗和边界输入
   │  ├─ tuning/                         # 调频采样、曲线误差和双按状态
   │  └─ editor_commands/                # 撤销、重做和序列化稳定性
   ├─ integration/                       # 多模块协作与场景级测试
   │  ├─ stage/                          # 完整关卡、暂停、失败和结算流程
   │  ├─ app_flow/                       # 主界面、选关、加载和返回流程
   │  └─ save/                           # 存档迁移、损坏恢复和奖励落盘
   ├─ editor/                            # 写谱器启动、保存、预览和插件生命周期
   └─ fixtures/                          # 自动测试专用的固定输入数据
      ├─ charts/                         # 极短谱、边界谱和全机制测试谱
      ├─ replays/                        # 已知结果的时间戳输入记录
      └─ saves/                          # 各 schema 版本和损坏存档样本

ArtSource/                               # Godot 工程外的美术工作源文件
├─ _templates/                           # 画布、分层、锚点和导出模板
├─ characters/                           # PSD/CLIP 等角色与编钟源文件
├─ stages/                               # 分层场景、背景和关卡物件源文件
├─ notes/                                # 音符、纹样和形变设计源文件
├─ enemies/                              # 小怪和 Boss 源文件
├─ followers/                            # 随从基础/进阶形态源文件
├─ ui/                                   # HUD、界面、字体排版和图标源文件
└─ vfx/                                  # 特效序列、笔刷、遮罩和材质参考
```

目录边界按下面四条执行：

1. `assets/` 放“导出的原料”，`content/` 放“带玩法或表现语义的 Resource”，`scenes/` 放“节点组合”，`src/` 放“逻辑”；同一职责不在多处各存一份。
2. `addons/minghe_chart_editor/` 只是编辑器宿主。时间、谱面、判定、命令和校验仍在 `src/`，避免插件版与游戏版分叉。
3. `addons/minghe_chart_editor/`、`editor_assets/`、`scenes/tools/`、`src/tools/` 和 `tests/` 在发行导出预设中排除；写谱器自动保存和崩溃恢复文件写入 `user://editor_recovery/`，不写回仓库。
4. `.godot/` 是引擎生成缓存，不纳入版本管理；`.import` 元数据与对应素材一起提交。美术源文件只进 `ArtSource/`，确认导出后再进入 `Game/assets/`。

## 14. 测试要求

### 14.1 自动测试

- 多 BPM、拍号、首拍偏移与 tick/秒往返；
- 每种音符的边界、重复输入、漏判和最差等级；
- 调频在 30/60/120 FPS 及不规则帧步下输出一致；
- 暂停、重试、Seek、失焦、多点触控取消、手柄回中和鼠标双键取消；
- 真实状态机 Replay 的确定性，不使用理论结果占位；
- FC/AP、伤害组、零血失败、随从解锁和单槽装备；
- 标题、选关、关卡、结算和存档的完整流程；
- 写谱器命令撤销、保存重载、迁移、编译哈希和预览一致性；
- `GrayboxVisualTheme` 与正式主题生成相同判定记录。

### 14.2 人工设备测试

- Android/iOS 目标机型的多点触控和安全区；
- PC 鼠标左/右键敲钟、双键移动调频、失焦恢复和光标状态；
- PC 手柄、不同刷新率和有线/蓝牙音频；
- 60 FPS 下相纹、透明场景层和粒子的 GPU 开销；
- 朱、玄、素在强演出下仍能读谱；
- 降低闪光、降低震动和低画质模式。

Headless 使用 Dummy 音频，不能代替真实设备的延迟测试。

## 15. 实施顺序

| 阶段 | 产物 | 退出条件 |
| --- | --- | --- |
| M0 合同冻结 | 数据结构、规则资源、时钟和输入接口 | 旧异拍字段全部移除；调频、Hold、FC/AP 规则无歧义 |
| M1 纵向切片 | Tap + BGM + 新白模主题 + 写谱器基础时间线 | 同一 Tap 在工具和关卡中结果一致 |
| M2 全机制 | Hold、调频、素音、疾振、血量、结算 | 全机制测试谱可完整自动重放 |
| M3 应用流程 | 主界面、选关、存档、随从、设置与校准 | 从启动到获得随从的流程可走通 |
| M4 美术尖峰 | 10～15 秒近成片片段、ArtLab、资产校验 | 替换主题资源无需改判定代码 |
| M5 工具定版 | 全部编辑功能、备份恢复、插件宿主 | 谱师无需改代码可独立完成并维护谱面 |
| M6 首关 | 正式歌曲、谱面、演出和随从 | 关卡由写谱器产出并通过设备测试 |
| M7 第二关 | 复用架构制作第二套内容 | 不新增关卡专用玩法脚本 |

写谱器不是最后补做的辅助工具。M1 就建立可用时间线，之后每种机制必须同时完成运行时、编辑能力、校验和预览。

## 16. 架构验收

满足以下条件后才进入大规模内容制作：

1. 一份谱面在写谱器预览和正式关卡中的判定记录完全一致。
2. 更换 `StageVisualTheme` 不改变任何得分、血量和 FC/AP 结果。
3. 两关可以使用同一个 `StageRoot`，仅替换资源。
4. 美术可通过资产包改变音符、怪物、相纹、场景和边界造型，不需要程序增加专用分支。
5. 谱师可以在工具内完成音频导入、谱面、调频曲线、疾振、演出轨、校验和发布。
6. 真实 Replay 在不同帧步下保持确定性。

## 17. Godot 4.6 依据

- [音频与玩法同步](https://docs.godotengine.org/en/4.6/tutorials/audio/sync_with_audio.html)
- [Resources](https://docs.godotengine.org/en/4.6/tutorials/scripting/resources.html)
- [EditorPlugin 主屏插件](https://docs.godotengine.org/en/4.6/tutorials/plugins/editor/making_main_screen_plugins.html)
- [命令行与 Headless](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)
