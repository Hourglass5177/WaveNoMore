# 红蓝 UI 火框

燃烧组件已接入正式游戏：设置与暂停使用红焰，选关卡片使用蓝焰。原始 PNG 保存在 `assets/ui/flame_frame/*_source.png`，审看场景继续复用同一组件。

## 画面与制作

两张输入的有效透明区域均为668×1324；蓝图额外留白在配准副本中去除。生成器从原画亮芯提取四边的火势分布，保留白芯、红紫/青蓝柔晕的配色层次。

火根固定附着在框边，以原画式的细窄曲线连接各簇。主火从窄根连续伸出，向上的两层噪声逐渐影响焰身和上部轮廓，形成拉长、卷动、裂开和尖端消退。没有整簇的升降、周期性淡入淡出或整体呼吸；固定八个附属火尖只承担少量逸散。

火根采用约52 px的分布单元，加上沿边错位和固定疏区；少数根部形成较大火簇，其余细短。根部位置和火势疏密保持稳定，运动集中在上方。两层流动使用不同尺度和速度，颜色与透明轮廓同步变化；柔晕由同一个密度场衰减得到。

底边使用约84 px的分布单元，焰身宽度为基础编排的235%、高度160%，并取消间隙补火，形成宽窄错落、留有空隙的火团。右侧下段仍在较大间隙补入68%的矮火，其余边保留疏区。火根沿边错位限制在边长以内。底火在1.5～2.35倍火势高度之间柔和消退，每条边独立限制向文字区的延伸；环带网格同步留足空间。

