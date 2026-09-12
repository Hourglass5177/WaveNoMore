# 换色、眼睛反馈与声波折射验证

2026-09-13，Godot 4.7.2 Compatibility / OpenGL 3.3，NVIDIA GeForce RTX 4060 Laptop GPU。工程内运行，未导出、打包或推送。

本轮生侧青蓝、死侧赭红。按最后确认的方向，睫毛朝分界线：当前蓝侧朝下、红侧朝上；普通路线与 BOSS 发射均保留切线倾斜。Tap 眼球在命中后 80 ms 内放大至 1.20 倍并褪白，接触时立即冻结状态并裂解。

## 回归结果

| 检查入口 | 结果 |
| --- | --- |
| `run_tap_feedback_tests.gd` | 185 项通过，含朝向、40 ms 中点、重复事件、池复用、连续播放与直接定位的眼球／碎片／波前一致性 |
| `run_note_effect_style_tests.gd` | 26 项通过，含短间隔立即裂解、碎片眼部冻结及 184 个正式睫毛内部像素的中性色检查 |
| `run_wave_distortion_tests.gd` | 22 项通过，含原尺寸／半尺寸画布、波带外与 HUD 像素稳定、暂停、重试、恢复及 16＋16 波前叠加上限 |
| `run_tap_eye_tests.gd` | 通过，实际 GPU 量测眼球追踪、旋转、缩放、透明合成、约 1.20 倍放大及眼眶裁切 |
| `run_note_edge_glow_tests.gd` | 通过，两侧材质实例隔离及 Hold 横竖布局 |
| `run_note_glow_tests.gd` | 通过，普通／双押、单／双侧 Hold 控制、消耗与结束阶段的暂停和定位 |
| `run_level_boss_tests.gd` | 21 项通过，发射速度朝向、入轨衔接、回拖恢复及生命周期 |
| `run_preview_frame_tests.gd` | 通过，写谱器纹理冻结、定位取消、后台休眠及恢复 |

以上均使用实际 Compatibility 图形渲染。编辑器导入和差异空白检查通过，无脚本或 shader 错误。最大叠加的设计位移为 3 px；使用 8 位 RGB 渐变取样的像素量测有约 0.25 px 量化误差。

## 性能

使用 `tests/visual/measure_wave_distortion.gd`，1080p，关闭 VSync 和帧率上限。读取本地 `Charts/charts/test/song.json` 的真实 Ghost 段，并在内存装配 s08 正式素材与墓地背景；未修改用户谱面。

连续推进 960 帧，每帧推进 1/120 秒，共四阶段交替开关。按完整帧间隔统计，包含原有玩法重演、绘制和系统调度。

| 阶段 | 平均帧耗时 | P95 | 最大值 |
| --- | ---: | ---: | ---: |
| 关闭 1 | 13.020 ms | 23.801 ms | 44.725 ms |
| 开启 1 | 12.502 ms | 21.481 ms | 49.218 ms |
| 关闭 2 | 13.230 ms | 21.938 ms | 48.369 ms |
| 开启 2 | 14.004 ms | 22.868 ms | 45.645 ms |

首次可见波前及其后 3 帧的峰值：关闭为 9.118 / 19.468 ms，开启为 8.994 / 12.735 ms；材质已按正式加载路径预热。Ghost 准备事件数峰值为 2。原有场景的 CPU 更新峰值为 36～41 ms，整帧仍有约 45～49 ms 峰值，不能把这部分归因于折射或宣称已解决。

为隔离 CPU 重演波动，`--fixed` 固定同一正式画面，保留 Ghost 状态，并设置每侧 16 条可见波前。每阶段预热 30 帧、采样 360 帧。GPU 时间通过 [Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu) 的视口测量取得。

| 阶段 | GPU 平均 | GPU P95 | GPU 最大 | 整帧平均 |
| --- | ---: | ---: | ---: | ---: |
| 关闭 1 | 2.661 ms | 3.322 ms | 3.694 ms | 2.900 ms |
| 开启 1 | 2.987 ms | 3.740 ms | 3.801 ms | 3.078 ms |
| 关闭 2 | 2.683 ms | 3.328 ms | 3.881 ms | 2.945 ms |
| 开启 2 | 3.078 ms | 3.936 ms | 5.200 ms | 3.510 ms |

成对比较，平均 GPU 增量 0.326 / 0.395 ms，P95 增量 0.418 / 0.608 ms，达到平均 ≤1 ms、P95 ≤2 ms 的目标。整帧平均增量 0.178 / 0.565 ms。结果只代表本机及上述负载，原始数据保存在 `builds/visual-review/wave-distortion/performance*.json`。

## 画面与复现

- `builds/visual-review/note-effects/palette-and-fracture.png`：两侧常态、骨白强调、命中眼球变化、裂解连续阶段及 Hold。
- `builds/visual-review/note-effects/eye-sequence.png`：命中后 0 / 40 / 80 ms，以及 40 ms 即接触的短间隔裂解。
- `builds/visual-review/wave-distortion/grid-off-*.png` / `grid-on-*.png`：原尺寸与半尺寸 SubViewport 的像素对照。
- `builds/visual-review/wave-distortion/wave-distortion.mp4`：正式预览 1080p / 60 fps 的 6 秒连续画面。

折射仅沿窄波带改变采样位置，分界线、角色、引导和场景素材进入同一次屏幕复制；教程面板与 HUD 后绘制。程序不增加音频延迟，不改命中坐标、输入、谱面或 Replay。
