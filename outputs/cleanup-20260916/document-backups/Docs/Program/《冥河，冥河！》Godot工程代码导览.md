# 《冥河，冥河！》Godot 工程代码导览

> 同步日期：2026-09-06  
> 适用工程：<code>Game/project.godot</code> 当前工作区（按源码与资源静态核对）  
> 引擎：Godot 4.7，GDScript，GL Compatibility  
> 本文是代码索引，不代替策划案。尚未落地的设想不会写成已实现功能。

第一次接触本工程，建议先打开同目录下的
[《冥河，冥河！》Godot工程手册.html](./《冥河，冥河！》Godot工程手册.html)。
那份手册按实际工作顺序讲解；本文更适合在已经知道要找什么时快速定位代码。

## 1. 三分钟总览

### 1.1 工程按职责分为四层

~~~text
content：关卡、谱面、规则、演出、主题、奖励
   ↓ 编译
domain：时间换算、判定、调频、载波、实体波、分数、魂火
   ↓ 由节点接入 Godot 生命周期
runtime：歌曲时钟、输入、调度、一局状态机、Replay
   ↓ 发信号和快照
presentation：音符、滑条、声波、相纹、HUD、音效
~~~

另有三块外围代码：

- <code>src/app</code> 与 <code>src/services</code>：标题、选关、加载、设置、存档、随从和页面切换；
- <code>src/tools</code> 与 <code>addons</code>：写谱器、美术验收工具和内容工具；
- <code>tests</code>：领域、输入、关卡、应用、存档、工具与视觉取样。

最重要的边界是：<strong>domain 决定结果，presentation 解释结果。</strong>
移动一个画面节点不应改变判定；不同帧率也不应改变同一份 Replay 的成绩。

### 1.2 快速试玩

1. 用 Godot 4.7 打开 <code>Game/project.godot</code>。
2. 按 F5 运行项目主场景。
3. 从标题页进入选关页，选择下面五张测试关之一。
4. 设置页可以打开“显示调试 HUD”，查看时间轴、输入所有权、频率和波前状态。

| 关卡 | 当前用途 | 时长约 |
| --- | --- | ---: |
| s01 空按与持续发波 | 没有音符，只看单钟、双钟载波和相纹能否持续 | 26 秒 |
| s02 Tap 音符测试 | 四分、八分、同侧重复、双押和混合节奏 | 54 秒 |
| s03 Hold 音符测试 | 短 Hold、长 Hold、错位、双侧和混合长度 | 54 秒 |
| s04 旋钮调频测试 | 单侧、双侧、旋转朝向、往返、短弧连续起手与素音 | 66 秒 |
| s05 综合机制测试 | Tap、Hold、单侧调频、双侧调频和机制切换 | 82 秒 |

五关均为 120 BPM、4/4、PPQ 480，首拍偏移 2 秒；使用程序节拍音，关闭奖励并默认解锁。s02 有 84 枚 Tap，s03 有 48 枚 Hold；s04 有 21 条滑条、2 个调频场、2 个素音事件；s05 有 56 枚普通音符、18 条滑条、6 个场、1 个素音事件。

五关都设置了 <code>debug_nonlethal = true</code>。Miss 仍会扣魂火，数值可以降到负数，但不会提前结束测试。

### 1.3 当前操作

| 动作 | 鼠标 | 键盘 | 手柄 |
| --- | --- | --- | --- |
| 生钟（左上角色） | 右键 | J / 右方向键 | R1 |
| 死钟（右下角色） | 左键 | F / 左方向键 | L1 |
| 生钟调频 | 按住右键并水平拖动 | PC 临时方案同鼠标 | 按住 R1，旋转右摇杆 |
| 死钟调频 | 按住左键并水平拖动 | PC 临时方案同鼠标 | 按住 L1，旋转左摇杆 |
| 双钟调频 | 同时按住左右键后拖动，两侧暂时同量变化 | 同左 | 两根摇杆完全独立 |
| 确认 / 取消 | 左键 | Enter、Space / Esc | A / B |
| 暂停 | — | Esc | Start |

键盘按钟不等于按住物理鼠标按钮；鼠标拖动要求对应鼠标按钮本身按住。触屏以上半屏控制生、下半屏控制死，各指水平拖动独立调频。手柄仅对应肩键建立调频输入所有权。

手柄旋转不是“把摇杆推到某个角度”。摇杆绕中心继续转动才产生位移；保持一个方向不动，频率也不动。屏幕坐标中顺时针为正，逆时针为负。

### 1.4 常用词

| 名词 | 工程里的含义 |
| --- | --- |
| tick | 谱面时间单位。当前固定 PPQ 480，即一个四分音符为 480 tick。 |
| song time | 歌曲本身走到哪里，不含输入补偿。 |
| judge time | 判定输入使用的时间轴。 |
| visual time | 提前或延后画面的时间轴。 |
| Resource / <code>.tres</code> | 可保存的数据对象；谱面、规则、主题和关卡定义都属于 Resource。 |
| Scene / <code>.tscn</code> | 可实例化的节点树，类似预制组合。 |
| Node | 进入场景树、有生命周期的运行对象。 |
| RefCounted | 不进入场景树的轻量逻辑对象，适合纯计算。 |
| Autoload | 项目启动后常驻的全局节点。 |
| Graybox | 验证尺寸、机制和接线的程序占位表现，不是正式美术。 |

