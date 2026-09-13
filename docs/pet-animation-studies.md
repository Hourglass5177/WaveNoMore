# 三只随从动画审看

更新：2026-09-13。蝠漆漆、苹果蛇、羊头仔各有 `idle / trigger / death` 三条动作。本轮交付独立素材和审看入口，正式随从配置与技能结算保持原状。

## 审看入口

在 Godot 打开 [`review.tscn`](../scenes/tools/pet_animation/review.tscn)，运行当前场景。提供播放、暂停、时间定位、技能、死亡、重置；可选 80 px、120 px 和放大查看，以及深浅背景。上下两侧按画面中心旋转对称。

“技能”播放一次完整短动作，期间的重复触发不重启、不排队；结束以 0.08 秒混合回到原常态相位。死亡用 0.12 秒接管当前姿态，之后不再接受技能。回拖后触发新事件会替换后面的审看历史。空间键切换播放与暂停。

动图、九条动作的关键姿势图、正式背景截图位于 [`build/pet-animation/`](../build/pet-animation/)：

- `three-pets.gif`：三只并排的常态、技能与死亡演示，使用实际 Spine 过渡采样。
- `bat-states.gif / snake-states.gif / sheep-states.gif`：每只随从的三状态演示。
- `{bat,snake,sheep}-{idle,trigger,death}.gif`：九条独立动作。
- 同名 `-poses.png`：九张关键姿势图。
- `stage-80-*.png / stage-120-*.png / stage-1280.png`：正式背景、双侧与不同尺寸。
- `review-1920.png / review-1280.png`：审看界面。
- `source-comparison.png`：原画与骨骼基准姿势对照。

`build/` 是忽略目录，动图和逐帧采样可通过脚本重新生成。

## 动作与分件

| 素材 | 常态 | 技能 | 骨骼 / 分件 |
| --- | --- | --- | --- |
| 蝠漆漆 `bat` | 1.2 秒，缓慢回翼、较快下拍，身体上下约 2 px | 0.6 秒，先收翼再展翼，上提约 3 px，胸口圆纹略亮 | 8 根 / 6 件；身体、双翼、双耳尖、尾端 |
| 苹果蛇 `snake` | 3.2 秒，三首依次摆动，颈部、盘曲身体与尾部错开；摆幅约为首版两倍 | 0.8 秒，中间头先抬，两侧依次舒展并喷出短促小火；展颈约 10°、上提约 3.3 px，腹纹略亮 | 10 根 / 4 件；后侧两颈、身体、前侧蛇颈，头与尾有独立骨骼 |
| 羊头仔 `sheep` | 3.6 秒，悬浮约 2.5 px，头角轻歪，小手与绒团跟随 | 0.6 秒，低头合手，绒毛稍晚舒展，最大放大 2.5% | 6 根 / 5 件；头角整体、绒毛、双手、小绒团 |

位移以常态原画最长边约 80 px 为基准。羊角与头部共用刚性变换；蝠面部保持整体；蛇颈按原画遮挡顺序绘制。技能不增加眼睛或面部表情，不另添图案。

死亡分为三段：0～1.2 秒收拢、失力并下沉约 6 px；1.2～1.4 秒保持末姿；1.4～2.05 秒化为原色薄片与灰点。漂移约 10 px，完全结束后隐藏。骨骼末姿与灰烬交接位置相同，死侧随整体旋转而向其地面方向下沉。

苹果蛇按审看反馈加大了三条动作：常态和技能的主要摆幅约翻倍；死亡展现更明显的低头与蜷尾，下沉改为 8 px。中颈的权重过渡延长，主要靠弯曲呈现低垂，减少纵向挤压。三首错开的节奏、动作时长、画布与灰烬时序沿用首版。

技能喷火：中间、右、左三首分别在 0.18 / 0.26 / 0.32 秒开始，每口约 0.44 秒，长度约 8 / 10 / 9 个设计像素。点火与熄灭保留原来的速度，中段稳定喷吐延长；三口火依次在 0.62 / 0.70 / 0.76 秒结束。橙红外焰、浅金内焰，末尾带两粒很小的余烬。中间头沿原舌头的方向向下喷，避开右侧蛇颈。火焰与嘴部共用绑定权重，随姿态、比例和所属世界旋转；死亡立即打断，常态没有火焰。

## 可编辑资源

源图来自仓库外层 `Assets/随从宠物原画/` 的三张彩色 PNG。原文件不改写；同名影子图本轮没有使用。派生目录为 [`assets/pets/animation_studies/`](../assets/pets/animation_studies/)，每只包含：

| 文件 | 用途 |
| --- | --- |
| `original.png` | 原始彩色图的完整副本 |
| `parts/*.png` | 保留笔触的分件，可继续补绘连接处 |
| `pet.spine-json` | Spine 4.3 数据，包含骨骼、权重、网格、绘制顺序和三条源动画，可导入 Spine 编辑 |
| `pet.atlas / atlas.png / pet.tres` | 当前 Godot Spine 运行时资源 |
| `animation.json` | 显示比例、原点、动作长度和局部提亮区域 |
| `death_pose.png` | 灰烬阶段使用的透明末姿，可从骨骼重新烘焙 |
| `*_sheet.png / frames.tres` | 30 fps 透明图集和 Godot `SpriteFrames` |

