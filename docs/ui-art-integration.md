# 主界面、暂停、设置与随从 UI

当前工作位置为主 `Game` 工程的 `ui` 分支，正式选关已接到应用入口。


## 正式主界面与启动过渡

正式 F5 入口沿用 `scenes/app/app_main.tscn`，主界面为 `scenes/screens/title_screen.tscn`。美术源目录 `Assets/UI/主界面` 的 9 份素材复制到工程 `assets/ui/art/主界面`；两张效果图作为对照，其余贴图用于画面。背景使用 AtlasTexture 的 `(45,0,2560,1440)` 区域，保留源图，通过 Design 画布适配为 1920×1080。四个按钮按原稿排列：开始游戏、著作信息、操作设置、退出游戏。

每次进程首次启动显示“点击任意处开始”字图，按 3 秒周期在 80%～100% 透明度间轻微呼吸。鼠标点击、键盘新按键、手柄按钮均可唤醒；鼠标移动、滚轮、摇杆漂移和重复键不触发。唤醒输入会消费到该键释放，不会穿透到新展开的开始按钮。过渡时序如下：

| 元素 | 延迟 | 时长 | 位移 |
| --- | --- | --- | --- |
| 提示淡出 | 0 | 0.16 秒 | 无 |
| 标题淡入 | 0.12 秒 | 0.40 秒 | 向上归位 8 px |
| 按钮依次淡入 | 0.28 秒起，每项间隔 0.06 秒 | 各 0.24 秒 | 向上归位 10 px |
| 默认下划线 | 菜单完成展开 | 0.16 秒 | 从中心舒展 |

页面脚本使用等待、展开、菜单、离开四阶段。AppMain 仅在内存中记录 `menu_revealed`；回到主界面跳过提示，默认选中开始游戏。设置沿用正式弹窗和校准分类，关闭后恢复操作设置的焦点。著作信息本轮保留按钮反馈及意图信号，尚未制作内容页。退出和开始先淡出 0.14 秒，再向宿主发送意图；重复确认不会重复切页。

主菜单按钮的 MenuInteraction 开启 `focus_only`，鼠标实际移动到按钮时同步焦点。鼠标事件按按钮的画布变换换算坐标，适配不同渲染分辨率；键盘、手柄接管后静止鼠标不再保留第二条下划线。其他页面继续沿用原先的悬停反馈。字图保留美术字体，辅助访问名称使用对应按钮原文。

标题后方使用 `title_glow.gdshader` 的局部字形柔光，独立字图保留灰白色和笔触。ShaderMaterial 随实例独立，默认半径 12 px、留边 20 px、淡骨白；越界采样透明，避免边缘笔触被拉伸。场景 Inspector 提供 4.8 秒周期、2 px 上下偏移及 0.18～0.26 光强。入场结束后才推进静息时间；页面释放时所属 Tween 一起释放。背景保持静态，以上参数仅属于菜单表现。

本轮主界面 49 项检查通过，原有弹窗、随从、暂停等 UI 回归 111 项通过，Compatibility 图形日志无脚本或 shader 错误。

验证入口：`tools/ui/run_ui_review.ps1 -Suites title`。测试通过正式 AppMain 检查输入、选关往返、弹窗隔离、退出防重复，并在独立画布实际读回 720p、1080p、2K、4K、1800×1200 图像。截图位于 `builds/title-review`。`-Suites title-video` 使用同一正式入口以固定 60 FPS 记录 7 秒 AVI；前 1 秒等待，随后展开菜单并展示一个完整标题呼吸周期。视频采用隔离用户目录，不保存玩家设置。交付预览为 `builds/title-review/title-transition.mp4`，1280×720、60 FPS、约 7 秒。录制按固定步长采样，编码耗时不作为正常游玩的帧耗时。

## 页面入口

| 页面 | Godot 场景 | 数据与动作 |
| --- | --- | --- |
| 暂停 | `scenes/ui/hud/pause_overlay.tscn` | StageSession 的暂停、恢复倒计时、重试、退出；外部试玩附加操作保留 |
| 设置 | `scenes/ui/modals/settings_modal.tscn` | 声音、画面、校准三个分类，保存统一提交，取消丢弃草稿 |
| 随从 | `scenes/ui/modals/pet_select_modal.tscn` | 当前装备定位、左右浏览、静息循环、点击技能预览、装备与卸下 |