## 2. 目录地图

~~~text
Game/
├─ project.godot          主场景、autoload、窗口、音频与 Input Map
├─ content/               可玩的关卡、谱面、规则、奖励与美术清单
├─ src/
│  ├─ content/            Resource 类型与跨层枚举
│  ├─ domain/             不依赖画面的玩法真值
│  ├─ runtime/            Godot 节点接线与一局生命周期
│  ├─ presentation/       画面、音效、HUD 与 VFX
│  ├─ app/                标题、选关、加载、结算与弹窗
│  ├─ services/           全局路由、目录、存档、设置与试听
│  └─ tools/              写谱器、ArtLab 与工具脚本
├─ scenes/                上述节点的场景装配
├─ shaders/               调频与疾振相纹 Shader
├─ addons/                Godot 编辑器插件入口
├─ assets/                运行时资产与音频总线
├─ editor_assets/         工具模板
└─ tests/                 自动测试与视觉取样
~~~

<code>res://</code> 的根就是 <code>Game/</code>。<code>user://</code> 是每台电脑自己的可写目录，存档、设置、Replay、波形缓存和写谱器恢复文件都在这里。

### 2.1 五个 autoload

| 名称 | 路径 | 职责 |
| --- | --- | --- |
| AppRouter | <code>src/services/navigation/app_router.gd</code> | 页面路由和返回历史 |
| ContentCatalog | <code>src/services/catalog/content_catalog.gd</code> | 按 ID 查关卡、随从和默认规则；自动扫描 content/stages |
| SaveService | <code>src/services/save/save_service.gd</code> | 通关、FC/AP、解锁、随从与装备 |
| SettingsService | <code>src/services/settings/settings_service.gd</code> | 音量、校准、显示和相纹强度 |
| MenuAudioService | <code>src/services/menu_audio/menu_audio_service.gd</code> | 选关试听能力 |

关卡内的时钟、判定、波与画面没有做成 autoload。每次进入关卡都会创建一套新的 <code>StageRoot</code>，离开关卡时一起清理。

## 3. 从启动到一局结束

### 3.1 页面链

~~~text
app_main.tscn
└─ AppMain
   ├─ ScreenHost：标题 / 选关 / 加载 / 关卡 / 结算
   └─ ModalHost：设置 / 校准 / 随从

标题 → 选关 → 异步加载 → StageRoot → 结算
                              ↘ 重试 / 返回选关
~~~

<code>AppRouter</code> 只发出“想去哪里”的请求，<code>AppMain</code> 才真正移除旧页面、实例化新页面，并把上下文交给它。

### 3.2 一关的固定场景树

~~~text
StageRoot
├─ Session
│  ├─ SongPlayer
│  ├─ SongClock
│  ├─ InputRouter
│  ├─ ChartScheduler
│  ├─ GameplayCoordinator
│  ├─ StageSession
│  ├─ ReplayInputDriver
│  ├─ ReplayRecorder
│  └─ StageShowDirector
├─ Presentation
│  ├─ GrayboxStagePresentation
│  └─ AudioFeedbackDirector
├─ HudLayer
├─ PauseLayer
└─ DebugLayer
~~~

<code>StageRoot</code> 是装配器，不写判定算法。它找到固定子节点，连接信号，并对外提供配置关卡、重试、Seek 和清理入口。

### 3.3 每帧真正发生什么

<code>StageSession</code> 先从 <code>SongClock</code> 取得一次统一时钟样本，再按时间顺序处理输入和自动事件：

~~~text
取 ClockSample
→ 把输入按 timestamp_us + sequence 排序
→ 推进到输入发生前
→ 处理输入
→ 推进到当前帧终点
→ 排出判定、波发射、接触和抵达事件
→ 更新 Scheduler、ShowDirector、HUD 与 Presentation
~~~

端点上的输入先于同一时刻的自动结算处理。例如疾振最后一拍的合法敲击会先计数，随后区域才结束。

## 4. 内容数据：一关由什么组成

### 4.1 六资源关卡包

~~~text
content/stages/sXX/
├─ stage_definition.tres      关卡身份与六项依赖路径
├─ song_definition.tres       歌曲、首拍、试听和无音频回退时长
├─ song_chart.tres            玩法谱面
├─ stage_show.tres            演出轨
├─ stage_visual_theme.tres    本关场景、色板与视觉引用
└─ reward_definition.tres     解锁与随从奖励
~~~

<code>StageDefinition</code> 可以直接持有 Resource，也可以只写路径。选关页读取轻量壳，确认后由加载页解析依赖，避免为了显示标题就提前载入整首歌和整张谱。

### 4.2 SongChart Schema 2

<code>src/content/resources/song_chart.gd</code> 是当前谱面合同。核心轨道如下：

