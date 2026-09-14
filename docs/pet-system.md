# 随从系统

更新：2026-09-14。三只随从已使用彩色原画图标和骨骼动画；技能结算沿用现有参数。

## 规则

单槽装备。正式关卡的 FC 奖励基础形态，AP 奖励进阶形态；首次 AP 同时取得所有权。进阶替换基础，重复奖励不降级。三只随从已登记到 `content/catalogs/mvp_catalog.tres`，现有测试关仍不发随从奖励。

| 随从 ID | 名称 | 基础 | 进阶 |
| --- | --- | --- | --- |
| `nu_tu_fu` | 蝠漆漆 | Perfect 得分 +2% | Perfect 得分 +3% |
| `gui_jin_yang` | 羊头仔 | 受伤减免 10% | 受伤减免 20% |
| `yi_huo_she` | 苹果蛇 | 普通 Hold 起手各档窗口 +10 ms，断持宽限 +20 ms | 相同宽限，整条 Hold 最终判定提高一级 |

蝠漆漆以每条 Perfect 实际获得的基础分为基数，包含 Combo 倍率；将这些分数累计后计算并四舍五入总奖励。实时分数为 `raw_score + bonus_score`，结算和存档直接使用计分器结果。

羊头仔对每个伤害事件减免后四舍五入，同一 `damage_group_id` 只处理一次。默认 20 点伤害变为 18 / 16 点。正常模式魂火最低为零，因此致死事件的 `actual_damage` 是实际损失的剩余魂火；非致死调试模式允许负魂火。

苹果蛇两种形态的起手 Perfect / Good / Pass / Miss 窗均为 55 / 100 / 145 / 190 ms，断持宽限为 120 ms。沿用原规则：主动输入只接受到 Pass 窗，Miss 窗用于无人起手的超时结算。窗口端点包含在内，断持或头部超时在下一微秒生效。Hold 到尾点自动完成，没有松手判定。Tap、调频及素音不受该技能影响。

进阶在最终记录形成时提档一次：Miss → Pass → Good → Perfect，Perfect 封顶。未按、断持均适用。分数、Combo、判定统计、FC / AP 使用最终等级；伤害仍由实际失误决定。漏按 Hold 可以获得 Pass 和 Combo，然后在抵达角色时受伤；通关后可以是 FC，魂火耗尽则仍失败。

## 装配和数据流

- `PetDefinition` 保存身份、文案、基础 / 进阶两份 `PetEffectProfile` 和美术资源。各模块读取参数，不按随从 ID 分支。
- `AppMain` 首次进入关卡时固定装备和形态，重试沿用，返回选择页面后重新读取。`StageRoot.set_pet()` 在 `load_stage()` 前传入本局配置。
- `StageSession → GameplayCoordinator → GameplaySimulation` 传递技能参数。Simulation 复制配置；判定器不读取菜单、存档和美术节点，不修改共享 `GameplayRuleSet`。
- `NoteJudgeEngine` 负责候选搜索、起手等级、头部超时和断持宽限。`JudgmentRecord.base_grade` 保留机械等级，`grade` 为最终得分等级，`components` 保留实际输入或超时采样、持续失败及失焦分量。
- `GameplaySimulation` 在统一收集最终记录时应用提档。`ScoreEngine` 计算 Combo 和奖励分，`ResultEvaluator` 使用最终等级汇总。
- `DamageRecord` 记录来源、伤害组、歌曲微秒、原始伤害和实际伤害；Simulation 生成，HealthEngine 消费。正式玩法不再从最终得分等级推断扣血。

Tap 未有效起手的伤害发生在 `WaveInteractionEngine` 算出的抵达时刻。Hold 漏头或断持后，未消耗身体按音乐拍长逐段抵达、逐段受伤，不额外结算整条伤害。默认每 1/4 拍 2 点，随从仍对每段分别减伤取整（2 点乘 90% 或 80% 后仍为 2）。Tuning 自身不扣血，Ghost 按关联调频完成情况判断，漏击按每枚 10 点结算；预测交点不足不作为扣血依据。空按按独立开关和伤害值处理。所有伤害经过同一个减伤与去重入口。

时间推进包含头部超时、Hold 尾点、断持失败与待发生的抵达事件。每个边界先计算物理事件和各判定器状态，再按时间、机制类型、单位 ID 稳定收集判定并处理即时伤害，最后按时间、阵营、音符 ID 处理抵达伤害。同刻调频端点仍先于 Hold 退出计算。输入重演沿用“端点前推进 → 同刻输入 → 包含端点推进”的顺序。致死后停止新增成绩，已发出的波继续完成表现；尚有抵达伤害时不宣布通关。

`StageSession` 向音符表现传机械等级，向判定文字传最终等级。表现不反向扣血。领域重演可传 `ReplayRunner.run(compiled, rules, replay, frame_step_us, pet_effect)`；本轮没有恢复真人 Replay 录制 / 回放。

## 菜单、存档和测试入口

选关页打开“随从”，可装备、卸下，使用现有 `ui_*` 键盘 / 手柄导航。页面显示所有权、形态、两档效果及装备状态。技能描述逐字使用用户确认的原文，不自行润色或追加解释；数值细则保留在程序配置与本文规则中。弹窗打开期间底层页面退出焦点导航，关闭后恢复打开前的焦点。

歌曲目录应跟随手柄上下切换的焦点滚动，保证当前歌曲可见；美术重做目录时继续保留这一交互原则。

