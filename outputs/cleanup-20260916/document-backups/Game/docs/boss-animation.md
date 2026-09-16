# BOSS 动画审看

2026-09-15。基于 `Assets/BOSS` 原始 Spine 3.8.75 导出，为蝙蝠、蛇、羊头及羊头眼球形态生成独立的 Spine 4.3.23 派生资源。完整表现现已可由关卡编辑器的 BOSS 属性选择，接入自动攻击、受击、阶段与死亡；本轮未构建发行程序。

## 打开与操作

先打开 [动画总览](../outputs/boss-animation/index.html) 浏览四套形态的演示；[状态总图](../outputs/boss-animation/all-states.png) 和 [死亡关键姿势](../outputs/boss-animation/death-poses.png) 用于静态比较。

Godot 打开 `tools/boss_animation/review.tscn`，运行当前场景。可以选择四种形态、开始或结束攻击、受击、转阶段、死亡、暂停、定位和重置。攻击持续段反复播放，结束请求等待当前一轮完成。普通羊头使用“转阶段”，完成后恢复操作；普通形态收到死亡请求也执行转阶段。最终死亡后只接受重置。“完整演示”连续播放羊头觉醒、真眼攻击与最终死亡。

“骨骼”显示没有光效的动作，“光效”隐藏主体。“正式背景”使用第三关墓葬背景；“中心对称”提供两侧构图，“判定参照”叠加静态 Tap、Hold 及判定圈尺寸参照。它们不是正式关卡的判定对象。

单体最长边以 560 设计 px 为基准。双侧审看为了完整展示火焰和碎片，主体缩至 62%；正式 BOSS 的出现位置和游戏事件本轮未配置。

## 动作与光效

| 形态 | 常态 | 蓄势 | 持续循环 | 收招 | 受击 | 死亡 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 蝙蝠 | `feixing` | 0.45 s | 1.2 s | 0.55 s | 0.38 s | 3.2 s |
| 蛇 | `animation` | 0.55 s | 1.6 s | 0.65 s | 0.45 s | 3.6 s |
| 羊头一阶段 | `animation` | 0.60 s | 1.6 s | 0.50 s | 0.42 s | 3.0 s 转阶段 |
| 羊头真眼形态 | `animation` | 0.60 s | 1.6 s | 0.50 s | 0.42 s | 7.0 s |

新增动画统一为 `attack_start / attack_loop / attack_end / hurt / death`。原始基础动画也保存在派生 JSON 中。

- 蝙蝠挺胸展翼，胸口每 0.6 s 发出主光波，双翼晚 0.10 s 释放副波。每次发射记录当时的纹样位置，已经离体的波不会拖着跟随翅膀。
- 蛇的三口火依次开始，年龄跨过持续段循环边界，结束时依次衰减。**喷口分别绑定上下唇的加权网格，取两唇之间的位置**，喷吐方向也随骨骼旋转。左首朝左下、右首朝右外、中央首向上展开。
- 羊头使用三张独立眼部亮层，复制对应眼部附件的 UV、三角形、骨骼权重和变形时间线。额眼的两种拓扑分别保留。**手部、飘带和角骨不使用全身提亮**；眼区周围只有局部柔晕。
- 受击使用独立叠加轨道，同侧动作未结束时忽略重复表现请求；基础轨道持续推进。死亡用 0.10 s 混合接管，旧光波与火焰短暂退去。
- 死亡先完成主体动作，再由固定数量的纹样碎片接替。蝙蝠向两翼散开，蛇从三首向下崩解。羊头的两阶段时序见下文。碎片贴图在生成阶段烘焙，运行时不截图、不重建整张网格。

### 羊头觉醒与最终死亡

二阶段死亡从接管动作起保持三眼白光，直到眼部骨片完全消散。精确眼罩与柔晕在2.1秒交接给同一裂解网格，随各自骨片一起移动；不再先熄眼，也不在原骨骼位置留下固定光点。`death_eyes.png` 为同姿势眼罩采样，生成器将其整理为 `death_eye_map.png`，与原色主体分开保存。

一阶段 `phase_break`：0～0.45秒低头失力，0.45～1.05秒额眼表层出现裂光，1.05～1.85秒六片表层向外剥落，显露真实眼球。1.85～2.65秒眼球短暂偏转、瞳孔收紧后凝视；2.65～3秒收稳并以0.15秒混合进入真眼常态。两侧眼睛在1.05～1.70秒同步渐亮为白色，保持至2.65秒，再于3秒前熄灭；额眼始终保留虹膜和瞳孔。转阶段期间忽略重复动作请求。

二阶段 `death`：0～0.7秒失力，0.7～2.1秒上升70设计像素；裂光从额眼向面骨、角根蔓延。2.1秒交给同姿势烘焙的34块骨片；2.1～3.8秒逐渐拉开，九束光从实际裂缝依次射出；3.8～4.8秒进一步分离，4.8～5.15秒爆发。白场5.15～5.65秒保持纯白，5.65～6.65秒退去；大块骨片在白场期间退尽，余烬至7秒完全消失。白场在画布层取各实例最大值，控件保持可见。