| 轨道 | Resource | 是否直接计分 | 含义 |
| --- | --- | --- | --- |
| 普通音符 | <code>NoteEvent</code> | 是 | Tap 或 Hold |
| 调频场 | <code>TuningFieldRegion</code> | 否 | 只声明何时允许改变频率 |
| 调频滑条 | <code>TuningSliderEvent</code> | 是 | 某一口钟的起点、终点、单程时长和往返次数 |
| 素音凝现 | <code>SuManifestationEvent</code> | 否 | 声明时机、数量与允许区域；精确坐标运行时求出 |
| 疾振区 | <code>RapidRegion</code> | 是 | 高速交替敲击区域 |
| 段落 | <code>SectionMarker</code> | 否 | 供工具、教学和定位使用 |

Schema 1 的“共同游标曲线＋固定素音靶”不能可靠判断应属于哪一口钟，因此 <code>ChartMigrator</code> 明确拒绝自动迁移。旧谱必须手工改写。

### 4.3 编译与校验

<code>ChartCompiler</code> 把 Resource 编译成 <code>CompiledChart</code>：

1. 深复制原谱；
2. 检查 schema 与字段关系；
3. 建立 <code>TempoMap</code>；
4. 把 tick 换成整数微秒；
5. 稳定排序；
6. 计算理论判定单位和玩法哈希。

理论判定数为：

~~~text
普通音符数
+ 去重后的调频 unit_id 数
+ 疾振区数
~~~

同一个 <code>group_id</code> 下的一生一死两条调频滑条只算一个单位；素音凝现不另加 Combo。

<code>ChartValidator</code> 会检查 ID、范围、事件重叠、滑条所属调频场、同组两侧的时间一致性、素音是否指向完整双侧组，以及持续占键机制是否互相争夺输入。

### 4.4 默认 GameplayRuleSet

| 类别 | 当前默认值 |
| --- | --- |
| Tap / Hold 头 | Perfect ±45 ms，Good ±90 ms，Pass ±135 ms，自动 Miss 180 ms |
| Hold 断持 | 100 ms 内可重按；尾部不判松键 |
| 双押容差字段 | 75 ms；当前普通双押仍是同 tick 两枚独立音符 |
| 调频端点 | 每程从起点到原定尾拍（含尾拍）进入末端 3% 即成功；尾拍结算 Perfect / Miss |
| 频率 | 最低 1 Hz，基准 3 Hz，最高 7 Hz |
| 调频尺度 | 等效弦长 160 px/Hz；计分圆弧 28°～100°；自由调频一圈 32 Hz |
| 疾振 | 1.00 / 0.85 / 0.65 完成率对应 Perfect / Good / Pass |
| 分数 | 1000 / 700 / 400 / 0；101 Combo 达 2 倍上限 |
| 魂火 | 100；Miss 扣 20；乱按默认不断 Combo、也不扣血 |
| 表现时间 | 音符提前 2.25 秒；预备 2 秒；失败收尾 0.7 秒 |
| 波 | 1920×1080 逻辑画布；2400 px/s |

<code>hold_release_*</code>、旧调频端点 150/300/500 ms 时间窗与覆盖率阈值还留在 Resource 中，只为旧资源字段兼容；当前 Hold 尾判与调频评分不读取它们。

## 5. 时间、输入与 Replay

### 5.1 TempoMap

<code>src/domain/timing/tempo_map.gd</code> 是 tick 与微秒之间唯一的正式换算入口。它支持 BPM 变化，并把结果落成整数微秒；tick_to_us 逐段积分，us_to_tick 二分反算。

常用接口：

| 接口 | 用途 |
| --- | --- |
| <code>tick_to_us()</code> | tick 转微秒 |
| <code>tick_span_to_us()</code> | 两个 tick 之间的真实时长 |
| <code>us_to_tick()</code> | 微秒反算浮点 tick |
| <code>us_to_tick_rounded()</code> | 微秒反算最近整数 tick |
| <code>bpm_at_tick()</code> | 查询当前位置 BPM |

不要用 <code>delta</code> 累积判定时间。每帧只负责问“现在的绝对时间是多少”，这样一帧跨过多个事件也不会漏掉。

### 5.2 SongClock 的时间域

<code>SongClock</code> 每帧产生一个 <code>ClockSample</code>：

- song time：歌曲播放位置；
- judge time：song time 减去输入补偿；
- visual time：song time 加视觉提前量；
- capture time：接收设备事件的单调系统时间，用于反查当时的 judge time。

音频输出、输入和视觉三类偏移分开保存。把它们相加成一个“总延迟”会破坏校准含义。

### 5.3 InputRouter

<code>InputRouter</code> 把键鼠、手柄和触屏统一变成 <code>SemanticInputSample</code>。领域层只看到：

~~~text
LIFE_PRESSED / LIFE_RELEASED
DEATH_PRESSED / DEATH_RELEASED
TUNING_DISPLACED
FOCUS_CANCELLED
~~~

调频位移的 X 永远代表生钟，Y 永远代表死钟。两路分别钳制并量化为 Q15，不能把它当二维方向向量做单位化；否则两根摇杆同时满幅会从 1 被压成约 0.707。

按住状态按“来源集合”维护。同一口钟若同时由键盘和鼠标按住，松开其中一个来源不会错误释放整口钟。每帧还会用 Input Map 轻量对账，修复窗口或 UI 吞掉边沿事件后的粘键。

### 5.4 RotaryStickTracker 与有限圆弧

