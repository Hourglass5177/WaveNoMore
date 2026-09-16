# 《冥河，冥河！》MVP 写谱器架构

> **新版正式设计入口（2026-09-06）：** 后续开发以[《写谱器设计说明书》](./《冥河，冥河！》写谱器设计说明书.md)为准，确定 Windows 独立应用、实时预览、单工具 Tap/Hold 和 JSON 共同协议；调频与素音只留扩展边界。[《调研与重构设计原则》](./《冥河，冥河！》写谱器调研与重构设计原则.md)提供来源与取舍。本文继续保留当前实现记录及历史方案，不作为新版范围依据。

> 文档状态：已补当前实现对照，原方案保留参考  
> 宿主：Godot 4.7 主屏插件 + 独立工具场景  
> 更新日期：2026-09-06；原方案日期：2026-08-23  
> 目标用户：内部谱师、主策划、演出配置人员和技术美术

## 当前实现对照（2026-09-06）

工具已有实现，尚未达到下文“完备”目标。实际入口为 Godot 顶部“冥河写谱器”主屏页签，以及 `scenes/tools/chart_editor/standalone_chart_editor.tscn`。

- `EditorDocument` 深复制并编辑 SongChart / StageShow；歌曲、主题、规则和奖励只读引用。新建关卡在内存建立完整依赖，首次保存生成六文件包，规则继续引用公共资源。
- 已有 Tap、Hold、普通双押、调频场、单侧及成组双侧滑条、素音、疾振和演出 cue；支持选择、拖动、拉伸、复制、属性编辑与 ID 重映射。圆弧朝向 `arc_rotation_deg` 和视觉偏移 `visual_offset_px` 可编辑。
- 已有 200 步快照历史、校验定位、保存备份与恢复、PCM16 WAV 多声道波形、循环试听及变速。试听通过 pitch_scale 变速，也会变调。
- 插件保存项目时只写恢复稿；正式保存仍用写谱器保存操作。当前未采用 EditorUndoRedoManager。
- 预览复用正式 StageRoot；中途预览裁掉已起手事件，不恢复跨越起点的 Hold、调频场等机制状态。
- 尚缺完整歌曲元数据、变拍网格、SongAuthoringProfile、输入录制制谱和完整演出预设。

静态检查发现两处待修问题：工作区打开路径式关卡时，在解析依赖前检查 chart / stage_show，可能拒绝当前五关；工作区预览起点换算未减首拍偏移，当前 2 秒偏移会使预览位置后移 4 拍。这两项不能用文档层或 PreviewBridge 单元测试通过来视为界面已可用。

下文保留 2026-08-23 的目标方案；现行接口和限制见[工程代码导览](./《冥河，冥河！》Godot工程代码导览.md)。

## 原方案（2026-08-23）

## 1. “完备”的定义

MVP 写谱器不是只会放 Tap 的小工具。谱师应能从一首音频开始，在工具内完成正式关卡的判定谱和演出轨，并交给游戏直接读取。

交付条件：

- 不改 GDScript；
- 不手写 `.tres`；
- 不依赖 Inspector 补字段；
- 能制作朱/玄 Tap、Hold、普通双押、素音调频、双钟疾振；
- 能配置角色、怪物、场景、镜头和 VFX 演出；
- 能试听、循环、变速、预览、校验、保存、恢复；
- 写谱器预览和正式关卡使用同一套规则；
- MVP 的正式关卡确实由该工具产出。

## 2. 宿主结构

```text
ChartEditorWorkspace.tscn          # 普通 Control 场景，功能主体
├─ StandaloneToolHost              # 独立运行，便于测试和故障回退
└─ ChartEditorPluginHost           # 嵌入 Godot 主屏
```

插件宿主只处理：

- 把 Workspace 加入 Godot 主屏；
- 编辑器页签显隐；
- 未保存提示；
- 保存项目时提交当前编辑；
- 将 `EditorUndoRedoManager` 适配为统一命令历史。

时间线、文档、校验和预览不依赖 EditorPlugin API。Godot 编辑器升级时，受影响的代码集中在薄宿主中。

## 3. 与游戏共用的核心

```text
ChartDocument（可编辑）
        │
        ├─ EditCommand / CommandHistory
        ├─ ChartValidator
        ├─ ChartCompiler
        └─ ResourceSaver
                │
                ▼
         CompiledChart（只读）
                │
                ▼
        PreviewBridge → StageSession
```

共用内容包括：

- `TempoMap`；
- 事件 ID 与确定性排序；
- 所有音符和区域定义；
- 判定窗口与 `GameplayRuleSet`；
- 调频曲线求值；
- 疾振状态机；
- `StageShow` cue；
- 校验器、迁移器和编译器。

工具预览不能用“看起来差不多”的替代规则。

## 4. 文档会话

```text
ChartEditorSession
├─ SongDefinition
├─ SongAuthoringProfile
├─ SongChart
├─ StageShow
├─ StageVisualTheme
├─ SelectionModel
├─ CommandHistory
├─ DirtyState
├─ ValidationReport
├─ AutosaveState
└─ PreviewState
```

