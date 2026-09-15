# BOSS 自动战斗与分侧发射验证

本轮修改游戏与关卡编辑器共享代码，未导出 EXE。测试产物位于 `Levels/output`。

## 实现与接口

- 自动动作识别、合并三段攻击、显式覆盖及生成只读轨道。
- 对象可选 `boss` 设置保存血量比例、语义动作映射、完整表现类型及发射默认参数；绑定可选 `action_mode`、`path_mode`、`flight_speed`、`spread_deg`。旧文件缺失模式时直接采用自动规则。
- BOSS 战斗状态读取权威判定过程，整数伤害去重；Replay 新增可选 `boss_battles`，原判定摘要不变。
- 弧长曲线、稳定方向、内部接点与速度衔接；真实阶段姿态更新发射锚点，查询后恢复当前画面。
- 正式表现与审看共用骨骼、揭眼、火焰和骨片源码。死亡白场位于玩法之上、HUD 之下。

## 检查与证据

| 检查 | 脚本与证据 |
| --- | --- |
| 旧常态绑定自动识别、密集攻击合并、偏移与覆盖 | `run_boss_actions_tests.gd`，`boss-actions.log` |
| 伤害去重、半血、破防、重试 | `run_boss_battle_tests.gd`，`boss-battle.log` |
| Hold 头尾与不足一拍、断持、不同帧率、Replay 扩展与原摘要 | `run_boss_gameplay_tests.gd`，`boss-gameplay.log` |
| 接点位置与速度、最小提前量、路程不回退 | `run_boss_path_tests.gd`，`boss-path.log` |
| 真实羊头揭眼、真眼死亡、骨片、暂停与回拖像素 | `run_boss_runtime_visual_tests.gd`，`boss-runtime-visual.log`，`boss-runtime/*.png` |
| 对象完整表现替换、撤销、路径覆盖、保存重开及窄窗口 | `run_boss_options_tests.gd`，`boss-options.log`，`boss-options/*.png` |
| 原有 BOSS 浏览、定位与绑定 | `run_boss_overview_tests.gd`，`boss-integration.log` |

旧领域总套件有 11 个核心用例和 24 个调频弧线用例失败。隔离移除本次 BOSS 接入、保留其他现有修改后，失败列表完全相同；对照分别为 `boss-domain-regression.log`、`boss-domain-baseline.log`。不把这些日志记作通过，也不在本次改写已有调频规则来迎合旧测试。

## 验证边界

GPU 使用 RTX 4060 Laptop、Godot 4.7.2 Compatibility。工程内测试不能替代全部外部骨骼素材、真人长时制作、真实触摸板、跨屏 DPI 或交付 EXE 验证。默认参数通过既有同步脚本更新工作簿，未重置其他当前值。

## 收尾复测

2026-09-15 最终核心复测通过：自动动作、战斗状态、分侧路径、Gameplay／Replay、GPU 完整表现及编辑器设置六组。对应 `boss-actions-final.log`、`boss-battle-final.log`、`boss-path-final.log`、`boss-gameplay-final.log`、`boss-runtime-final.log`、`boss-options-final.log`。完整表现额外覆盖 0.5／1／2 倍速素材时间。

战斗测试显式提供真实传播接触收尾通知；成功判定不意味着物理收尾已经完成。最终画面检查覆盖羊头揭眼、真眼死亡和骨片，尚未完成全素材、多 BOSS、调频部分成功与整关曲后结算的完整人工连续验收。旧领域套件的 35 项基线失败仍保留，不宣称全部验收场景通过。

## tutorial_1 附件修复

附件已配置静息 `feixing` 和三段攻击映射，但 `show.bindings` 为空，且残留手放的 `animation`／非循环 `feixing` 片段。旧播放器只在有战斗状态且无片段时回退静息，导致静息停住；编译器只处理显式绑定，导致没有自动攻击。

现在静息不再依赖战斗状态，单一已配置 BOSS 自动接收未分配音符；显式绑定优先，多 BOSS 不猜归属。局部预览使用独立动作优先级，避免被常态覆盖。附件 GPU 回归确认 16 个音符关联、静息时间推进及实际骨骼三段攻击，打开不修改文档。测试 `run_boss_imported_project_tests.gd`，素材与结果仅放在 `Levels/output/boss-user-repro`。交付版通过外部验收素材包运行 `boss_delivery_probe.gd`，不把探针加入用户工程或发行包。

交付检查：实际 Windows Release 编辑器从外部工程加载上述骨骼，确认静息和生成攻击；通过配套 Release 游戏试玩收到 ready。`Levels/output/boss-delivery-qa/delivery-result.json` 的 errors 为空，画面见同目录 `交付版界面.png`。交付包不包含验收 PCK。导出阶段已有编辑器占用临时热重载 DLL 的提示未影响发行 DLL，实际 EXE 骨骼加载已验证。
