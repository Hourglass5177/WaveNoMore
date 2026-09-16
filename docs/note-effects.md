# 音符配色与裂解效果

Ghost 的闭眼／睁眼素材、骨白光及额外预告见 [Ghost 眼睛与柔光](ghost-effects.md)，正式游戏与写谱器预览共用同一全局资源。

更新日期：2026-09-13。适用 Godot 4.7 Compatibility、正式游戏、独立写谱器预览和 ArtLab。

## 全局参数

打开 `content/presentation/note_effect_style.tres` 调整全局效果。资源类型为 `NoteEffectStyle`；关卡主题继续选择音符素材，不再提供每关的音符光色覆盖。

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| 生侧暗部／本体／亮部 | `#172A31` / `#3F5967` / `#73818E` | 青蓝明度映射，保留颗粒与暗纹 |
| 生侧外晕 | `#517587` | 稍亮的青蓝柔光 |
| 死侧暗部／本体／亮部 | `#45201F` / `#87382E` / `#BA5841` | 赭红漆色，眼部与睫毛保留原色 |
| 死侧外晕 | `#AD4638` | 暖赭红柔光 |
| 外晕宽度／近边宽度 | 36 / 3 px | 1920×1080 设计像素，随整体画布缩放 |
| 外晕／本体提亮强度 | 0.80 / 0.18 | 平时的阵营色光 |
| 条件白光色／强度 | `#E6DDC9` / 0.48 | 双押与实际调频控制的本体提亮 |
| 双押头部提前／渐亮 | 0.60 / 0.15 s | 同 tick 或同非空组的双侧 Tap／Hold 头部 |
| Hold 渐亮／退出 | 0.10 / 0.08 s | 只读当前侧交互窗口、dragging 与 Hold 控制关联 |
| 命中亮痕／续行亮度 | 0.08 s / 45% | Tap 接受按键后隐藏圈和所有光晕 |
| 眼球变化／放大 | 0.08 s / 1.20 倍 | 可动暗色眼球平滑褪成骨白，局部亮度独立于暗淡本体 |
| 裂解震颤 | 0.06 s / 2 px | 沿冲击方向衰减，只影响音符与碎片 |
| 裂隙／漆片／光尘 | 0.03 / 0.26 / 0.34 s | 在真实声波接触时替换完整 Tap |
| Tap 漆片／光尘 | 8 / 12 | 稳定编号的非规则纹理薄片，快速散开后减速 |
| Hold 收尾 | 5 片＋6 尘，0.24 s | 成功结束播放一次轻量裂解 |
| Hold 消耗采样 | 24 px | 跨过固定消耗距离时产生一枚细屑 |

`enabled` 供全局关闭与性能对照使用。颜色和时间属于表现资源，不进入谱面 JSON、判定数据或 Replay 摘要。

## 混合双押头部白光

`ChartScheduler` 在装谱时统一索引 Tap／Tap、Hold／Hold、Tap／Hold，生成只读表现字段 `double_press`，替代旧 `double_tap`。同侧、Hold 尾部相遇、持续区间重叠及 SU 不加入双押；同组不同 tick 的音符各自按头部时间渐亮。没有逐帧配对查询或 JSON 格式变化。

Hold 的 `head_double_glow` 与现有调频 `glow_amount` 分离：头部取两者较大值，身体和尾部只取调频亮度。成功命中或漏击后，头部双押亮度从接受时刻的实际值在 0.08 秒内淡出；重复事件不重启，收尾和回收清零。正式头部贴图与程序化头部都接入，近轮廓转向骨白，外晕保持阵营色。白光变化只更新已有材质，不重建身体网格。

`set_note_glow_time()` 现在也由宿主提供给 Hold；接近与淡出依照绝对视觉时间求值，调频仍只读原玩法快照。ArtLab 的接近状态使用同一头部入口，其他 Hold 演示状态保持调频白光语义。

2026-09-13 验证：混合双押专项 156 项、原音符白光 56 项、计时提示 68 项、Tap 反馈 185 项及滑条 41 项均通过。包含身体／尾部像素不变、各自头部时刻、命中中途淡出、调频取最大值、暂停、定位、重复事件及资源复用。正式预览截图位于 `builds/mixed-double-review/preview-*.png`，头部开关对照为同目录 `head-off-*` 与 `head-on-*`。

