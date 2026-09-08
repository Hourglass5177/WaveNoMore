# 随从系统

本轮实现位于 `pet` 分支，基于 `develop@ca2d574`。以下规则对应当前工程，替代旧文档中“随从不改变判定”和整曲结算加分的描述。

## 规则

单槽装备。正式关卡的 FC 奖励基础形态，AP 奖励进阶形态；首次 AP 同时取得所有权。进阶替换基础，重复奖励不降级。三只随从已登记到 `content/catalogs/mvp_catalog.tres`，现有测试关仍不发随从奖励。

| 随从 ID | 名称 | 基础 | 进阶 |
| --- | --- | --- | --- |
| `nu_tu_fu` | 女土蝠 | Perfect 得分 +2% | Perfect 得分 +3% |
| `gui_jin_yang` | 鬼金羊 | 受伤减免 10% | 受伤减免 20% |
| `yi_huo_she` | 翼火蛇 | 普通 Hold 起手各档窗口 +10 ms，断持宽限 +20 ms | 相同宽限，整条 Hold 最终判定提高一级 |

女土蝠以每条 Perfect 实际获得的基础分为基数，包含 Combo 倍率；将这些分数累计后计算并四舍五入总奖励。实时分数为 `raw_score + bonus_score`，结算和存档直接使用计分器结果。

鬼金羊对每个伤害事件减免后四舍五入，同一 `damage_group_id` 只处理一次。默认 20 点伤害变为 18 / 16 点。正常模式魂火最低为零，因此致死事件的 `actual_damage` 是实际损失的剩余魂火；非致死调试模式允许负魂火。

翼火蛇两种形态的起手 Perfect / Good / Pass / Miss 窗均为 55 / 100 / 145 / 190 ms，断持宽限为 120 ms。沿用原规则：主动输入只接受到 Pass 窗，Miss 窗用于无人起手的超时结算。窗口端点包含在内，断持或头部超时在下一微秒生效。Hold 到尾点自动完成，没有松手判定。Tap、调频及素音不受该技能影响。

进阶在最终记录形成时提档一次：Miss → Pass → Good → Perfect，Perfect 封顶。未按、断持均适用。分数、Combo、判定统计、FC / AP 使用最终等级；伤害仍由实际失误决定。漏按 Hold 可以获得 Pass 和 Combo，然后在抵达角色时受伤；通关后可以是 FC，魂火耗尽则仍失败。

## 装配和数据流

- `PetDefinition` 保存身份、文案、基础 / 进阶两份 `PetEffectProfile` 和美术资源。各模块读取参数，不按随从 ID 分支。
- `AppMain` 首次进入关卡时固定装备和形态，重试沿用，返回选择页面后重新读取。`StageRoot.set_pet()` 在 `load_stage()` 前传入本局配置。
- `StageSession → GameplayCoordinator → GameplaySimulation` 传递技能参数。Simulation 复制配置；判定器不读取菜单、存档和美术节点，不修改共享 `GameplayRuleSet`。
- `NoteJudgeEngine` 负责候选搜索、起手等级、头部超时和断持宽限。`JudgmentRecord.base_grade` 保留机械等级，`grade` 为最终得分等级，`components` 保留实际输入或超时采样、持续失败及失焦分量。
- `GameplaySimulation` 在统一收集最终记录时应用提档。`ScoreEngine` 计算 Combo 和奖励分，`ResultEvaluator` 使用最终等级汇总。
- `DamageRecord` 记录来源、伤害组、歌曲微秒、原始伤害和实际伤害；Simulation 生成，HealthEngine 消费。正式玩法不再从最终得分等级推断扣血。

普通音符未有效起手的伤害发生在 `WaveInteractionEngine` 算出的抵达时刻；成功起手后断持在失败时刻受伤。调频等其他机制保留原结算时刻，乱按按规则开关扣血。所有伤害经过同一个减伤与去重入口。

时间推进包含头部超时、Hold 尾点、断持失败与待发生的抵达事件。每个边界先计算物理事件和各判定器状态，再按时间、机制类型、单位 ID 稳定收集判定并处理即时伤害，最后按时间、阵营、音符 ID 处理抵达伤害。同刻调频端点仍先于 Hold 退出计算。输入重演沿用“端点前推进 → 同刻输入 → 包含端点推进”的顺序。致死后停止新增成绩，已发出的波继续完成表现；尚有抵达伤害时不宣布通关。