分件以原画为基础。羊头仔绒毛在头与手遮挡的连接处有少量颜色补齐；网格仅保留覆盖图像的三角面。权重和动作由 [`build_pets.py`](../tools/pet_animation/build_pets.py) 生成。修改该脚本可重建整套素材；直接在 Spine 或 PNG 中手改的内容，应另存后再运行生成器，避免被派生输出覆盖。

源骨骼的死亡动画长 1.4 秒；最后 0.65 秒由 [`pet_study_ashes.gdshader`](../shaders/characters/pet_study_ashes.gdshader) 控制。它复用现有音符碎片的固定网格，保留独立的颜色、渐隐与漂移参数，不需要逐帧生成网格或运行粒子物理。

苹果蛇的喷火由 [`snake_breath.gd`](../src/tools/pet_animation/snake_breath.gd) 和[同名 shader](../shaders/characters/snake_breath.gdshader) 组成。嘴部绑定、方向、开始时间、长度保存在 `animation.json` 的 `breath` 中；三张共用网格的小面片使用显式年龄绘制，因此暂停、回拖和直接定位不依赖粒子模拟历史。透明 `trigger_sheet.png` 已包含喷火，Spine 源动画与火焰源分别保留。

透明图集固定每帧 512×512，原画基准最长边 320 px，8 列排布。`AnimatedSprite2D` 使用 `frames.tres` 时缩放 0.25，对应约 80 px；所有动作共享同一画布和原点。常态循环，技能与死亡不循环。死亡第 61 帧使用半帧时长，第 62 帧从 2.05 秒起完全透明，非循环播放器停在末帧时也不会留下灰点。

审看节点 [`pet_study_actor.gd`](../src/tools/pet_animation/pet_study_actor.gd) 由调用方提供时间和事件。骨骼不含物理约束；定位重建事件对应的轨道，短混合段以 120 Hz 推进，避免 Spine 嵌套角度混合的历史方向差异。该节点用于素材审看，未装配到正式 `PetVisual`。

## 重新生成

以下命令在 `Game` 内运行，`python` 需要 Pillow、NumPy，`godot` 指向带当前 Spine 扩展的 Godot 4.7.2。图像采样命令使用 Compatibility 实际渲染，不能换成 headless。

```powershell
python tools/pet_animation/build_pets.py
godot --headless --path . --editor --import --quit
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/render_pets.gd -- --death-poses
godot --headless --path . --editor --import --quit
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/render_pets.gd
godot --headless --path . --editor --import --quit
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/capture_review.gd
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/capture_review.gd -- --stage
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/capture_review.gd -- --ui
godot --path . --rendering-method gl_compatibility --script tools/pet_animation/capture_review.gd -- --baseline
python tools/pet_animation/make_previews.py
```

源 PNG、网格与动作先生成，再烘焙死亡末姿，最后采样含灰烬的图集。不要交换这几个步骤。GIF 受格式限制，以 30 / 30 / 40 ms 帧时长交替保持平均 30 fps；透明 PNG 保留完整 RGBA。

仅调整苹果蛇时，生成器可加 `--pet=snake`，`render_pets.gd` 的用户参数也可加 `--pet=snake`；省略则处理三只。死亡末姿烘焙示例：`godot --path . --rendering-method gl_compatibility --script tools/pet_animation/render_pets.gd -- --death-poses --pet=snake`。

## 本轮验证

```powershell
godot --headless --path . --script tests/integration/pets/run_pet_animation_study_tests.gd
python tools/pet_animation/validate_assets.py
```

- 98 项播放与资源检查通过：循环首尾、密集技能、技能回常态、死亡打断、原生逐步推进与定位、暂停、重置、两界布局以及图集时长；含喷火的三首错时、延长持续与依次熄灭、定位恢复、中心对称、死亡打断与离线采样。
- 489 张实际渲染帧和 2109 组网格姿态通过检查。苹果蛇增幅后，保留三角面的最小面积比例为基准的 0.302，没有翻面；导出画布最小透明边距 50 px，约合 12.5 个设计像素。
- 三只随从 1.4 秒交接前后的透明度逐像素一致；2.05 秒末帧完全透明。原图副本与输入文件相同。
- 在 Compatibility 下采样了中性背景、正式背景、80 / 120 px、1920 / 1280 宽度和中心对称双侧。检查翅根、蛇颈遮挡、羊角刚性、绒毛连接及灰烬末帧。

原画黑色蝠身在最深的柱面上会与背景贴近，黄色与玫红纹样仍可辨；正式接入时需要结合随从摆位检查。羊头仔的浅色绒毛在当前深色背景上轮廓清楚。

后续确认动作后，再将动画接入正式随从。苹果蛇基础形态目前没有独立的技能触发通知，需要在正式接入时明确通知时机。本轮不修改技能描述、判定、扣血或 Replay，不构建发行程序。