Compatibility、RTX 4060 Laptop、1080p 下固定 12 Tap＋12 Hold 做四段开关测试：关闭时整帧平均 1.16／0.96 ms，P95 1.83／1.46 ms；开启时平均 1.31／1.53 ms，P95 2.09／2.32 ms。首次渐亮四帧峰值 1.84／1.57 ms；初次装配整批素材有 23.59 ms 峰值。GPU 平均约 0.09～0.12 ms，没有随双押开启出现明显增加；节点数始终 143，Hold 身体网格 RID 未变。该测试固定身体姿态以隔离白光开销，不代表完整关卡帧率。数据在 `builds/mixed-double-review/performance.json`。本轮未 build、提交或推送。

## 素材接入

- Tap 眼部保留原色，但眼眶和可动瞳孔共同参与条件骨白提亮，沿用全局白光强度；原有浅色眼白不压暗，睫毛继续保持中性。命中后的眼球放大与褪白仍独立按事件时间推进。
- 保留现有 Tap 底图、眼球和眼部遮罩组合，增加 `tap_lashes.png` 中性睫毛保护遮罩。两侧着色共用 `note_surface.gdshaderinc`，眼球合成共用 `note_eye.gdshaderinc`；碎裂时冻结眼球偏移、放大和褪白进度。
- 当前原图睫毛向下。正式宿主让 Tap 随普通路线切线或 BOSS 发射速度倾斜，并选朝分界线的一面；当前蓝侧朝下、红侧朝上。原图、眼球、遮罩、柔光与碎片一起变换，不能分别翻转。
- Hold 继续使用头部贴图与可平铺身体。身体沿原动态脊线绘制，头部与身体采用同一套色板；尖尾包含在身体网格中。
- 正式贴图的距离遮罩与原图同目录，命名为 `<原图名>_glow.png`。遮罩按长边 96 设计像素生成，2 倍采样、四周预留 64 设计像素；保留线性数据导入。常用柔光宽度在 1～60 px 内调整。
- 替换 PNG 后运行 `python tools/generate_note_glow_masks.py assets/image/note/新素材.png`。默认不传路径会更新当前 Tap 与两种 Hold 头部；依赖 Pillow、NumPy。处理 `tap_base.png` 时还根据中性浅色区域生成睫毛遮罩，并排除 `tap_musk.png` 眼眶内部。换成不同构图后应检查遮罩，必要时由美术提供同尺寸灰度遮罩；白色保护、黑色染色。工具不改写原图。
- 裂解网格使用原图 UV 和透明轮廓，不需要为当前素材手工切片。工具生成的遮罩随素材一起纳入工程与发布包。
- 自定义音符场景实现 `configure_effect_style(style, affinity)`，继续响应 `prepare`、`play_timing_confirmed`、`play_wave_contact`、`reset_for_pool`；默认 Tap/Hold 已完整接入。自定义 shader 可包含共用着色文件。

## 时间与生命周期

按键反馈、真正波接触和 Hold 结束分别触发不同效果。表现宿主将触发时的姿态交给独立 `NoteFragmentHost`，所以本体隐藏或回收不会截断碎片。重复事件由原音符状态和活动效果 ID 去重。

按键到波接触不足 0.08 秒时立即裂解，使用当时眼球变化进度，不延后死亡。震颤以稳定事件 ID 和绝对事件年龄解析求值；暂停冻结，定位重演得到相同姿态，池复用清除眼部状态。

## 声波空间扭曲

`content/presentation/wave_distortion_style.tres` 是全局 `WaveDistortionStyle`：开关、单波位移 12 px、主波带半宽 36 px、短尾长度 32 px、短尾相对强度 0.025、总位移上限 14 px、波源淡入距离 120 px、远端强度 0.70、画布边缘淡出 64 px。均使用设计画布像素，随窗口和写谱器 SubViewport 整体缩放。

`TuningInterferenceVisual.render_fronts_changed` 发布已筛选的两侧渲染波前，每侧至多 16 条。`WaveDistortionVisual` 直接消费同一批发射时间、波源、波速和视觉时间，不保存第二套发波历史、不触发 Ghost 查询。每道声波的主峰位于真实波前；主波带前后各 36 px，后缘再接 32 px 的一次微弱反向短尾。按默认波速，明显主波带经过一个位置约 30 ms，轻微短尾约 13 ms。主波带与短尾不重叠，使用三次包络，连接点和外边界的位移、一阶及二阶导数均为零；波源附近连续淡入，交汇以平滑饱和限制位移。单波参数表示饱和前幅度；实际位移还受传播距离与画布边缘衰减影响。