<code>rotary_stick_tracker.gd</code> 将摇杆角位移转成输入；自由调频和计分滑条使用不同映射。

- 半径达到 0.55 接合，低于 0.35 脱开；第一次接合只定锚。
- 小于 0.25° 的净变化先累计，正反抖动抵消；跨越 -π/π 保持连续。
- 单帧异常阈值：自由旋转 165°，有限圆弧 110°；异常时重新定锚。
- 计分滑条第一次接入须对准圆弧起点 ±15°。途中回中保留进度与已接合状态，再推出时可在任意角度重新定锚；每条新滑条重新捕获起点。

自由调频的归一化位移为：旋转弧度 × 32 Hz ÷ (2π × 6 Hz)。它只在调频场内、无活动或预告滑条占用时生效。

计分滑条由 <code>TuningArcGeometry</code> 共用视觉与输入几何，不使用每圈 Hz 参数：

~~~text
等效弦长 = 频率跨度 × 160 px/Hz
弦中点到圆心距离 d = 画布宽 × 0.21875（默认 420 px）
圆弧角度 = clamp(2 × atan(弦长 / (2d)), 28°, 100°)
默认跨度 1 / 2 / 4 Hz → 约 28° / 41.7° / 74.6°
~~~

<code>arc_rotation_deg</code> 改变起手与运动朝向，参与玩法哈希；<code>visual_offset_px</code> 只改绘制位置，不参与玩法哈希。

### 5.5 Replay v3

<code>ReplayData</code> 保存语义输入，不保存具体键码。v3 的调频输入是两侧相对位移；v1/v2 的共同游标或持续速率不能无损还原，因此加载时会被拒绝。

输入使用 <code>timestamp_us + sequence</code> 稳定排序，并记录谱面哈希、规则哈希、歌曲时序、装备和构建信息。<code>ReplayRunner</code> 可以脱离场景树运行同一套 <code>GameplaySimulation</code>。

## 6. 核心玩法怎样工作

### 6.1 Tap 与普通双押

一次正确敲击有两个不同的时刻：

~~~text
按键时：NoteJudgeEngine 确认资格和等级
稍后：  实体 Strike Wave 追上音符，画面才击碎
~~~

<code>NoteJudgeEngine</code> 在同阵营、未判定且仍处 Pass 窗内的音符中选择最近者。若按键越过 Pass 窗，不会立刻把目标判 Miss；这次按键先成为乱按，原音符到自动截止时再 Miss。

普通双押是同 tick 的朱、玄两枚音符。它们各自判定、各发一圈波。共享 <code>group_id</code> 用于合印表现，共享 <code>damage_group_id</code> 可避免同一组漏击扣两次魂火。

### 6.2 Hold

Hold 的画面按“头、身、尾”逐步出现，沿与 Tap 相同的弧线移动。头部命中后，玩家持续按住对应钟；身体从尾部向头部逐渐缩短。

运行时只判头部和持续：

- 头部按 Tap 窗口评分；
- 提前松开后有 100 ms 宽限；
- 宽限内重按可以继续，但持续分量降为 Pass；
- 超过宽限为 Miss；
- 到尾点仍按住时自动完成；
- 晚松、始终不松、旧谱的 <code>tail_requires_release = true</code> 都不会降级。

<code>tail_requires_release</code> 与三项 <code>hold_release_*</code> 字段仍能反序列化，但运行时忽略，写谱器也不再展示。

### 6.3 Strike Wave 与 Carrier Wave

工程里有两类容易混淆的声波：

| 波 | 触发方式 | 能否击破普通音符 | 归谁维护 |
| --- | --- | --- | --- |
| Strike Wave | 每次按下边沿 | 只有被普通音符接受的彩波可以 | <code>WaveInteractionEngine</code> |
| Carrier Wave | 按住一口钟后按当前频率持续发射 | 不可以；用于相纹和素音 | <code>CarrierWaveEngine</code> |

乱按仍会出现灰色 Strike Wave，但它不会绑定音符。Carrier Wave 无论有没有调频滑条都能独立存在；滑条只在谱面允许时改变之后的发射频率。

已经发出的 Carrier Wave 保存绝对发射时刻，以固定 2400 px/s 传播。之后改变频率，只改变未来发波间隔，不会让旧波突然加速、减速或重排。

### 6.4 旋钮调频

调频由三层数据分工：

~~~text
TuningFieldRegion：这段时间允许改频
TuningSliderEvent：某一侧要从哪个频率走到哪个频率、每程多久、走几程
SuManifestationEvent：何时把真实相纹交点凝成素音
~~~

滑条不要求重新敲头，也不判尾部松键。可以在开始前先按住相应肩键，进入段落后直接旋转。

当前手感是直接控制：

- 实际旋转多少，频率和填充立即变化多少；
- 点状虚线只提示节奏，不会吞掉输入；
- 每一程被限制在自身起点与终点之间；
- 正向到端点后继续旋转不会溢出；
- 反向旋转会立即回退；
- 往返滑条在谱面规定的强拍翻转要求方向。

每程从起始时刻到原定尾拍（含尾拍），只要玩家进入目的端最后 3%，就登记成功；原定尾拍统一结算 Perfect，否则 Miss。没有 Good / Pass 端点时间窗，也不采样沿途覆盖率。