编辑器运行或 Debug 构建中显示“开发”按钮。“测试基础 / 测试进阶”会授予对应随从并装备，保存获得状态；测试形态只在本进程临时覆盖。“结束测试”清除临时覆盖，回到存档中的最高形态。Release 构建不显示这些控制。

沿用存档 `pets[id].owned / advanced` 和 `equipped_pet_id`。旧 `horned_soul` 历史记录保留，不兑换，已失效的装备按未装备解析。正式奖励仍由 `StageDefinition.reward.pet` 与奖励开关配置。

正式关卡和本地谱面均应用装备；本地谱面只保存本地成绩，不授予正式随从奖励。写谱器内嵌预览与一键试玩默认没有随从，重试同样保持空配置。结算携带本局随从名称、ID、形态和附加分。

## 正式动画与美术接入

三只随从的 `base_scene` 分别指向 `scenes/presentation/pets/bat.tscn`、`snake.tscn`、`sheep.tscn`，基础和进阶共用当前动画。菜单图标使用 `assets/pets/animation_studies/*/original.png`；内部 ID、解锁记录和技能描述保持不变。可编辑资源、分件和生成方式见[随从动画素材](pet-animation-studies.md)。

`PetAnchor` 位于现有角色槽内，`PetDefinition.world_offset` 默认 `(-136,70)`，使用 1920×1080 设计坐标；`world_scale=1.5` 时原画最长边约 120 px。生界在主角左侧胸腹附近，死界继承角色槽 180° 旋转，出现在主角的屏幕右侧。随窗口整体等比缩放，悬浮由动画完成，锚点固定。

两侧独立实例化 `src/presentation/pets/animated_pet_visual.gd`，同用歌曲时间的常态相位。死界骨骼、火焰和灰烬各自持有材质，共用 `pet_world_color.gdshaderinc`：`death_desaturation=1`、`death_brightness=0.65`，可在随从场景 Inspector 调整，不改透明度。

### 技能及死亡事件

| 随从 | 技能动画触发条件 | 来源侧 |
| --- | --- | --- |
| 蝠漆漆 | `ScoreEngine.bonus_score` 实际增加 | `JudgmentRecord.affinity` |
| 苹果蛇 | 两种形态均在有效新接住 Hold 的起手绑定时触发 | 绑定 Hold 的阵营 |
| 羊头仔 | 非致命伤害中实际损失小于原始伤害；取整后没有减伤不触发 | `DamageRecord.affinity` |

苹果蛇漏接、续按和暂停重臂不触发，进阶最终提档不追加动画。喷火仍按中、右、左首依次开始，每口 0.75 秒。技能正在播放时拒绝同侧再次触发，不重启、不排队；结束以 0.08 秒混合回歌曲时间对应的常态相位。

`GameplaySimulation.drain_pet_triggers()` 返回 `{timestamp_us, affinity}`，协调层转发 `pet_triggered(timestamp_us, affinity)`。`StageRoot` 合并同帧收到的技能和致命伤害，按原始时间排序，再分发给所属侧；`SU` 同时分发双方。同刻死亡优先，不保留零时长的技能混合。事件只驱动表现，不进入判定、计分和 Replay 摘要。

致命伤害让双方同时以 0.12 秒接管当前姿态；失力、下沉后在 1.4 秒切到灰烬，2.05 秒完全隐藏。复用当前 2.1 秒失败表现等待。正常通关、主动退出和非致命调试伤害不播放死亡。

### 时钟和替换接口

正式关卡与审看复用同一个播放器和喷火控制，正式场景不依赖 `src/tools`。播放器继承 `PetVisual`，提供 `bind(pet, advanced)`、`set_world(affinity)`、`trigger(song_seconds)`、`die(song_seconds)`、`clear_events()` 和 `set_state(song_seconds)`。骨骼直接采样可用 `sample()`，单条离线素材采样用 `sample_clip()`。

正常播放仅推进新增时间、消费新事件；短混合段细步推进，避免 Spine 角度混合改变转向。暂停冻结，倒计时使用同一常态相位，重试清空状态，定位按现有会话重演恢复事件、混合、喷火与灰烬。不会每帧从头重播历史，也不逐帧创建网格。

`PetVisual` 仍支持静态贴图和 `SpriteFrames`，可用于后续替换；自定义场景需遵守上述侧别、事件及时间接口。导出配置显式包含 `animation.json`，骨骼播放器、喷火和 shader 位于正式目录；审看工具继续排除。

## 验证

运行方式（在 Game 下，把 `godot` 替换成本机 Godot 4.7.2 可执行文件）：

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/integration/pets/run_pet_tests.gd
godot --headless --path . --script res://tests/integration/pets/run_pet_runtime_tests.gd
godot --headless --path . --script res://tests/integration/pets/run_pet_animation_study_tests.gd
godot --headless --path . --script res://tests/integration/save/run_save_tests.gd
godot --headless --path . --script res://tests/integration/stage/run_develop_merge_tests.gd
godot --headless --path . --script res://tests/editor/run_preview_frame_tests.gd
godot --headless --path . --script res://tests/editor/run_trial_flow_tests.gd -- --play-chart res://builds/trial-flow-input.zip
```

随从测试覆盖四档窗口及断持边界内外 1 微秒、短 / 双侧 Hold、暂停重臂、一次提档、伤害组、致死与非致死、不同帧步、领域重演、存档、菜单和真实 StageRoot。去掉 `--headless` 可检查实际渲染，并输出截图到 `builds/pet-review/`。

本次正式动画接入记录见 [随从动画接入验证](pet-runtime-validation.md)；早期系统测试记录保留在 [随从系统验证记录](pet-validation.md)。