根节点的 `Design` 使用 1920×1080 设计坐标，屏幕变化由 `art_screen.gd` 等比缩放并居中。子部件位置均保存到场景，可直接在 Godot 中调整。弹窗隔离底层输入，关闭时 AppMain 恢复原焦点；随从左右方向键用于切换，确认预览区播放一次技能。预览区不显示选中下划线或悬浮提示；其他按钮保持交互细光。

暂停按钮从左到右为“重玩／继续／退出”，默认焦点仍为继续。继续时面板、火框、按钮与遮罩在 0.14 秒内淡出，独立睁眼显示会话剩余倒计时；最后 0.14 秒眼睛与数字淡出，不延长恢复时刻。重玩先收起面板，再按会话现有 `resume_countdown_sec` 显示眼内倒计时，结束后才重置关卡，过渡期间原会话保持暂停。恢复默认完整等待 3 秒，数字使用 Huiwen 字体，按“3 → 2 → 1”各显示一秒，满三秒才恢复玩法。重复确认不重新计时。外部试玩沿用相同退场，并保留动态退出文字及附加操作。

设置分类栏位于设计坐标 x=410，比首版右移 35 px，分类字号为 32 px。

设置的 `initial_tab` 可为 `sound`、`display` 或 `calibration`。原校准路由打开相同设置页的校准分类。校准内容场景在 `scenes/ui/components/calibration_content.tscn`，复用原测量器，仅向设置宿主提供 `draft_values()`；离开分类调用 `deactivate()` 停止参考音并恢复输入递送方式。数值框只提交正在编辑的文本，隐藏分类不以旧文本覆盖草稿值。

## 美术和字体

- 来源：项目根目录 `Assets/UI`，原图未修改。副本位于 `assets/ui/art`；选关背景、飘带、箭头复用队友已有的 `assets/image/ui/选关`。
- 暂停底图、睁眼、按钮、设置底图和分类按钮原扩展名虽为 JPG，文件实际为 RGBA PNG；工程副本纠正为 `.png`，没有重新抠图或改色。
- 粉焰边框使用 8 帧透明素材，`fire_frame.gd` 的 `frames_per_second` 默认 12；按菜单时间循环，游戏暂停时继续播放，隐藏时停止更新。
- 共同 Theme 为 `content/ui/game_theme.tres`：灰紫暗轨、赭红填充、骨白文字及滑块。开关的两个 SVG 是可替换的基础控件图形。
- `assets/fonts/huiwen.otf` 来自 `Assets/中文 - Huiwen.otf`，字体随工程保存，无需玩家安装。正式游戏文本由 GameFont 与 Theme 接入，程序绘制的 HUD 通过 `MingheUiStyle.ui_font()` 读取；工具模式保留原字体。
- 界面淡入 0.18 秒、淡出 0.14 秒，使用平滑曲线；关闭完成前继续隔离底层输入，随后恢复原焦点。按钮按下缩至 98%；不移动页面布局。现成书法贴图不替换成动态字体。
- 未使用的效果图和选关素材副本保留，页面不加载这些副本；清理副本的删除操作被自动审批阻止，原始美术文件不受影响。

## 交互动效与随从投影