提前完成可等待尾拍，无须退出后再次卡拍进入；退出端点或松手不会撤销已经登记的成功。超过尾拍不能补救。往返按谱面原定时间换程，不因提前完成而提早换程；每程单独登记结果，最后取最差等级。端点磁吸只影响显示，不修改真实频率。

同一 <code>group_id</code> 的生、死滑条分别记录，最后合并成一次 Judgment 和一次 Combo，组成绩取两侧、各程中的最差值。预告滑条仅展示，开始前不能操作或预填；每条开始时重置本侧到谱面起点。

### 6.5 相纹与素音

<code>CarrierWaveEngine</code> 保存两口钟的真实波前历史。<code>TuningInterferenceVisual</code> 把权威波前交给 <code>interference_ink.gdshader</code>：

- 单侧区域显示本钟颜色；
- 两侧真实波带叠加处有连续骨白底；
- 网点只提供纹理层次，不再决定“这里有没有相纹”；
- 设置项“相纹强度”只改透明度、辉光和对比，不删除波圈，也不改玩法频率。

素音不是预摆的第三轨音符。到 <code>SuManifestationEvent.tick</code> 时，领域层对生、死圆波逐对求交点，再按允许区域、HUD 避让、距离与稳定 ID 排序。若没有合法加强交点，只显示凝现失败，不把素音硬塞到不存在的白纹上。

### 6.6 双钟疾振

疾振代码仍保留。区域激活后，它取得最高输入优先级，按防抖、交替和目标次数判断有效敲击；有效波包交织成白色加强纹和相消暗带。

当前 s01～s05 都不放疾振，原因是这一轮测试集中在 Tap、Hold、载波和旋钮调频。实现仍位于：

- <code>src/domain/rapid/rapid_engine.gd</code>
- <code>src/presentation/vfx/rapid_interference_visual.gd</code>
- <code>shaders/fields/rapid_wave_interference.gdshader</code>

### 6.7 分数、魂火与结算

| 模块 | 当前规则 |
| --- | --- |
| <code>ScoreEngine</code> | 非 Miss 增加 Combo；Pass 保 FC、破 AP |
| <code>HealthEngine</code> | 同一伤害组整局只扣一次；调试关允许负魂火但不失败 |
| <code>ResultEvaluator</code> | 理论单位全部结算且未失败才 Clear；无 Miss 且无破连乱按才 FC；FC 且全 Perfect 才 AP |
| <code>ResultSummary</code> | 保存分数、最大 Combo、魂火、四档数量、FC/AP、奖励等 |

当前乱按默认既不断 Combo 也不扣魂火。随从“角魂”的加分在原始玩法结算后应用，不改变判定、Replay 或 FC/AP。

## 7. 运行时各模块

### 7.1 ChartScheduler

<code>src/runtime/scheduler/chart_scheduler.gd</code> 只负责表现调度。它按 <code>visual_time</code> 提前请求生成音符和场域，不参与“按没按准”。

普通音符有两个通知阶段：

1. <code>visual_timing_confirmed</code>：按键时机已经确认，圆环和锁定反馈可以响应；
2. <code>visual_wave_contacted</code> 或 <code>visual_note_arrived</code>：波真正接触，或漏击音符到达角色。

### 7.2 GameplaySimulation 与 Coordinator

<code>GameplaySimulation</code> 持有七个领域引擎：

~~~text
NoteJudgeEngine
TuningEngine
RapidEngine
WaveInteractionEngine
CarrierWaveEngine
ScoreEngine
HealthEngine
~~~

当前输入所有权为：

~~~text
疾振 > 调频位移 > 普通 Tap / Hold
~~~

调频滑条不接管普通按下边沿；按下仍可启动 Hold/Tap 或成为乱按，同时也控制 Carrier Wave 的开始与停止。只有 <code>TUNING_DISPLACED</code> 交给 <code>TuningEngine</code>。

<code>GameplayCoordinator</code> 是 Node 包装，把领域输出转成 Godot 信号。它不重新计算成绩。

### 7.3 StageSession

<code>src/runtime/session/stage_session.gd</code> 是一局的状态机：

~~~text
LOADING → READY → PREROLL → PLAYING
                         ↘ PAUSED ↗
PLAYING → FINISHING → RESULT
PLAYING → FAILING   → RESULT
~~~

它负责准备依赖、编译谱面、选择正式 BGM 或 Graybox 节拍音、配置时钟、推进一局、暂停恢复、重试、Seek、Replay 录制和结束时间。

失败后不再继续产生新判定，但已经发出的波仍会走到离屏，不会突然消失。

### 7.4 StageShowDirector

<code>StageShowDirector</code> 使用同一 <code>TempoMap</code> 推进演出 cue。瞬时 cue 越过后不重播；跨过 Seek 点的持续 cue 会按正确进度重建。因此需要中途预览仍可恢复的演出，最好写成持续 cue，或让具体表现器支持绝对时间重建。

## 8. 表现层与美术接入

### 8.1 当前构图

<code>graybox_stage_presentation.tscn</code> 的主要槽位为：