`StageSession` 向音符表现传机械等级，向判定文字传最终等级。表现不反向扣血。领域重演可传 `ReplayRunner.run(compiled, rules, replay, frame_step_us, pet_effect)`；本轮没有恢复真人 Replay 录制 / 回放。

## 菜单、存档和测试入口

选关页打开“随从”，可装备、卸下，使用现有 `ui_*` 键盘 / 手柄导航。页面显示所有权、形态、两档效果及装备状态。技能描述逐字使用用户确认的原文，不自行润色或追加解释；数值细则保留在程序配置与本文规则中。弹窗打开期间底层页面退出焦点导航，关闭后恢复打开前的焦点。

歌曲目录应跟随手柄上下切换的焦点滚动，保证当前歌曲可见；美术重做目录时继续保留这一交互原则。

编辑器运行或 Debug 构建中显示“开发”按钮。“测试基础 / 测试进阶”会授予对应随从并装备，保存获得状态；测试形态只在本进程临时覆盖。“结束测试”清除临时覆盖，回到存档中的最高形态。Release 构建不显示这些控制。

沿用存档 `pets[id].owned / advanced` 和 `equipped_pet_id`。旧 `horned_soul` 历史记录保留，不兑换，已失效的装备按未装备解析。正式奖励仍由 `StageDefinition.reward.pet` 与奖励开关配置。

正式关卡和本地谱面均应用装备；本地谱面只保存本地成绩，不授予正式随从奖励。写谱器内嵌预览与一键试玩默认没有随从，重试同样保持空配置。结算携带本局随从名称、ID、形态和附加分。

## 美术替换

白盒 SVG 位于 `assets/pets/`，128 × 128，中心为轮廓基准；三个轮廓分别是蝠翼、羊角和蛇形。菜单使用 `base_icon / advanced_icon`，保持纵横比。进阶图未配置时使用基础图。

局内入口是 `PetDefinition.base_scene / advanced_scene`，默认场景为 `scenes/presentation/pets/pet_visual.tscn`。表现层在两个角色槽下各建立一个 `PetAnchor`；二者共用技能结果，不重复计算效果。锚点继承角色所在世界变换，死界旋转 180°。`world_offset` 使用 1920 × 1080 设计坐标，相对生界角色默认 `(-96, 70)`；`world_scale` 控制整体尺寸。

替换方式：

1. 静态局内立绘：复制默认局内场景，给根节点 `PetVisual.texture` 设置独立贴图，调整 `display_size`（默认 80 × 80）。不设置 texture 时才回退菜单图。
2. 帧动画：配置 `PetVisual.frames`，使用 `idle` 和可选的 `trigger` 动画。原点居中，所有帧采用相同画布与对齐基准，透明边距尽量一致。待机是否循环、帧速度和单帧时长由 SpriteFrames 配置；触发按动画总时长完整播放，结束后回到待机，缺少 trigger 时继续待机。
3. 自定义表现场景：根脚本继承 `PetVisual`，重写 `bind(pet, advanced)` 和 `set_state(song_time, trigger_us)`。只读取配置与时间，不计算技能、不访问存档。内部可以自行组织多个 Sprite2D 或其他表现节点。

默认静态白盒有轻微浮动及技能触发脉冲。所有随从动画直接采样歌曲时间，不靠 `_process`、Tween 或动画播放器自行累计；暂停停在当前姿态，定位 / 重试从当前领域状态重建。自定义场景也应遵守这条时钟约定。

## 验证

运行方式（在 Game 下，把 `godot` 替换成本机 Godot 4.7.2 可执行文件）：

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/integration/pets/run_pet_tests.gd
godot --headless --path . --script res://tests/integration/save/run_save_tests.gd
godot --headless --path . --script res://tests/integration/stage/run_develop_merge_tests.gd
godot --headless --path . --script res://tests/editor/run_preview_frame_tests.gd
godot --headless --path . --script res://tests/editor/run_trial_flow_tests.gd -- --play-chart res://builds/trial-flow-input.zip
```

随从测试覆盖四档窗口及断持边界内外 1 微秒、短 / 双侧 Hold、暂停重臂、一次提档、伤害组、致死与非致死、不同帧步、领域重演、存档、菜单和真实 StageRoot。去掉 `--headless` 可检查实际渲染，并输出截图到 `builds/pet-review/`。

本轮测试结果与既有失败记录见 [随从系统验证记录](pet-validation.md)。
