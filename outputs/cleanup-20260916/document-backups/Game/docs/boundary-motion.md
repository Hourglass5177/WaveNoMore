# 波浪分界线：连续卷流

基线：2026-09-15。正式背景使用 `scenes/presentation/boundary_waves.tscn`。关闭总动画仍显示原始 `edge.png`。

## 当前画面

中央两股厚浪围绕同一个判定区域顺时针卷入。入口下缘先平行接入水带，再平顺上行；厚度增加在上方。卷顶饱满，末端收成游离尖缘，左右固定 180° 中心对称。内外缘由三段三次 Bézier 曲线分别定义，中央留白由几何形成。

下层水坡保持连接，上层由有空腔、分叉和薄尖的浪唇组成。浪唇沿卷曲路径前进，伸出的尖缘与唇下空隙一起改变外轮廓；到末端收细，后面的继续跟上。不同大小的浪唇错开接替，内部色带、浪唇和细水的速度分别为 1、1.06、1.12 倍。拍点仅轻微提速，默认每拍前 0.4 拍平滑多前进 1.25 设计 px。

浪唇的横向映射将连接水坡略加厚，压低上层长尖，并让薄尖沿前进方向弯送，收拢过大的唇下开口。起势斜坡上的浪尖先贴水，到卷顶逐步展开。颜色与透明度共用映射，保留原素材的白边、细分叉和空腔，不填成实心外缘。此次修形沿用现有素材、曲线和绝对时间，不改变旋转速度或策划参数。

纵向高点在顶点阶段略微压低：距离水平中线 96 设计 px 以内保持原位置，外侧超出部分渐进压缩 18%，用 40 px 过渡接入。默认浪顶约降低 20 px，另一侧中心对称。内缘留白、浪根与原 UV 路程不缩放，旋转节奏及纹理相位沿用原值。

小浪保留每拍一对、三拍寿命、约 140 设计 px 前进，以及原来的 0.43 / 0.30 比例和上移 8 px。厚底带、凹凸走势及基底水流保留。

## 资源与绘制

`BoundaryVortexArm` 是两个独立材质的常驻 MeshInstance2D，每股 144 段、12 个横向分段。网格上侧留出 40% 空间承载翻出的浪唇，实际外缘由透明素材定义。网格只在内径或厚度改变时重建；逐帧仅更新三个有界纹理相位和细沫强度。另一股由父节点旋转 180°，共用曲线和路程。

- 曲线源：`src/presentation/parallax/boundary_vortex_arm.gd` 的 `edges()`。返回内缘和外缘，厚度调整只向外侧扩张。
- 材质：`shaders/materials/boundary_vortex.gdshader`，Compatibility 局部 canvas_item。
- 纹样：直接读取原有 `boundary_waves/water_band.png` 的色带与笔触。初次装配生成一张共享的 512×1 上下缘采样表，之后无逐帧图像生成。
- 浪唇：`boundary_vortex/crest_flow.png`，2172×724 透明补绘。以原始 edge.png 为风格参考，用内置 image_gen 生成；完整提示词保存在 `boundary_vortex/source/crest-flow.md`。原 PNG 与生成透明度保留，运行时收紧零星半透明噪点，空腔不填底色。
- 入口颜色：读取各自底带同位置的原色，在脚部短距离接合。透明边缘只作亚像素柔化，无圆形挖空。
- 中央派生底带：`boundary_vortex/water_band_split.png`，让水带在中央分流。
- 旧 `boundary_vortex` 图集、Spine 与 `build_vortex.py` 保留供历史对照，正式场景不再加载它们。当前轮廓由可编辑曲线生成，无需重新烘焙整套序列帧。

原纹循环为 640 设计 px，浪唇整条素材为 900 px，细沫间距为 235 px。素材在低水段短距离接合首尾，根部用预乘透明度与厚水坡接合，避免透明处黑色参与混色。主体没有统一明暗包络；浪唇与细水在卷流末端消退。三个相位均由绝对路程求模，暂停及定位不依赖累计帧数。

## 时钟与背景接入

`BoundaryMotion.vortex_distance_at(seconds)` 从歌曲绝对秒数和连续拍位求路程。TempoMap 提供浮点 tick；拍号分母决定每拍长度，换拍号累计前段拍数，不归零。轻微提速的位移及速度在拍点连续。小浪仍由 `BoundaryWaveSchedule` 直接枚举最近三拍，不重演历史。

`sample_background(seconds)` 沿用正式游戏、写谱预览、关卡编辑器、普通背景和环境换段的共用入口。位置、整体缩放、场景素材保存及撤销沿用背景条目。表现资源不进入 GameplayRuleSet 或 Replay 摘要，不使用 shader 内建 TIME。

基底水流仍由 `boundary_water_flow.gdshader` 在一次绘制中处理：Flow Map 双阶段短程搬运，默认 60 px/s、原纹混合 80%、细纹 24%。透明度按原 UV 保持，边缘固定；中央减弱的是颜色流动强度。关闭 `flow_enabled` 只冻结基底，中央卷流继续。参数见 [分界线表现](planning/07-分界线表现.md)。

## 审看与验证

独立入口：`tools/boundary_animation/review.tscn`，支持暂停、定位、BPM 和静态切换。

```text
godot --rendering-method gl_compatibility --script tests/integration/stage/run_boundary_waves_tests.gd
python tools/boundary_animation/verify_vortex.py
godot --rendering-method gl_compatibility --script tools/boundary_animation/capture_waves.gd -- --fps=60 --count=600 --folder=res://build/boundary-animation/vortex-flatter-final
python tools/boundary_animation/package_vortex.py --source=vortex-flatter-final --before=vortex-gather-refined --name=vortex-flatter
```

输出为原生 60 fps：完整画面、中央近景和上一版同刻对照均为 10 秒，覆盖完整浪唇素材周期。实际关内采样见 `vortex-flatter-stage/`。当前曲线、材质、浪唇原图及测试均在工程内可编辑。本轮不构建发行包。