~~~text
生界与生角色：左上
死界与死角色：右下，整体旋转 180°
共同落点：画面正中心
生音符：右偏上画外 → 弧形旋入中心
死音符：左偏下画外 → 弧形旋入中心
生调频滑条：右上（跟随右手控制区）
死调频滑条：左下（跟随左手控制区）
~~~

两个世界中心对称，但两侧行为独立，不要求同一时刻做镜像动作。

### 8.2 NoteVisualHost

<code>src/presentation/adapters/note_visual_host.gd</code> 统一生成、更新和回收 Tap、Hold、时机环、调频滑条和疾振场。

普通音符的位置来自绝对 <code>time_to_hit</code>：

- 落点前沿 <code>NoteApproachPath</code> 的等弧长贝塞尔路径移动；
- 越过中心仍未解决时，继续直线走向对应角色；
- 接到波接触或抵达事件才播放最终状态。

同侧可同时展示多条调频预告。按 group_id（无组时用 event_id）组织，依次按当前 / 未来 / 收尾阶段、起点时间与 ID 排序编号；当前透明度 1，首条未来 0.7，其余未来 0.45，收尾 0.24。同一 event_id 防止重复生成；Seek、重试、换关和重绑会清空视觉及 ID 记录。

### 8.3 Tap、时机环与 Hold

<code>graybox_note_visual.gd</code> 负责默认 Tap 外形和确认、接触、抵达、Miss 状态。

<code>timing_ring_visual.gd</code> 的圆环告诉玩家：在环闭合时按下，发出的波会在正确时刻追上音符。Hold 头命中后，环改为持续进度提示；不再绘制尾部松键提示。

<code>graybox_hold_visual.gd</code> 让 Hold 先出头、再长身体、最后出现尾部；按住后从尾部缩短。扭动由稳定 ID 和绝对进度计算，同一 Replay 不会随机变形。

### 8.4 调频滑条

<code>graybox_field_visual.gd</code> 的调频模式只画：

- 104 px 左右的宽轨道与骨白描边；
- 从起点到玩家当前位置的填充；
- 随歌曲时间蔓延、折返的点状引导；
- 当前要求的顺时针或逆时针箭头；
- 开始前的收束进度环。

滑条使用 TuningArcGeometry 有限圆弧。“频率跨度 × 160 px/Hz”是等效弦长，不是最终弧长；角度限制为 28°～100°。支持圆弧旋转与独立视觉偏移，时间只决定点状引导的推进速度。

### 8.5 波与相纹

| 文件 | 职责 |
| --- | --- |
| <code>wave_field_visual.gd</code> | 画 Strike Wave、碰撞环和普通双波交点 |
| <code>tuning_interference_visual.gd</code> | 消费 Carrier Wave 历史、推送 Shader、呈现素音 |
| <code>interference_ink.gdshader</code> | 逐像素计算生死波带与连续骨白叠加区 |
| <code>rapid_interference_visual.gd</code> | 消费疾振有效波包 |
| <code>rapid_wave_interference.gdshader</code> | 画疾振相长与相消纹 |

调频 Shader 每侧最多接收 16 个详细波前。CPU 领域层可保存更多历史；表现容量与玩法真值不是同一件事。

### 8.6 StageVisualTheme

当前已接入生死世界、边界、角色、朱/玄/素音符、Hold、调频、疾振、时机环与色板。钟、UI 与随从等部分主题字段尚未完整接入主流程。正式美术应通过 <code>StageVisualTheme</code> 换场景，不要在 Scheduler 或判定器里画素材。

世界和角色进入预留 Slot。只给生界场景时，死界可复用并由 Slot 做 180° 中心对称。玩法坐标还保存在 <code>GameplayRuleSet</code>；若美术改变波源或落点，必须同步更新规则坐标。

## 9. 应用层与常驻服务

| 模块 | 关键文件 | 说明 |
| --- | --- | --- |
| 页面总控 | <code>src/app/app_main.gd</code> | 挂载页面、弹窗和 StageRoot，接结算并应用随从 |
| 标题页 | <code>title_screen.gd</code> | 开始、设置、校准、退出 |
| 选关页 | <code>stage_select_screen.gd</code> | Catalog、解锁、成绩和手柄焦点 |
| 加载页 | <code>stage_loading_screen.gd</code> | 异步解析六项关卡依赖 |
| 结算页 | <code>result_screen.gd</code> | Clear/Fail、FC/AP、分数和重试 |
| 设置 | <code>settings_modal.gd</code> | 三类音量、震动、闪光、相纹强度、全屏、调试 HUD |
| 校准 | <code>calibration_modal.gd</code> | 手动设置音频输出、输入补偿、视觉提前各自 ±300 ms；无自动采样 |
| 随从 | <code>pet_select_modal.gd</code> | 单槽装备、基础与进阶状态 |

设置中的“相纹强度”默认 0.85，范围 0.35～1.00。旧版“显示密度”字段不会被当成新强度继承，因为两者语义不同。

玩家存档在 <code>user://player_save.json</code>，设置在 <code>user://settings.cfg</code>。存档采用临时文件、回读和备份替换；遇到未来 schema 会进入写保护。

## 10. 写谱器

### 10.1 入口与组成