制作参考：[Real Time VFX 的火焰拆解](https://realtimevfx.com/t/simple-fire-shader-breakdown/11213)用于学习多尺度流动噪声和高度约束；[NVIDIA 火效说明](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-6-fire-vulcan-demo)用于参考源点与火焰的连续关系。网页素材仅作参考，未下载复用。保留本项目的配色和独立实现。

环带网格只有16个三角形，中央不着色；尺寸或火势高度改变时才重建。主火芯、彩焰和柔晕同一次绘制，附属火尖另一次绘制。四边在同一坐标中计算，角区不重复绘制。无需屏幕采样、全屏后处理或逐火框 SubViewport；录制工具的视口仅用于离线审看。

## 使用

组件：`src/presentation/ui/flame_frame_visual.gd`，挂载在独立 `Control` 上，`size` 表示燃烧根部的框尺寸。火舌以设计像素计算，改变框宽高不会拉伸火舌；整个设计画布可以整体缩放。允许绘制区域比框四周大2.4倍火势高度，父节点不要开启贴边裁切。

- `palette`：0红、1蓝；`random_seed`：每实例独立相位。
- `flame_height / speed / glow_strength`：默认48 / 90 / 1；工作簿目标为 `ui_flame`。
- `sample(seconds)`：显式绝对时间；同一时间和种子得到相同像素。
- `automatic=false`：交由宿主推进时间；默认自动播放，玩法暂停不冻结菜单，隐藏期间时间停止，重新显示继续。
- `apply_planning(report)`：应用已读取的策划参数，不在表现帧内访问工作簿。

打开 `tools/ui_flame/review.tscn` 可播放、暂停、定位、重置、切换背景、横框与原八帧对照。审看沿用真实 UI 底图和示例文字，不写入玩家存档。

横向弹窗底图右侧有额外透明留白；审看通过 `AtlasTexture` 按原图有效透明区域配准，再将可见底图与火根放在同一矩形中。原始图片保留，不能直接按含留白的整张图片宽度定位火框。

## 正式界面接入

- `src/app/ui/fire_frame.gd` 继承燃烧组件，设置与暂停场景的 `Fire` 改为 Control。按 `Panel` 原图的有效透明区域计算火根矩形，保留面板本身的位置和尺寸。跟随面板布局更新，菜单暂停时继续燃烧。
- 选关资源 `LevelCardEntry.flame_palette` 提供无／红焰／蓝焰；默认目录三张卡片使用蓝焰。火框按居中背景的可见区域及 `background_scale` 定位，不再套用旧帧动画的倍率和偏移。其他自定义 `SpriteFrames` 背景特效入口保留，开启燃烧框时替代帧动画。
- 轮播通过选中权重调整火焰透明度；权重归零时隐藏火框并停止采样。每张卡片独立保存种子、时钟及材质。设置、暂停沿用现有淡出和焦点流程，火框不接收鼠标或键盘焦点。
- shader 同时继承界面颜色和透明度，火芯、柔晕、逸散火尖一起退场。预乘 RGB 随 alpha 衰减；火尖编号与颜色分开，淡出不会改变运动轨迹。参见 [Godot CanvasItem 颜色定义](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html#color-and-texture)。
- 正式弹窗装载时读取现有 `ui_flame` 参数；一批轮播卡片共用一次读取。工程内使用策划表，发行程序沿用构建参数快照，默认值及策划当前值不变。

通过 `tools/ui/run_ui_review.ps1 -Suites art,carousel` 检查正式界面、真实暂停会话及轮播，626项通过。`tools/ui_flame/check.gd` 额外验证半透明像素与完全淡出无残留。接入截图保存在 `outputs/ui-flame/integration`；本次未重新构建发行程序。

## 重复生成与验证

```text
python tools/ui_flame/build_assets.py
godot --path . --editor --import --headless --quit
godot --path . --rendering-method gl_compatibility --script tools/ui_flame/check.gd
godot --path . --rendering-method gl_compatibility --script tools/ui_flame/benchmark.gd
godot --path . --rendering-method gl_compatibility --script tools/ui_flame/capture.gd -- --full --mode=0
godot --path . --rendering-method gl_compatibility --script tools/ui_flame/capture.gd -- --full --mode=1
godot --path . --rendering-method gl_compatibility --script tools/ui_flame/capture.gd -- --full --mode=2
python tools/ui_flame/package.py
python tools/ui_flame/package.py --details
python tools/ui_flame/package.py --verify
```

生成依赖 NumPy、Pillow；包装与运动检查使用 OpenCV、FFmpeg。FFmpeg 可通过环境变量 `FFMPEG` 指定，或将 `imageio-ffmpeg` 安装在忽略目录 `build/ui-flame/python-deps`。采样另支持 `--720 / --4k`。输出在 `outputs/ui-flame`，原生采样保存在忽略目录 `build/ui-flame`。

检查包括固定火根像素带不发生升降、上方火形持续变化、30秒显式时间推进、定位逐像素一致、暂停、重置、隐藏冻结、实例隔离、中央留白、网格复用、工作簿字段读取与原有值保留。录制视频为12秒60 fps，动图为12秒20 fps；光流方向检查和三处关键姿势图辅助人工检查生灭，不把通过数值检查等同于视觉认可。

性能以 Compatibility、1920×1080、本机 RTX 4060 的视口 GPU/CPU 时间戳测量。每组先预热120帧，再统计180帧；不含截图、编码或编译耗时。静态组使用同布局原画，五张静态可合批，新火框每实例独立材质。完整结果见 `outputs/ui-flame/performance.json`；本机数据不代表其他显卡。

| 布局 | 静态 GPU 中位 | 新火框 GPU 中位／P95 | 新增 GPU 中位 | 脚本 CPU 中位 | 新火框绘制次数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 一个大弹窗 | 0.053 ms | 0.163 / 0.173 ms | 0.110 ms | 0.012 ms | 2 |
| 五张卡片 | 0.052 ms | 0.386 / 0.397 ms | 0.334 ms | 0.030 ms | 10 |

新效果共享噪声、火势图和两张色阶，按RGBA8估算约262 KiB；不计审看底图及保留的原画。渲染线程CPU中位分别为0.102 / 0.136 ms，和脚本采样时间分开记录。本次GPU中位增量低于1 ms，完整分位数据保留在报告中。