玩法绘制完成后，CanvasLayer 3 使用一次 `BackBufferCopy` 和一次屏幕颜色取样。中央判定框、时机环与调频操作界面在第 5 层，教程面板在第 6 层，HUD 在第 10 层。这些提示与外部编辑器界面保持稳定，背景、角色、Tap/Hold 及碎片一起形变。独立判定画布跟随正式画布变换，节点进出对象池保留设计坐标，避免缩放叠加。没有可见波前或关闭效果时，同时停用复制和绘制。背景、钟、声波、Tuning、Ghost 自身色板保持原配置。

每次裂解使用一个可复用网格节点，网格模板缓存后不逐帧重建。片中心、片编号和类型存入顶点数据，位移、旋转、断面亮度和透明度由 shader 根据绝对事件年龄求值。没有逐碎片节点、运行时大半径模糊或逐音符 SubViewport；初始化阶段只借用现有一次性小视口预热材质。

暂停不推进视觉时钟。写谱器在 Hold 可见区间用 120 Hz 固定运动采样，普通播放与直接定位共用；稀疏输入间也恢复身体与消耗位置。没有 Hold 的空段跳过固定采样，长 Hold 分批恢复并保持定位可取消。HUD、背景和相纹在预览帧尾集中发布。

## 检查入口

ArtLab 的 `note_zhu`、`note_xuan`、`note_hold` 条目接入 `note_effect_preview.tscn`，直接调用正式 Tap/Hold 的表现脚本和全局资源。可切换普通、调频、命中与结束状态；Hold 条目同时展示两侧。场景只负责预览编排，不另存一套光色参数。

使用 Godot `--path . --script <脚本>` 运行；状态测试可加 `--headless`，截图与性能测量需实际图形渲染。

- `tests/visual/run_tap_feedback_tests.gd`：按键、波接触、重复事件、对象池、定位与独立碎片。
- `tests/visual/run_note_glow_tests.gd`：双押、单／双侧调频、松开、连续滑条、Hold 细屑和结束阶段的定位一致性。
- `tests/visual/run_note_effect_style_tests.gd`：正式材质、全局参数、独立 ArtLab 实例、网格复用与配色／裂解截图。
- `tests/integration/stage/run_tap_eye_tests.gd`、`run_note_edge_glow_tests.gd`：眼球方向、缩放、透明合成及横竖画布。
- `tests/editor/run_preview_frame_tests.gd`：定位纹理冻结、取消、后台休眠、重建结果一致性。
- `tests/visual/measure_note_effect_density.gd`：固定密集负载交替关闭／开启特效。
- `tests/visual/measure_note_effect_comparison.gd`：真实谱面同进程交替采样；默认使用 `../Charts/charts/test/song.json`。`-- --phases=2` 可运行一组关闭／开启。
- `tests/visual/run_wave_distortion_tests.gd`：实际像素检查波前主峰、反向短尾、连续发波间隙、叠加上限、HUD、留边、缩放、暂停与恢复。
- `tests/visual/measure_wave_distortion.gd`：实际 Ghost 谱段交替开关折射；`-- --fixed` 固定正式画面并测试 16＋16 条波前，记录 GPU 时间；`-- --capture` 输出 60 fps 连续帧，每次冻结同一已提交姿态再切换折射开关，分别保存开启／关闭对照。局部波前版输出位于 `builds/visual-review/wave-distortion-focus/`。

截图与原始测量输出位于 `builds/visual-review/note-effects/`，本轮不导出应用。

换色、眼睛与折射结果见 [验证记录](note-effects.md)。早期光效结果保留在 [历史验证记录](note-effects.md)。

调频滑条的半透明配色、起点预填与骨白／阵营柔光见 [调频滑条表现](tuning-visual-style.md)。

音符进度环、接近缩圈与滑条起点缩圈共用 `TimingCueStyle`；提示色比本体略偏青绿／暖铜，并带窄柔光，参数和验证见 [计时提示](timing-cue-style.md)。

Hold 动态网格改为同拓扑缓冲更新，定位恢复的中间步骤只推进运动；相纹与折射在最终画面统一提交。游戏新增 720p～4K 渲染分辨率，设计坐标保持 1920×1080，眼球、折射与背景接缝已同步适配。实现、实际帧耗时及验证边界见 [关卡性能与分辨率](performance-and-resolution.md)。