`SongChart` 和 `StageShow` 分文件保存，但在一个会话中同步编辑。选择、缩放、折叠轨道和播放头属于 UI 状态，不写进正式谱面。

`SongAuthoringProfile` 只保存制谱 WAV、波形缓存和谱师工作设置。正式关卡不引用它。

## 5. 界面布局

```text
┌──────────────── Transport / 时间 / Snap / 预览模式 ────────────────┐
│ Track Tree │  波形 + 小节拍网格 + 多轨时间线          │ Inspector │
│            │                                         │           │
│            │                                         │           │
├────────────┴─────────────────────────────────────────┴───────────┤
│ Validation / Event List / Preview Log                            │
└──────────────────────────────────────────────────────────────────┘

右侧或独立窗口：Gameplay Preview
```

### 5.1 顶部 Transport

- 播放、暂停、停止、Seek；
- 循环区间；
- 0.5×、0.75×、1.0× 速度；
- 节拍器和预卷；
- 当前秒、tick、小节:拍:tick；
- Snap 粒度和临时自由放置；
- 输入/视觉偏移仅用于预览，不写回谱面事件。

### 5.2 轨道树

```text
Timing
  Tempo
  Meter
  Sections
Gameplay
  朱音
  玄音
  调频区域
  素音目标
  双钟疾振
StageShow
  角色
  怪物与关卡物
  场景与调色
  镜头
  VFX
  音频提示
  教程
```

轨道可以锁定、静音、独奏、折叠和调整显示高度。锁定只影响编辑，不影响预览。

## 6. 编辑能力

MVP 必须支持：

- 单选、框选、多选；
- 新增、删除、拖动、拉伸；
- 复制、粘贴、重复；
- 批量移位、量化和改属相；
- 缩放、水平滚动、跳转、书签和段落；
- 键盘快捷键；
- 命令式 Undo/Redo；
- Inspector 精确输入；
- 事件列表和搜索；
- 点击错误直接定位；
- 在时间线上录制输入。

拖动过程只更新临时预览。松手后提交一条命令，避免每个鼠标像素都进入撤销历史。连续修改单个值时使用合并命令。

## 7. 各机制怎样编辑

| 机制 | 时间线表达 | 主要属性 | 专用操作 |
| --- | --- | --- | --- |
| Tap | 单点事件 | tick、朱/玄、分组、视觉变体 | 点击放置、批量量化 |
| 普通双押 | 同 tick 的两枚 Tap | 共同 `group_id` | 一键生成/拆分双押 |
| Hold | 可拉伸块 | 起点、时长、尾判、视觉变体 | 拖尾调整长度 |
| 调频 | 区域块 + 曲线 | 起止、双按窗、容差、引导方向、目标曲线 | 控制点编辑或实录 |
| 素音 | 调频区内检查点 | tick、目标值、容差、视觉变体 | 吸附到调频曲线 |
| 疾振 | 区域块 | 起止、required_strikes、防抖、视觉预设 | 密度预览和压力提示 |
| 演出 cue | 对应轨道事件/区域 | cue ID、参数、目标槽位 | 资产浏览器选择与成片预览 |

### 7.1 调频编辑

调频区显示三层信息：

1. 区域起止和双按起手；
2. 归一化目标曲线；
3. 素音检查点及容差带。

谱师可用两种方式制作曲线：

- 直接添加控制点，使用阶梯或线性插值；
- 在预览中按住双钟并拖动/推摇杆，录制带时间戳的输入，再按容差简化为控制点。

谱面不保存屏幕像素和实际 Hz。写谱器可以显示 0～1 的技术数值，正式玩家界面不显示。

### 7.2 演出编辑

`StageShow` 轨道从当前 `StageVisualTheme` 读取 cue 列表。谱师选择稳定 `cue_id`，不直接填写场景路径或深层 NodePath。

常用 cue：

- 角色动画；
- 怪物/关卡物生成与回收；
- 世界层移动、显隐和调色；
- 边界变化；
- 镜头位移、缩放和震动强度；
- 相纹、粒子和屏幕特效预设；
- 教学文字和安全提示。

## 8. 波形与音频

发行音乐使用 OGG。制谱时为每首歌保留一份 16-bit PCM WAV 代理文件，写谱器从 WAV 数据生成多级 min/max 峰值缓存：

```text
WaveformCache
├─ overview
├─ medium_zoom
└─ detail_zoom
```

缓存以源文件哈希和修改时间判断失效。制谱 WAV 与缓存放在 `Game/editor_assets/`，从发行导出中排除。

`AudioEffectCapture` 只用于实时电平或辅助显示，不用于整曲波形生成；它必须等待实时播放，无法满足打开歌曲后立即写谱。

首拍偏移、谱面偏移、输入补偿和视觉偏移必须分成四个字段，不允许一个 `offset` 同时承担多种语义。

## 9. 撤销、保存和恢复

统一接口：