- `menu_interaction.gd` 由焦点、鼠标和控件信号驱动：骨白细线在 0.16 秒内从中心舒展，外侧贴一层暖色软边；确认后短亮约 0.28 秒。按钮按下缩到 98%，释放平滑复原。颜色反馈与弹窗整体淡出使用独立属性，避免相互抢写透明度。
- 滑块只在当前滑块附近显示柔光，修改数值时短亮；分辨率下拉框、开关及校准输入框沿用骨白细光。反馈节点不接收鼠标或焦点，每个控件复用一个绘制组件，静息时没有逐帧更新。
- 左右箭头的美术子节点向外轻移 4 px；设置分类内容用 0.18 秒淡入衔接。随从切换按方向移入 18 px，并在 0.22 秒内归位、淡入；快速切换终止前一个 Tween。
- 随从脚下使用一个局部 ShaderMaterial 绘制扁椭圆光影：中心较暗，外围连续衰减。无灯光、视口、屏幕模糊或常驻闪烁。技能被播放器接受时影子舒展一次，重复点击不重新启动。
- 颜色来自原画部件主色采样：女土蝠胭脂红 `#C83050`，鬼金羊暖陶粉 `#D09080`，翼火蛇朱红 `#C81800`。菜单展示资源 `content/ui/*_preview.tres` 提供 `shadow_color`、`shadow_size`、`shadow_position`、`shadow_strength`，不影响局内随从。默认中心设计坐标 (960,641)，强度 0.85，各角色宽高分别为 480×108、420×96、420×98。

## 随从动画与分支衔接

2026-09-14 集中合并后，以下初期快照已被 editor 的最新完整随从实现替换；菜单与正式游戏现在共用播放器，移除旧的双参数 `set_state` 兼容调用。投影只在 `trigger()` 返回接受时响应。详见[分支同步审查](branch-sync-2026-09-14.md)。

### 初期接入记录

动画来源是同日原 `Game` 工作区的一份表现快照，包含 `assets/pets/animation_studies`、三个随从场景、`src/presentation/pets` 及对应角色 shader。没有复制领域逻辑、技能参数或覆盖原工作区。

`content/ui/*_preview.tres` 分别指定名称贴图、动画场景和菜单缩放。蝙蝠 4.8、羊 4.6、蛇 4.2；位置偏移默认零。这些数值不影响局内随从尺寸。

预览在 PetDefinition 的局部副本上选择快照场景，通过 `visual_scene()`、`bind()`、`set_state()`、`trigger()` 调用现有播放器；只消费 UI 时间，不发领域技能事件。每次切换只保留一个演员实例。连续点击由播放器拒绝重复起播，播放结束自行回到静息。状态只显示“未获得”或“已获得”。技能按各自解锁层级显示：基础／进阶标题保留左侧位置，未解锁时右侧内容区居中显示“？？？”，与“未获得”状态共用 x=1030 的竖向中心线，解锁后左对齐读取资源原文。未获得也可以预览动画，装备仍由 SaveService 管理。

为兼容 UI 分支原来的关卡宿主，PetVisual 暂时保留 `set_state(song_time, trigger_us)` 调用；新增预览使用单参数和显式触发接口。整合动画分支时应以其最新正式播放器为准，保留 UI 展示配置，不能用本快照覆盖队友后续动画修改。

分辨率服务取自 `editor` 已提交实现，仅同步该服务。实际像素与设计坐标分别处理：验证实际渲染尺寸要读取 ViewportTexture 的图像，不能用仍表示逻辑尺寸的 `get_size()` 判定。

## 选关分数与立绘

当前美术选关场景为 `scenes/ui/modals/level_choosing.tscn`，队友的新框图保持原样。卡片通过已配置的 `stage_id` 读取 SaveService 最高分；无记录显示 `000000`，短分数补足六位，超过六位不截断。正式 `stage_select_screen.tscn` 继承这份场景，标题页、结算返回和暂停退出均进入同一美术轮播。

分数字体为 Huiwen、60 px；相对卡片数学中心左移 8 个设计像素进行视觉校正，`content/ui/score_gradient.tres` 使用横向渐变覆盖整段文字。左端精确采用参考的 RGB 144/129/118（`#908176`），中间骨白 `#D3D4CA` 与右端暖灰 `#AB9E8B` 取自截图，渐变中间的亮部停靠约 65.5%。额外取样点重现参考图 13% 中点形成的较快左侧提亮。`score_gradient.gdshader` 以整段文字的局部横坐标采样，保留原字形透明边缘，不让每个数字重复渐变。卡片各自保存文字范围，字体大小或文字长度改变时更新；侧卡只保留背面，分数随选择权重淡出。

