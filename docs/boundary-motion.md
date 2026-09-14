# 波浪分界线：逐拍推进与小节拍落

基线：2026-09-14。正式背景使用 `scenes/presentation/boundary_waves.tscn`。原始 `edge.png` 保留；关闭动画时直接显示原图。旧整图微形变只留作审看对照。

## 动作与时间

- 每拍从三个小浪区域轮流生成一对小浪，中心对称，存活三拍、前进约 140 设计 px，每侧最多三道。
- 小浪纵向比例 0.30、横向 0.43，高浪段约 60 px；浪根位于水面基准上方 8 px，仍嵌在底带内。相较上一轮上移 6 px、高度增加约 15%，死界由父节点中心对称。中央大浪保留配置浪高，横向基准 0.76，让坡面与卷顶更挺立。
- 底带保留原画自身的厚薄、凹凸走势、粉灰块面与薄白浪缘。原来突出的八处静态浪头在浪根外局部压成约 12 素材 px 的低水脊，避免与活动浪重复；水带内部及其余天然轮廓不裁平、不拉伸。
- 默认每小节首拍拍落一对中央大浪。每道浪跨两小节：前 1.5 小节成形、前进、卷顶与下扣，后半小节摊开、前滑和消退。每侧最多两道。
- 浪身推进默认 190 px；高浪约 165 px；卷顶横向尺度按 90 px 基准配置；拍落后水沫再向前滑约 120 px。默认 1920×1080 画布，随背景条目整体缩放。
- 目标触水为动作相位 0.75。补绘关键形态位于 0、0.22、0.40、0.60、0.69、0.75、0.86、1.0；薄浪唇有独立加权骨骼余势。
- 浪花保留完整透明轮廓，经过判定圈后方；取消原先约 70 px 的圆形透明裁切，遮挡由正式界面的前后层级处理。原画底带贯穿分界线；前浪退去时后浪已经形成外侧弧面。

`BoundaryWaveSchedule` 使用 `TempoMap.us_to_tick()`，以四分音符为连续内部坐标；拍号段决定每拍长度与小节首拍。每道浪保留所属段的长度，变 BPM 连续变速，换拍号仍按原段收尾。负时间和开场直接获得已在运行的浪，不等待填满水面。

## 素材与编辑

### 基底水流

`boundary_water_flow.gdshader` 在底带原有的一次绘制内完成原纹与细纹混合。两组纹理按流向图搬运，错开半周期，将三角权重平方并归一化，让主导水纹更清楚，减少宽色带的相反偏移被冲淡；控制图的空间相位使各处不同步重置。原纹默认 60 设计 px/s、混合强度 80%，细水纹峰值 24%、速度倍率 1.3。颜色使用原画粉灰、蓝紫及骨白，不叠加发光。

`flow_control.png` 为 1325×720 数据图：RG 编码局部流速向量（0.5 为零）、B 为内部权重、A 为空间相位。方向与相位保持中心对称，边缘权重取两侧可流动区域的交集。`flow_streaks.png` 是从原始 `edge.png` 的薄白水线提取的 512×96 重复贴图；约 35～100 px 长、1～3 px 宽，疏密错开。两图由 `tools/boundary_animation/build_flow.py` 生成，重建底带时自动同步生成。

固定原 UV 的透明度和最外侧约 6 设计 px，向内 5 px 渐入流动；只在内部短程搬运颜色。原纹采样落到透明处时混回当前位置原色，避免黑边。中央约 55 px 内水流权重为零，向外 90 px 内逐渐恢复。每个背景实例单独持有材质，位置及尺寸仍由背景条目控制。

水流沿用歌曲绝对秒数，向 shader 传入取模后的 2 秒相位以保持长时间精度；浪头仍用 TempoMap。独立审看切换 BPM 只改变浪头节奏，水流速度不变。暂停、直接定位、环境换段均沿用同一入口。`flow_enabled` 关闭只冻结底带，`streak_strength=0` 只去掉细纹，`enabled` 关闭恢复完整原图。