```text
CommandHistory
├─ EditorCommandHistory      EditorUndoRedoManager
└─ StandaloneCommandHistory  UndoRedo
```

所有数据修改都经过命令，包括新增、移动、删除、拉伸、批量粘贴、改 BPM 和曲线编辑。

保存流程：

```text
编译与强校验
  → ResourceSaver 保存到临时 .tres，并检查 Error
  → 重新加载并比较关键哈希
  → 替换正式文件
  → 保留最近备份
```

工具还要提供：

- 脏标记和未保存提示；
- 定时自动保存；
- 崩溃恢复会话；
- schema 迁移；
- 确定性序列化；
- 稳定 ID，不因复制粘贴发生重复。

## 10. 校验器

错误分为 `error / warning / info`。有 error 时不能发布正式谱面。

最低检查项：

- 重复 ID、空引用和循环引用；
- TempoMap 无效、事件越界、负时长；
- 普通、调频和疾振的输入判定区重叠；
- Hold 头尾冲突和无法完成的松手间隔；
- 调频区缺曲线、素音脱离所属区域、容差无效；
- 疾振目标次数与时长不合理；
- `group_id` 只有一侧或跨越过远；
- `StageShow` cue 不存在、参数类型错误；
- VisualTheme 缺少所选变体或锚点；
- 理论满分、判定单位数和伤害组可计算；
- 曲终后仍有未结束的玩法区域；
- 高风险视觉密度和手部疲劳提示。

校验结果包含事件 ID、轨道和 tick。点击后选中事件并把播放头移到问题位置。

## 11. 正式运行时预览

`PreviewBridge` 创建一套可 Seek 的 `StageSession`。预览提供：

- 纯判定灰模；
- 当前正式美术主题；
- 判定区域、锚点、路径和安全区调试层；
- 16:9、20:9、16:10 画幅；
- Perfect Replay、手动游玩和典型失败 Replay；
- 从当前乐段起播和循环；
- 判定日志、活动输入所有者和曲线误差。

核心对象必须能从绝对 `visual_time` 重建。粒子不要求逐帧倒放；拖动结束后从当前时间重新触发即可。

## 12. 工具内部组件

```text
src/tools/chart_editor/
├─ chart_editor_workspace.gd
├─ chart_editor_session.gd
├─ document_controller.gd
├─ timeline/
│  ├─ timeline_view.gd
│  ├─ track_tree.gd
│  ├─ event_view.gd
│  └─ curve_editor.gd
├─ commands/
├─ inspectors/
├─ waveform/
├─ validation/
├─ preview/
├─ autosave/
└─ hosts/
```

`addons/minghe_chart_editor/` 只保存 `plugin.cfg` 和薄宿主脚本。共享核心、Workspace 和正式资源类不能放进 addon 内部。

## 13. 快捷键基线

| 操作 | 快捷键 |
| --- | --- |
| 播放/暂停 | Space |
| 保存 | Ctrl+S |
| 撤销/重做 | Ctrl+Z / Ctrl+Shift+Z |
| 复制/粘贴/重复 | Ctrl+C / Ctrl+V / Ctrl+D |
| 删除 | Delete |
| 临时关闭 Snap | 按住 Alt |
| 框选追加 | Shift |
| 水平缩放 | Ctrl+滚轮 |
| 跳到播放头 | F |
| 设置循环起止 | I / O |

快捷键集中配置，避免散落在 Control 节点中。

## 14. 自动测试

- 每条 EditCommand 的 do/undo/redo；
- 连续拖动合并和批量命令；
- 保存、重载、迁移和哈希一致；
- 稳定 ID 和确定性排序；
- 波形缓存采样、缩放层级和失效；
- 调频录制、曲线简化和固定 tick 采样；
- Validator 错误定位；
- 工具预览与正式 StageSession 的 JudgmentRecord 一致；
- 插件显隐、未保存提示和退出保护。

## 15. MVP 不包含

- 在线协作和多人同时编辑；
- Steam Workshop 或玩家 UGC；
- 通用 MIDI/Osu/StepMania 全格式导入；
- 自动 AI 写谱；
- 独立于项目发布的商业制谱软件；
- 任意 Godot 场景编辑替代器。

旧 Web JSON 可做一次性迁移脚本，但它不是正式格式。

## 16. 验收用例

由一名没有参与工具开发的谱师执行：

1. 新建歌曲，设置首拍、BPM 和拍号。
2. 制作一段含 Tap、双押、Hold、调频、素音和疾振的谱。
3. 为同一段添加角色、怪物、场景和 VFX cue。
4. 在 0.75× 下循环试听并修正调频曲线。
5. 处理所有校验错误，保存并关闭工具。
6. 重新打开，确认时间和事件没有漂移。
7. 在正式选关流程加载该关，得到与预览一致的判定结果。
8. 执行一次错误操作并完整 Undo/Redo。
9. 模拟异常退出，恢复自动保存版本。

九项全部通过，才算“完备写谱工具”进入 MVP。