两形态使用同一派生骨架的 `goat / goat_eye` 皮肤，分别保留源附件UV、权重及三角形；16顶点图案眼与56顶点真眼不相互插值。六片表层采用原图网格和独立子骨骼；真眼与眼罩的局部修形同步。光束位置与骨片运动共用同一切分数据，手部和飘带不使用全身提亮。

三个外部倍率见 [BOSS 表现参数](planning/09-BOSS表现.md)。它们默认均为 1，不参与玩法规则及 Replay 哈希。

## 素材与再生成

`assets/bosses/animation_studies/<形态>/` 包含 `boss.spine-json`、`boss.atlas`、原图集副本、拆件 PNG、眼罩及 `death_pose.png`。JSON 可重新导入匹配版本的 Spine 编辑；它不是原始 `.spine` 二进制工程的替代备份。

转换器按实际使用的 3.8 时间线转换旋转字段、骨骼继承、归一化 Bézier、加权 deform 和图集信息。曲线按 120 Hz 采样并保留关键时间与阶跃边界；新动作按 60 Hz 编排，由 Spine 连续插值。没有只改版本号冒充转换。

从 `Game` 执行，`python` 和 `godot` 分别指本机 Python 与带当前 Spine 扩展的 Godot 4.7.2：

```text
python tools/boss_animation/build_bosses.py
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd -- --bake
python tools/boss_animation/package_previews.py --prepare-bakes
python tools/boss_animation/goat_phases.py
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd
python tools/boss_animation/package_previews.py
```

只更新羊头时执行以下命令。指定任一羊头形态都会同时生成两套皮肤：

```text
python tools/boss_animation/build_bosses.py --id goat
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd -- --id=goat_eye --bake
python tools/boss_animation/package_previews.py --prepare-bakes --id goat_eye
python tools/boss_animation/goat_phases.py
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd -- --id=goat --clip=phase_break
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd -- --id=goat_eye --clip=death
godot --path . --rendering-method gl_compatibility --script tools/boss_animation/capture.gd -- --id=goat --clip=two_phase
python tools/boss_animation/package_goat_phases.py
```

`--prepare-bakes` 紧跟每次新烘焙执行一次，将透明渲染的预乘颜色转换为普通透明贴图。不要对同一张已转换的贴图重复执行。

骨骼播放器、固定光波/火焰网格、显式时间采样位于 `src/presentation/actors/boss_visual.gd`，审看脚本继承该正式实现。关卡适配层为 `level_boss_visual.gd`；光效源码位于 `shaders/bosses/`。播放器直接加载生成的 JSON、Atlas 和源 PNG，导出配置包含这些原始依赖。

## 检查与输出

- `check_playback.gd`：连续播放与定位骨骼误差小于 0.01 px，检查受击恢复、重复请求、结束边界、死亡优先、暂停及重置；读取工作簿三个倍率。
- `capture_base.gd` + `verify_assets.py`：独立读取原始 3.8 曲线，对照七个时间点的原生骨骼变换。当前最大分量误差约 0.014；原始网格、UV、三角形保留，眼部亮层变形与原眼一致。
- `capture.gd -- --audit` + `package_previews.py --audit`：采样转头及受击姿势。两种羊头各四个姿势，开启/关闭眼光的眼区外像素差为零。喷火根部需要结合输出图逐帧目检，不能仅凭锚点坐标相等判断贴合。
- `capture_review.gd`：在 Compatibility 下输出四形态的 1920×1080、1280×720 背景审看图，脚本核对实际图像尺寸。
- `check_review_layers.gd`：单独显示光效时保留三眼网格，手部区域透明；切换回完整视图后逐像素恢复。
- `verify_delivery.py`：逐帧解码状态、组合与羊头新增演示，核对60 fps、帧数及GIF时长，抽查画布边缘和死亡末帧。`--goat` 只检查本轮五个新增或更新的视频链接，并验证纯白保持与转阶段后主体仍可见。
- `check_goat_phases.gd`：转阶段优先级、第二阶段恢复操作、侧眼亮度、定位/暂停/重置、光束位置和0.5秒白场。
- `capture_goat_handoff.gd`：在2.1秒交接点关闭光效，对比骨骼与固定分块的实际渲染。
- `capture_goat_review.gd`：正向/中心对称、两分辨率的揭眼、裂光、纯白和结束画面。

`outputs/boss-animation` 保存 60 fps WebM、30 fps GIF、全部状态图、死亡关键姿势图和喷口/眼罩对照图。`build/boss-animation` 保存原生 60 fps 透明 PNG 采样。攻击演示包含两轮持续段；`combo` 演示攻击中受击。

羊头新增 `goat-phase_break`、`goat-two_phase` 与 `goat-eye-closeup` 演示；`goat_eye-death` 为7秒最终死亡。`goat-death` 旧链接对应一阶段觉醒，不再播放主体消失。裂解期画布边缘允许光束离开画面，最终白场覆盖整幅画面。

此审看没有运行正式 BOSS 技能结算，也不构成正式关卡遮挡或性能的最终验收。后续集成应根据真正的 BOSS 出现位置检查火流与音符的重叠。
