# 随从系统验证记录

日期：2026-09-08。环境：Windows、Godot 4.7.2，真实渲染使用 Compatibility / OpenGL。对照基线为 `develop@ca2d574`。没有导出应用或合并 develop。

## 本轮检查

| 检查 | 结果 |
| --- | --- |
| 工程编辑器导入与脚本解析 | 无脚本错误 |
| `tests/integration/pets/run_pet_tests.gd` | 260 项检查通过，Headless 和实际渲染均通过 |
| `tests/integration/save/run_save_tests.gd` | 13 项检查通过；奖励夹具改用女土蝠 |
| `tests/integration/stage/run_develop_merge_tests.gd` | 通过，双 Hold / 调频与外部时钟行为保持 |
| `tests/editor/run_preview_frame_tests.gd` | 通过，包含预览默认无随从及重复定位 |
| `tests/editor/run_preview_loading_tests.gd` | 通过 |
| `tests/editor/run_trial_launcher_tests.gd` | 通过 |
| `tests/editor/run_local_chart_tests.gd` | 通过 |
| `tests/editor/run_trial_flow_tests.gd` | 通过，扩充试玩空装备、本地装备、重试固定形态、重新进入读取新形态 |

随从套件实际覆盖：四档起手窗口内外 1 微秒、120 ms 断持边界、两种形态相同宽限、短 Hold、双侧 Hold、暂停重臂、提档封顶、完全漏按和断持、Tap / 调频 / 素音不受翼火蛇影响、独立配置副本、Combo 倍率与累计奖励取整、独立伤害四舍五入、双侧同刻伤害组去重、致死 / 非致死模式、8.333 ms / 16.667 ms / 5 s 帧步、领域重演、跨越致死时刻的输入、等待抵达后通关、重复定位、FC / AP 奖励、旧装备失效及历史保留、保存重开、菜单焦点与真实关卡装配。

实际画面检查确认：两个随从中心对称，位于各自角色旁；漏按 Hold 获得 Pass 后仍沿失败路径移动，抵达时魂火变为 80 / 100，Combo 保持 1，判定文字为 Pass。菜单显示三种轮廓、完整数值和装备状态。细则置于悬停提示。

本机截图与日志位于忽略目录 `builds/pet-review/`：`pets-menu.png`、`pets-missed-hold.png`、`pets-stage.png`、`pets.log`、`render.log` 及各回归日志。Headless 随从 / 页面测试退出时仍有两个音频对象释放警告，Verbose 标识为 `AudioStreamWAV / AudioStreamPlaybackWAV`；本轮实际渲染测试没有该警告。

## 既有失败

| 测试入口 | develop 基线与本轮结果 |
| --- | --- |
| `tests/unit/domain/run_domain_tests.gd` | 同样 34 项失败；按失败消息集合比对，无新增或消失项 |
| `tests/unit/domain/test_wave_interaction.gd` | 同样无法解析，仍引用已删除的 `SemanticInputKind.LIFE_PRESSED` 等 |
| `tests/integration/stage/run_stage_runtime_tests.gd` | 同样无法解析，仍引用旧 `InputRouter` 等接口 |
| `tests/integration/app_flow/run_app_flow_smoke.gd` | 同样无法解析，仍引用已删除的 `LIFE_RELEASED` 等 |
| `tests/unit/domain/test_carrier_wave_engine.gd` | 同样 2 项失败：s04 / s05 素音事件数量预期仍为 2 / 1，实际为 0 / 0 |

领域、波传播、旧关卡和旧应用入口在改动前记录了基线。载波套件另在临时的干净 develop 工作树复现两项失败，核对后已移除临时工作树。本轮没有恢复旧输入接口来迁就这些测试；新增随从套件通过现行 A/B 输入和真实 StageRoot 验证波接触、抵达伤害及玩法生命周期。

## 手柄菜单修正

`tests/integration/pets/run_menu_navigation_tests.gd` 通过真实 `InputEventJoypadButton` 覆盖长目录上下滚动、完整露出当前歌曲、弹窗四向寻焦、卡片重建、开发区展开、B 键关闭后恢复原焦点、关闭后继续操作目录及六条技能原文。此次共 49 项检查通过；截图输出为 `builds/pet-review/menu-scroll.png` 和 `modal-focus.png`。

菜单技能描述恢复为用户确认的原文，移除了后加的细则悬停文案；程序数值仍见规则配置。列表跟随焦点滚动、弹窗隔离焦点的原则同时记录在根目录 `AGENTS.md`，供后续美术改版沿用。