`LevelCardEntry.monster_scale` 单独调节立绘大小；蝙蝠采用 2.00，其余仍为 1.0。卡片与父级不裁切，翅膀可以自然越过边缘。背景、分数和卡位尺寸保持原配置。原本混入分数的卡片序号与用于占位的评级标题已移除。

描述采用 Huiwen 的 FontVariation 轻斜体（倾斜量 0.2），额外行距由 7 px 减至 3.5 px。三张卡片统一用原稿括号“〔…〕”包住整段，按语义分为两行，段落居中；括号只出现在首行开头和末行结尾。移除手工空格缩进，显式换行使用资源内的 `\n`，避免 CRLF 产生额外空行；保留原文。蝙蝠使用“你坚信生命依然在棺椁中流动。”；羊头使用“成礼兮会鼓，传芭兮代舞，姱女倡兮容与。”

## 验证与截图

运行 `tools/ui/run_ui_review.ps1`；可用 `-Suites art` 只复测 UI 交互与截图。脚本仅在当前 worktree 临时设置 `override.cfg`，使用 `WaveNoMore-UIReview` 用户目录，结束恢复原配置。暂停会话检查使用独立的默认规则快照，不依赖正在编辑中的策划工作簿。首次导入包含 Spine 时需让 Godot 完成扩展初始化及资源导入；原工作区的 `.godot` 缓存不共用。

| 检查 | 结果 |
| --- | --- |
| 新 UI、草稿、取消、保存、动画复用、真实会话暂停/继续/重试/退出 | 111 项通过 |
| 正式轮播、手柄导航、教程加载、弹窗隔离及返回焦点 | 55 项通过 |
| 校准统计、未回车输入、建议应用、正式关卡接线 | 上轮 142 项通过，本轮未改测量算法 |
| 窗口/全屏五档实际渲染像素及正式 UI 字体 | 上轮 31 项通过 |
| 工具字体隔离 | 上轮 1 项通过 |
| 选关轮播、最高分、立绘缩放、渐变实例与布局 | 398 项通过 |

图形验证使用 Godot 4.7.2、Compatibility、RTX 4060 Laptop。五档窗口与全屏读回尺寸均等于选定尺寸；另检查 1800×1200 的等比留边。UI 动画预览更新的 120 次 CPU 采样：本轮平均约 0.19 ms、P95 约 0.23 ms、最大约 0.31 ms；这是动画更新成本，不代表整帧 GPU 或整局性能。

旧输入接口迁移已补齐：应用流程、输入 / Replay、关卡运行时、声波交互和截图工具使用 A/B 输入与物理事件缓冲，不再引用已删除的 `InputRouter` 类和四个旧按键枚举。关卡测试也同步了设计画布坐标、稳定 HUD 层路径、头判反馈及素音准备流程。`tools/testing/check_scripts.gd` 在 Autoload 注册后加载 `src/tests/tools/addons` 下全部脚本，覆盖编辑器会扫描而 UI 测试未必执行的文件。校准测试原有两次后台任务节点泄漏已在测试清理中修正，142 项断言通过且退出无资源泄漏警告。

选关截图位于 `builds/level-carousel/score-default.png` 和 `score-record.png`，分别为零分和隔离测试记录 165467。其他截图输出在 `builds/ui-review`：

- [暂停](../builds/ui-review/pause.png)、[独立眼内倒计时](../builds/ui-review/pause-countdown.png)、[真实会话重玩倒计时](../builds/ui-review/pause-retry-countdown.png)
- [按钮轻压](../builds/ui-review/interaction-button-down.png)、[滑块柔光](../builds/ui-review/interaction-slider.png)
- [声音](../builds/ui-review/settings-sound.png)、[画面](../builds/ui-review/settings-display.png)、[校准](../builds/ui-review/settings-calibration.png)
- [女土蝠静息](../builds/ui-review/pet-nu_tu_fu-idle.png)、[技能](../builds/ui-review/pet-nu_tu_fu-trigger.png)
- [鬼金羊静息](../builds/ui-review/pet-gui_jin_yang-idle.png)、[技能](../builds/ui-review/pet-gui_jin_yang-trigger.png)
- [翼火蛇静息](../builds/ui-review/pet-yi_huo_she-idle.png)、[技能](../builds/ui-review/pet-yi_huo_she-trigger.png)