实现参考：[Valve 的流向图与双阶段流动](https://cdn.akamai.steamstatic.com/apps/valve/2010/siggraph2010_vlachos_waterflow.pdf)。本项目使用颜色纹理与二维固定轮廓，不使用法线光照或流体求解。

| 文件 | 用途 |
| --- | --- |
| `assets/image/background/edge.png` | 未改动的原画与静态回退 |
| `assets/image/background/boundary_waves/source/keyposes-green.png` | 参照原画整张补绘的八形态源图 |
| `assets/image/background/boundary_waves/keyposes/00.png`～`07.png` | 共用画布和水面基准的透明关键形态 |
| `assets/image/background/boundary_waves/water_band.png` | 保留原画厚度和走势、将静态高浪局部收成低水脊的连续底带 |
| `wave.spine-json`、`wave.atlas`、`wave.tres` | Spine 4.3 可再编辑数据：根、浪身、薄浪唇，128 个补间附件与加权网格 |
| `parts/wave_000.png`～`wave_127.png` | Spine 编辑时读取的独立附件源图，`.gdignore` 避免在 Godot 中重复导入 |
| `small_frames.tres` | 保留全部 128 个轮廓的小浪序列，纹理与大浪共用图集 |
| `tools/boundary_animation/build_waves.py` | 抠色、配准、双向轮廓搬运补间、透明边缘清理和资源生成 |

补绘使用内置 imagegen，以原 `edge.png` 为参照；整张生成后以纯绿幕版本归一化，原始生成结果不覆盖。补间采用双向光流搬运再混合，透明覆盖收紧以消除轮廓重影。运行时不计算光流、不生成贴图；纹理共享，每侧保留独立 Spine 实例。主要轮廓变化由补绘附件完成，骨骼负责局部加权余势，可继续用 Spine 修改。

生成阶段使用单调 Hermite 时间曲线，关键形态间保持通过速度，替代逐段缓入缓出造成的停顿，触水相位仍为 0.75。`break` 保留完整附件序列供编辑；正式播放使用仅含骨骼的 `flow`，附件固定首帧。大小浪的独立材质按年龄采样相邻两帧并做预乘透明度补间，随渲染帧率更新，低 BPM 下也不会锁在整数轮廓帧。该补间用于密集相邻帧，不直接淡化八个跨度较大的关键形态。

着色器与生成器共用当前图集布局约定：4096×4096、10 列、400×272 单元、4 px 内边距、384×256 画布、128 帧。调整布局时两处同时修改。图集数量和分辨率未增加；各浪只增加一次相邻纹理采样，材质年龄互不串用。

背景条目 `StageBackgroundEntry` 的 `texture / sprite_frames / scene` 三选一。场景根须为 Node2D，当前作为有限素材；位置、缩放、材质和场景引用走原有保存、复制及撤销流程。场景可实现 `background_bounds()` 提供选框尺寸，`sample_background(seconds)` 接收时钟。`configure_boundary_scene(BoundaryMotion)` 供波浪取得谱面和表现配置。修改场景内容后仍按原有外部素材重载流程刷新。

五份引用分界线的正式背景已切换为场景条目，原条目坐标和缩放不变。普通 `ParallaxController` 与环境 `StageEnvironmentSlice` 共用采样入口；正式游戏、写谱预览、关卡编辑器沿用同一路径。环境片段不以 `local_sec` 重置相位；歌曲主时钟已经扣除首拍偏移，演出音频时间回退入口只减一次偏移。暂停时不推进，不使用内建 shader `TIME`。

参数见 [分界线表现](planning/07-分界线表现.md)。只进入 `BoundaryMotionStyle` 副本，不参与判定、计分或 Replay 规则摘要。

## 审看与生成

在 Godot 运行 `tools/boundary_animation/review.tscn`，支持播放、暂停、定位、BPM 与静态切换。独立预览默认 120 BPM。

```text
python tools/boundary_animation/build_waves.py
python tools/boundary_animation/verify_waves.py
godot --editor --import --quit
godot --rendering-method gl_compatibility --script tests/integration/stage/run_boundary_motion_tests.gd
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture_waves.gd
python tools/boundary_animation/package_waves.py
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture.gd -- --full
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture.gd -- --game
python tools/boundary_animation/package_waves.py --runtime
python tools/boundary_animation/package_waves.py --video
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture_waves.gd -- --fps=60 --count=240 --folder=res://build/boundary-animation/smooth-after
python tools/boundary_animation/package_smooth.py
python tools/boundary_animation/build_waves.py --band-only
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture_flow.gd
python tools/boundary_animation/package_flow.py
godot --rendering-method gl_compatibility --script tools/boundary_animation/benchmark.gd -- --flow
```

构建素材需要 Pillow、NumPy、OpenCV；游戏运行无这些依赖。输出位于忽略目录 `build/boundary-animation/`，原生截帧为 1920×1080，四小节样片为 8 秒。GIF 是截帧预览，正式场景按连续拍位采样。本轮不构建发行包。

此前流畅度修订的样片为 4 秒、240 帧、60 fps WebM；`package_smooth.py` 的前后对照还需要修改前保存的 `smooth-before` 同时刻截帧。旧版 30 fps GIF 保留作历史参考。基底水流本次新增四项参数，保留其他工作簿人工当前值；三状态水流样片为 6 秒、360 帧、60 fps，见 `water-flow-*-60fps.webm`。

底带修订样片：以 `--folder=res://build/boundary-animation/relief-after` 输出相同的 240 帧，再运行 `python tools/boundary_animation/package_smooth.py --before=smooth-after --after=relief-after --name=waves-relief`。生成器的 `--band-only` 只更新底带，无需重生成浪头图集。

验证结果及交付清单见 [本轮验收记录](boundary-waves-validation.md)。