<code>addons/minghe_chart_editor/plugin.gd</code> 是薄 EditorPlugin 宿主，真正工具在 <code>src/tools/chart_editor</code>，入口为顶部主屏页签。插件保存项目时只写恢复稿，正式保存使用写谱器内的保存操作。

~~~text
ChartEditorWorkspace   工具页面与操作编排
EditorDocument         Chart / Show 工作副本，其余依赖只读、轨道、ID、Dirty
EditorHistory          最多 200 步 Undo / Redo 快照
EditorTempoMap         编辑期 tick/秒换算
TimelineView           波形、节拍网格和事件交互
PropertyPanel          类型化属性编辑
PreviewBridge          用正式 StageRoot 预览
EditorSaveService      保存、备份和崩溃恢复
ValidationAdapter      把问题映射到可点击事件
~~~

### 10.2 当前调色板与轨道

调色板包含：朱 Tap、玄 Tap、普通双押、朱 Hold、玄 Hold、调频场、朱调频滑条、玄调频滑条、成组双侧滑条、素音凝现、疾振、StageShow cue。

时间线可见行是：Timing/波形、朱音、玄音、调频场、朱滑条、玄滑条、素音、疾振、演出。<code>SectionMarker</code> 有数据合同，但尚无独立编辑行。

创建调频内容时：

1. 先放 <code>TuningFieldRegion</code>；
2. 再分别放朱或玄 <code>TuningSliderEvent</code>；
3. 双侧需要合并评分时，给两条滑条相同 <code>group_id</code>；
4. 需要素音时，放 <code>SuManifestationEvent</code> 并关联已结束的完整双侧组。

属性面板可直接编辑 <code>field_id</code>、<code>group_id</code>、阵营、起点 tick、单程 tick、程数、0～1 起终值、圆弧朝向 arc_rotation_deg 与视觉偏移 visual_offset_px。旧曲线点、固定素音目标与 Hold 尾松键选项已经移除。

### 10.3 预览与保存

正式预览会深复制当前工作副本，实例化真正的 <code>StageRoot</code>。从中途开始时，会删除已经起手的事件，包括 Tap、Hold、调频场及其滑条、素音、疾振和旧 cue；它不会伪造机制中段状态。

保存已有谱时，chart 与 show 作为一组事务写入，并通过 journal 恢复中断。首次保存新关卡时，先写五项依赖，最后写 <code>stage_definition.tres</code> 作为完整包的提交标志。

恢复位置：

~~~text
user://minghe_chart_editor/save_journal.json
user://minghe_chart_editor/backups/
user://minghe_chart_editor/recovery/
~~~

WAV 波形解析支持 PCM16、1～8 声道及附加 chunk 扫描，后台建立多级 min/max 波形与缓存；其他编码需先转换。试听通过 pitch_scale 变速，也会变调。尚无完整歌曲元数据、变拍网格、SongAuthoringProfile 或输入录制制谱。

## 11. ArtLab 与美术合同

<code>src/tools/art_lab</code> 会实例化 Manifest 指向的真实运行场景，而不是只看一张 PNG。它可切状态、判定、画幅、背景压力和质量，并画出 visual bounds、Pivot 与必需 Marker。

当前 Manifest 的常用锚点：

| Marker | 用途 |
| --- | --- |
| <code>wave_origin</code> | 声波源 |
| <code>mallet_tip</code> | 槌端 |
| <code>body_center</code> | 身体中心 |
| <code>hit_fx_anchor</code> | 受击特效 |
| <code>follower_anchor</code> | 随从挂点 |
| <code>hit_anchor</code> | 音符命中位置 |
| <code>progress_anchor</code> | 进度提示 |
| <code>attach_anchor</code> | 通用挂接点 |

<code>content/visual/graybox_manifest.tres</code> 目前仍是占位清单。ArtLab 的旧背景也仍可能与正式关卡构图不同；验收资产尺寸和锚点可以用它，判断整关构图应回到实际 <code>StageRoot</code>。

## 12. 测试入口

<code>tests/run_all.gd</code> 当前枚举 11 个独立 headless 套件：

1. domain 核心与调频端点；
2. Strike Wave；
3. Carrier Wave 与动态素音；
4. 内容包；
5. 美术合同；
6. 存档；
7. 输入与 Replay v3；
8. Stage runtime；
9. App flow；
10. 全部关卡入口冒烟；
11. 写谱器。

总入口会为每套测试启动独立 Godot 子进程，避免 autoload、暂停状态和 Resource 缓存互相污染。视觉截图脚本 <code>tests/visual/capture_screens.gd</code> 不属于自动像素回归，只负责取样。

运行命令：

~~~powershell
# 将占位路径替换为本机 Godot 4.7 控制台程序
$godotExe = 'C:\路径\Godot_4.7_console.exe'
& $godotExe --headless --path "E:\大学\MEMO\编钟音游\Game" --script res://tests/run_all.gd
~~~

这份工作区经常处于机制调整中的未提交状态，所以本文不冻结“当前通过了多少条”这个易过期数字。查看最近一次命令输出，比文档中的历史统计可靠。

## 13. 常见修改从哪里进入