截图是工程实际渲染。暂停与设置的审看底景使用工程背景贴图，运行时实际底景来自打开页面前的场景。校准区域支持滚动，底部保存/取消始终固定。

## 正式选关与教程源谱

正式目录只显示三张卡：蝙蝠 → `tutorial2`（教程2），蛇 → `s07`（素音目标点专测），羊头 → `s08`（双 Hold 调频联动）。底部两侧保留返回、本地谱面、随从、设置入口。左右切卡，下移到功能栏、上移回卡片，确认进入；返回选关保留上次卡位。卡片使用正式关卡 ID 读取成绩和解锁状态。

`mvp_catalog.tres` 的可玩目录保留上述三关；早期测试资源未删除，场景发现仍保留它们供写谱器和回归测试引用。教程源自根目录 `Charts/charts/教程2` 的 normal 难度，源谱及音乐复制到 `content/stages/tutorial2/source`，不依赖工程外路径。通过 `tools/content/import_tutorial2.gd` 使用现有 JSON 解析和路径投影生成正式资源，保留原谱 s08 场景、首拍偏移、BPM、音符与调频编排。更新工程内源谱后运行 `Godot --headless --path . --script res://tools/content/import_tutorial2.gd -- --chart-editor`；先完成新增音乐的编辑器导入。教程使用默认正式规则，未开启测试关不致死选项，不新增随从奖励规则。

正式入口截图：`builds/pet-review/menu-carousel.png`；教程运行截图：`builds/pet-review/tutorial2-game.png`。

### 编辑器脚本错误回归

本次修复只迁移测试和检查入口，没有恢复旧玩法 API。2026-09-15 验证：

- 全工程加载：413 份 GDScript，0 解析 / 编译错误。
- 输入与 Replay V3：219 项；声波交互：38 项。
- 关卡运行时：356 项；正式 AppMain 流程：33 项。
- 主界面实际 Compatibility 渲染检查：49 项。

检查入口（在 Game 目录运行，Godot 替换成本机引擎路径）：

```powershell
Godot --headless --path . --script res://tools/testing/check_scripts.gd
Godot --headless --path . --script res://tools/testing/run_stage_runtime.gd
./tools/ui/run_ui_review.ps1 -Suites title,app-flow
```

关卡测试通过延迟入口加载，让 `SettingsService` 等 Autoload 先注册。当前 StageRoot 将旧 `replay_recorder` 与 `replay_input_driver` 置空，因此旧录制 / 注入集成检查明确输出 SKIP；此项不计入通过数，不代表局内 Replay 接线已恢复。独立 Replay 编解码与回放检查仍执行。若重新接入这两个节点，保留的集成检查会再次执行。

## 手柄操作与键位提示（2026-09-15）

