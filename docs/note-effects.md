# 音符配色与裂解效果

更新日期：2026-09-13。适用 Godot 4.7 Compatibility、正式游戏、独立写谱器预览和 ArtLab。

## 全局参数

打开 `content/presentation/note_effect_style.tres` 调整全局效果。资源类型为 `NoteEffectStyle`；关卡主题继续选择音符素材，不再提供每关的音符光色覆盖。

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| 生侧暗部／本体／亮部 | `#45201F` / `#87382E` / `#BA5841` | 按原图明度重映射，眼部保留对比 |
| 生侧外晕 | `#AD4638` | 暖赭红柔光 |
| 死侧外晕／亮边 | `#102A2C` / `#416466` | 保留本体原色，叠加青黑柔光 |
| 外晕宽度／近边宽度 | 36 / 3 px | 1920×1080 设计像素，随整体画布缩放 |
| 外晕／本体提亮强度 | 0.80 / 0.18 | 平时的阵营色光 |
| 条件白光色／强度 | `#E6DDC9` / 0.48 | 双押与实际调频控制的本体提亮 |
| Tap 提前／渐亮 | 0.60 / 0.15 s | 沿用同 tick 或同组的双侧 Tap 识别 |
| Hold 渐亮／退出 | 0.10 / 0.08 s | 只读当前侧交互窗口、dragging 与 Hold 控制关联 |
| 命中亮痕／续行亮度 | 0.08 s / 45% | Tap 接受按键后隐藏圈和所有光晕 |
| 裂隙／漆片／光尘 | 0.03 / 0.26 / 0.34 s | 在真实声波接触时替换完整 Tap |
| Tap 漆片／光尘 | 8 / 12 | 稳定编号的非规则纹理薄片，快速散开后减速 |
| Hold 收尾 | 5 片＋6 尘，0.24 s | 成功结束播放一次轻量裂解 |
| Hold 消耗采样 | 24 px | 跨过固定消耗距离时产生一枚细屑 |

`enabled` 供全局关闭与性能对照使用。颜色和时间属于表现资源，不进入谱面 JSON、判定数据或 Replay 摘要。

## 素材接入

- 保留现有 Tap 底图、眼球和眼部遮罩组合。着色代码共用 `shaders/notes/note_surface.gdshaderinc`；眼球偏移在碎裂时冻结。
- Hold 继续使用头部贴图与可平铺身体。身体沿原动态脊线绘制，头部与身体采用同一套色板；尖尾包含在身体网格中。
- 正式贴图的距离遮罩与原图同目录，命名为 `<原图名>_glow.png`。遮罩按长边 96 设计像素生成，2 倍采样、四周预留 64 设计像素；保留线性数据导入。常用柔光宽度在 1～60 px 内调整。
- 替换 PNG 后运行 `python tools/generate_note_glow_masks.py assets/image/note/新素材.png`。默认不传路径会更新当前 Tap 与两种 Hold 头部；依赖 Pillow、NumPy。只生成遮罩，不改写原图。
- 裂解网格使用原图 UV 和透明轮廓，不需要为当前素材手工切片。工具生成的遮罩随素材一起纳入工程与发布包。
- 自定义音符场景实现 `configure_effect_style(style, affinity)`，继续响应 `prepare`、`play_timing_confirmed`、`play_wave_contact`、`reset_for_pool`；默认 Tap/Hold 已完整接入。自定义 shader 可包含共用着色文件。

## 时间与生命周期

按键反馈、真正波接触和 Hold 结束分别触发不同效果。表现宿主将触发时的姿态交给独立 `NoteFragmentHost`，所以本体隐藏或回收不会截断碎片。重复事件由原音符状态和活动效果 ID 去重。

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

截图与原始测量输出位于 `builds/visual-review/note-effects/`，本轮不导出应用。

本轮结果见 [验证记录](note-effects-validation.md)。