| 想改什么 | 先看 | 通常还要同步 |
| --- | --- | --- |
| Tap/Hold 判定窗 | <code>default_gameplay_rules.tres</code> | <code>note_judge_engine.gd</code>、领域边界测试 |
| Hold 持续规则 | <code>note_judge_engine.gd</code> | Hold 视觉、Replay、领域测试 |
| 键位与左右关系 | <code>project.godot</code> | <code>input_router.gd</code>、UI 提示、输入测试 |
| 旋钮接合与抖动 | <code>rotary_stick_tracker.gd</code> | Replay v3 输入测试 |
| 自由调频每圈 Hz | <code>GameplayRuleSet.tuning_hz_per_revolution</code> | 仅影响无滑条占用时的自由调频 |
| 计分滑条动作幅度 | <code>TuningArcGeometry</code>、谱面频率跨度 | 等效弦长、角度上下限与输入映射 |
| 调频评分 | <code>tuning_engine.gd</code> | 末端捕获比例、每程期限、Replay、调频测试 |
| 调频滑条外观 | <code>graybox_field_visual.gd</code> | <code>NoteVisualHost</code> 的多条预告排序与透明度 |
| 载波发射 | <code>carrier_wave_engine.gd</code> | <code>gameplay_simulation.gd</code>、相纹 VFX |
| 相纹明暗与纹理 | <code>interference_ink.gdshader</code> | <code>tuning_interference_visual.gd</code>、设置项 |
| 普通波接触 | <code>wave_interaction_engine.gd</code> | 路径、波视觉、关卡结束时间 |
| 音符路径和落点 | <code>GameplayRuleSet</code> | <code>NoteApproachPath</code>、主题锚点、视觉测试 |
| 换正式音符或角色 | <code>StageVisualTheme</code> | PackedScene 方法合同、ArtLab Manifest |
| 新增关卡 | 新建 <code>content/stages/sXX</code> 六文件包 | Catalog、选关、Replay 与完整流程 |
| 写谱器轨道 | <code>editor_document.gd</code>、<code>timeline_view.gd</code> | 属性面板、保存、预览、工具测试 |

涉及声波或音符路径时，不能只改画面。至少核对四处：规则坐标、领域计算、表现采样、Replay 与边界测试。

## 14. 当前边界

以下是当前代码现状，不是未来承诺：

1. 五关都是 Graybox 测试关，没有正式 BGM，也不会死亡。
2. 疾振实现保留，但五张当前测试谱均未使用。
3. PC 鼠标只能提供一条水平相对位移；双键时两口钟暂时同量变化。真正独立双路输入依赖手柄双摇杆或移动端双指。
4. 调频不再采样覆盖率；旧端点三级时间窗仅为资源兼容保留，当前按每程期限结算 Perfect / Miss。
5. <code>chord_tolerance_ms</code> 仍未把普通双押合成原子判定；双押是同 tick 两枚音符。
6. 实体 Strike Wave 决定击破动画何时发生，但按键资格和等级仍在按下时确定。
7. <code>wave_front_half_width_px</code> 主要服务表现；普通波接触公式把波前视作理想薄环。
8. 写谱器小节粗线仍按 4/4 绘制，<code>MeterEvent</code> 尚未完整进入网格。
9. 写谱器从机制中段预览会裁掉已开始事件，不重建中间状态。
10. <code>StageVisualTheme.ui_theme</code>、菜单试听、部分 Actor/Audio cue 与若干预留槽尚未进入主流程。
11. 正式美术、随从图标与场景、字体、图标和授权清单仍待补齐。
12. 静态检查发现 <code>ChartEditorWorkspace.open_stage_path()</code> 在解析路径依赖之前检查 chart / stage_show，可能拒绝当前五关；文档模型的打开测试没有覆盖此 UI 入口。
13. 工作区 <code>_open_runtime_preview()</code> 换算起点时未减首拍偏移；当前 2 秒偏移相当于 4 拍，预览会偏后。以上两项本次仅记录，尚未运行界面复现或修复。

## 15. 推荐阅读顺序

第一次读代码，不建议从最长的 <code>StageSession</code> 开始。按下面顺序更容易建立正确心智模型：

1. <code>project.godot</code>：入口、autoload、Input Map；
2. <code>content/stages/s02</code> 与 <code>s04</code>：分别看普通音符谱和调频谱；
3. <code>src/content/resources</code>：理解 Resource 合同；
4. <code>tempo_map.gd</code> 与 <code>semantic_input_sample.gd</code>：时间和输入语言；
5. <code>note_judge_engine.gd</code>、<code>tuning_engine.gd</code>、<code>carrier_wave_engine.gd</code>；
6. <code>gameplay_simulation.gd</code>：看各引擎怎样合流；
7. <code>song_clock.gd</code>、<code>input_router.gd</code>、<code>stage_session.gd</code>；
8. <code>note_visual_host.gd</code>、<code>graybox_field_visual.gd</code> 与两套波 VFX；
9. <code>stage_root.gd</code> 和 <code>app_main.gd</code>；
10. 最后再读写谱器、ArtLab 和测试。

读任何脚本时都先问三件事：它使用哪条时间轴；它在决定玩法真值还是只画反馈；重试、Seek、暂停或 Replay 后，它如何从绝对状态恢复。工程里大多数边界都能用这三个问题判断。