正式选关的快捷入口只在本页获得焦点时响应；打开弹窗前先选中对应入口，关闭后回到该按钮。随从和设置页接管肩键，按住或松开都不穿透到选关。手柄键位按 Godot 的物理位置映射，不交换确认 / 返回逻辑：[Godot JoyButton 定义](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html#enum-globalscope-joybutton)。

| 操作 | Xbox | PlayStation | Nintendo | 键盘 |
| --- | --- | --- | --- | --- |
| 选关打开随从 | Y | △ | X | P |
| 选关打开设置 | X | □ | Y | O |
| 上一关 / 上一只随从 / 上一设置分类 | LB | L1 | L | Q |
| 下一关 / 下一只随从 / 下一设置分类 | RB | R1 | R | E |
| 返回 | B | ○ | A | Esc |
| 确认当前焦点 | A | × | B | Enter |

保留原有方向键、摇杆、Tab 与鼠标操作。随从的一次横向摇杆偏转只切换一只，超过 0.55 触发、回到 0.30 以内重置，避免轴事件抖动造成连续翻页；肩键切换保持焦点，若目标随从未获得而禁用装备按钮，则回到预览。技能说明继续按原资源显示。设置分类用肩键循环切换，草稿不丢失；键盘正在编辑数值时 E 不触发切页。

`UiInputHints` 为菜单与关内共用的设备提示服务，按最近有效的手柄输入、键盘输入或鼠标操作切换提示；摇杆漂移不触发，鼠标微小位移不抢提示。手柄名称与厂商 ID 用于分类，拔出后选用其他已连接手柄或键盘；未知设备显示四个面键的位置，避免猜错字母。若系统 / Steam Input 将真实设备暴露成 Xbox 虚拟手柄，则显示系统提供的 Xbox 布局。没有改变领域按键采集、A/B 转换、Replay 或设备补偿。

32 份键帽、摇杆分层图与柔光遮罩统一使用灰紫底、骨白细边和手绘矢量笔画，保持小尺寸清楚；不依赖字体，也没有常驻闪烁。源图在 `assets/ui/input`，`tools/ui/generate_input_glyphs.py` 同时生成矢量副本与 `src/app/ui/input_glyph_data.gd`，运行时从同源内嵌数据预热并缓存纹理，导出包不依赖原始 SVG 是否被保留。`shortcut_glyph.gd` 只在设备变化时更新，节点位置保存在场景中，不遮挡原按钮。

主界面选中线位于按钮下方 10 px、线宽 2.4 px；选中美术字用温骨白提亮，非选中保持较暗层次。每次仍只有一个焦点。暂停面板、火框与按钮缩至原布局 84%，锚点向判定中心移动；睁眼独立使用原图圆孔中心约 `(418,169)`、内半径 129 px，对齐设计中心 `(960,540)` 和判定圈 66 px 半径。数字居中，原来的 3、2、1 各一秒不变。暂停主按钮方向左右循环，试玩附加按钮参与 Tab 与向下导航。

验证使用 `tools/ui/run_ui_review.ps1 -Suites controller,title,art`，在独立用户目录运行正式 AppMain。键位验证使用合成的真实 `InputEventJoypadButton` / `InputEventJoypadMotion` 事件，并单独检查设备名称和厂商 ID；不等同于三款实体手柄均已插机测试。截图位于 `builds/controller-review`，包括五类键帽、选关、随从、设置、主菜单和暂停眼眶。

上一轮验证结果：手柄 UI 75 项、主界面 49 项、原有弹窗 111 项，共 235 项通过，Compatibility 日志无脚本 / shader 错误；全工程 417 份脚本加载检查通过。暂停对齐使用真实 StageRoot 与 SettingsService 的窗口配置，在 2560×1440 渲染、1280×720 窗口及 1800×1200 非 16:9 窗口中核对中心与半径。后者保持 1920×1080 渲染后等比留边，截图记录 Viewport 内容，不包含原生窗口外框。

主要截图：`controller-glyphs.png`、`stage-xbox.png`、`stage-nintendo.png`、`pets-shoulders.png`、`settings-playstation.png`、`title-selected.png`、`pause-compact.png`、`pause-eye-aligned.png`、`pause-window-1280x720.png`、`pause-window-1800x1200.png`，均在 `builds/controller-review`。

### 关内提示与摇杆手势（2026-09-15）

选关、随从页的左右美术箭头下不再摆放 Q / E 或肩键键帽，切换绑定保留。随从、设置、返回等操作入口继续显示快捷图标。

判定圈旁仅显示当前设备的敲钟图标：生侧右上为 RB / R1 / R / J，死侧左下为 LB / L1 / L / F。与菜单共用灰紫底、骨白线和缓存纹理，不再并排列出三种设备的文字。判定圈旁键帽高度为 36 设计像素（原 40），整体不透明度 65%，继续与已有调频淡化叠乘。通用手柄肩键复用 Xbox 的 LB / RB，菜单与关内一致；键鼠模式显示 J / F，原鼠标敲钟操作仍保留。玩法缓冲消费输入前通知提示服务，设备提示不会因事件被消费而停留在旧状态。

调频旋向提示采用贴近平面的灰紫摇杆帽与薄底座，L / R 显示在帽面。使用低对比平涂及骨白细边，去掉杆身、侧壁、投影与凹面高光；图层宽 52 设计像素，方向弧半径 27 px，帽面与底座明确分开，帽面宽 36 px，拨动半径为水平 12 px、竖直 9 px；上述几何围绕提示中心整体放大 15%，方向弧直径实际约 62 px，采用 75% 不透明度。方向弧、摇杆帽和底座统一采用 75% 绘制不透明度，并与既有预读及等待状态淡化叠乘。生侧显示右摇杆，死侧显示左摇杆；固定在整条滑条起点靠画面中心的一侧，与条身留出间距；进入交互、切换目标端点和折返均不移动提示位置。旋向与角度沿用 `required_rotation_sign` 和现有手势几何，摇杆帽按宿主时间每 1.2 秒循环演示当前单程的要求方向，方向弧上有同步移动的短亮段；长滑条也能看清动作。每次演示结束淡出复位，不绘制误导性的反向回程。预读也演示起手方向，正式单程开始时从起手方向演示；折返读取新的权威旋向。无需继续旋转、失败或收尾时隐藏。暂停、定位、重复状态推送不启动独立动画计时，也不增加节点或动态纹理。

本次验证：Compatibility 实际渲染下手柄 UI 107 项通过，涵盖箭头无键帽、设备切换、两侧正反旋向、折返接续、冻结、定位与回收；关卡运行时 356 项通过。运行时仍跳过原有未接入的 StageRoot Replay 节点检查，没有更改 Replay 接线。新增 `builds/controller-review/tuning-stick-10.png`、`tuning-stick-25.png`、`tuning-stick-40.png`，记录测试关背景上的三阶段姿态；选关和随从截图同步刷新。实体手柄各品牌仍需真机体验确认。

参考资料：[Kenney Input Prompts](https://kenney.nl/assets/input-prompts) 提供分设备的按钮与手势符号；[《战神：诸神黄昏》官方辅助功能](https://www.playstation.com/en-us/games/god-of-war-ragnarok/accessibility/) 将图标尺寸、控制器可视化和 HUD 对比作为独立的可读性选项。本轮借鉴清楚区分按键身份与操作方向的表达，保持项目自己的灰紫、骨白与小尺寸轮廓。

动态验证：`tools/ui/run_ui_review.ps1 -Suites controller,stick-motion`；`tests/visual/capture_stick_gesture.gd` 直接调用正式提示绘制，按 30 FPS 记录四种旋向，图标放大两倍便于检查。使用带 Pillow 的 Python 运行 `tools/ui/encode_stick_preview.py`，得到 `builds/controller-review/stick-motion.gif`（2.4 秒、两个完整循环）。107 项 UI 检查包含长单程重复演示及隐藏复位，并检查暂停、定位与两侧方向。

摇杆追加弱柔光：底座与帽面使用缓存椭圆遮罩，灰青／赭红外晕系数 0.34、骨白近边系数 0.24，再乘提示透明度；底座光强额外乘 0.65。移动方向亮段叠加窄骨白柔边。光晕随原有演示淡出、暂停和定位更新，不新增灯光、视口或运行时纹理；判定圈旁的肩键提示仍为 65%。


## Memo 工作室开屏

正式游戏首次进入标题页时播放 `scenes/screens/boot_splash.tscn`。原图完整复制到 `assets/ui/art/boot/memo_splash.png`，等比居中显示，非 16:9 窗口留黑边。默认淡入 0.6 秒、停留 1.2 秒、淡出 0.6 秒，再用 0.3 秒从黑场过渡到原有等待输入页面；前三项可在开屏场景 Inspector 调整。开屏期间隔离输入，每次运行仅播放一次，返回主菜单不重复；编辑器与外部试玩入口保持直接启动。

验证入口：`tools/ui/run_ui_review.ps1 -Suites title,app-flow`；开屏截图输出至 `builds/title-review/memo-splash.png`。

多节点 Tuning 拆成运行时分段后，仅首段显示起点摇杆动画，后续分段不重复绘制。表现标记随编译和对象池准备传递，不参与判定或 Replay；旧版独立滑条仍默认显示起点提示。
