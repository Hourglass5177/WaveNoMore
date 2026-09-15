# 暂停、设置与随从 UI

2026-09-14，`ui` 独立 worktree，已同步队友 `origin/ui@126fe74` 的卡片框图。新一轮修改未构建发布包、提交或推送。

## 页面入口

| 页面 | Godot 场景 | 数据与动作 |
| --- | --- | --- |
| 暂停 | `scenes/ui/hud/pause_overlay.tscn` | StageSession 的暂停、恢复倒计时、重试、退出；外部试玩附加操作保留 |
| 设置 | `scenes/ui/modals/settings_modal.tscn` | 声音、画面、校准三个分类，保存统一提交，取消丢弃草稿 |
| 随从 | `scenes/ui/modals/pet_select_modal.tscn` | 当前装备定位、左右浏览、静息循环、点击技能预览、装备与卸下 |

根节点的 `Design` 使用 1920×1080 设计坐标，屏幕变化由 `art_screen.gd` 等比缩放并居中。子部件位置均保存到场景，可直接在 Godot 中调整。弹窗隔离底层输入，关闭时 AppMain 恢复原焦点；随从左右方向键用于切换，确认预览区播放一次技能。预览区不显示选中下划线或悬浮提示；其他按钮保持交互细光。

暂停按钮从左到右为“重玩／继续／退出”，默认焦点仍为继续。继续时面板、火框、按钮与遮罩在 0.14 秒内淡出，独立睁眼显示会话剩余倒计时；最后 0.14 秒眼睛与数字淡出，不延长恢复时刻。重玩先收起面板，再按会话现有 `resume_countdown_sec` 显示眼内倒计时，结束后才重置关卡，过渡期间原会话保持暂停。数字使用 Huiwen 字体并向上取整，重复确认不重新计时。外部试玩沿用相同退场，并保留动态退出文字及附加操作。

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

分数字体为 Huiwen、48 px，`content/ui/score_gradient.tres` 使用横向渐变覆盖整段文字。左端精确采用参考的 RGB 144/129/118（`#908176`），中间骨白 `#D3D4CA` 与右端暖灰 `#AB9E8B` 取自截图，渐变中间的亮部停靠约 65.5%。额外取样点重现参考图 13% 中点形成的较快左侧提亮。`score_gradient.gdshader` 以整段文字的局部横坐标采样，保留原字形透明边缘，不让每个数字重复渐变。卡片各自保存文字范围，字体大小或文字长度改变时更新；侧卡只保留背面，分数随选择权重淡出。

`LevelCardEntry.monster_scale` 单独调节立绘大小；蝙蝠采用 1.40，其余仍为 1.0。卡片与父级不裁切，翅膀可以自然越过边缘。背景、分数和卡位尺寸保持原配置。原本混入分数的卡片序号与用于占位的评级标题已移除。

## 验证与截图

运行 `tools/ui/run_ui_review.ps1`；可用 `-Suites art` 只复测 UI 交互与截图。脚本仅在当前 worktree 临时设置 `override.cfg`，使用 `WaveNoMore-UIReview` 用户目录，结束恢复原配置。首次导入包含 Spine 时需让 Godot 完成扩展初始化及资源导入；原工作区的 `.godot` 缓存不共用。

| 检查 | 结果 |
| --- | --- |
| 新 UI、草稿、取消、保存、动画复用、真实会话暂停/继续/重试/退出 | 106 项通过 |
| 正式轮播、手柄导航、教程加载、弹窗隔离及返回焦点 | 55 项通过 |
| 校准统计、未回车输入、建议应用、正式关卡接线 | 上轮 142 项通过，本轮未改测量算法 |
| 窗口/全屏五档实际渲染像素及正式 UI 字体 | 上轮 31 项通过 |
| 工具字体隔离 | 上轮 1 项通过 |
| 选关轮播、最高分、立绘缩放、渐变实例与布局 | 394 项通过 |

图形验证使用 Godot 4.7.2、Compatibility、RTX 4060 Laptop。五档窗口与全屏读回尺寸均等于选定尺寸；另检查 1800×1200 的等比留边。UI 动画预览更新的 120 次 CPU 采样：本轮平均约 0.19 ms、P95 约 0.23 ms、最大约 0.31 ms；这是动画更新成本，不代表整帧 GPU 或整局性能。

旧 `run_stage_runtime_tests.gd` 在当前 UI 分支仍引用已不存在的 `InputRouter` 和旧输入枚举，不能解析；未把它记为通过。本轮使用真实 StageRoot 会话补验相关暂停流程，没有为旧测试恢复过时玩法 API。校准测试原有两次后台任务节点泄漏已在测试清理中修正，142 项断言通过且退出无资源泄漏警告。

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
