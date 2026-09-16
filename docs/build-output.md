# 构建与交付目录

## 当前保留

- `../Charts/`：写谱器、配套 `game/`、离线 `rhythm_analyzer/`、用户 `charts/` 和导出 `output/`。不要用发行包覆盖用户工程。
- `../Levels/`：关卡编辑器、配套 `game/`、用户工程及素材包。
- `builds/windows/`：现有独立游戏运行包。
- `../Levels/output/冥河，冥河！.zip`、`../Levels/output/冥河，冥河！（带开发工具版）.zip`：2026-09-16 参赛阶段保留的交付包，原样保存。带工具版内含一个旧上传状态文件，不影响本轮保留策略。
- `../Levels/output/保底关卡/`、`火-用户修改快照/`、`钟-用户修改快照/`：关卡成果与用户快照，继续保留。

编辑器运行目录和现有独立游戏不代表与参赛 ZIP 完全相同的构建；重新发布时应明确使用哪一版源工程。当前工作区有未提交改动，不能仅凭 HEAD 重现参赛包。

## 构建入口

在 Game 目录使用 Godot 4.7.2 和匹配模板，导出 `export_presets.cfg` 中的游戏、Chart Studio Windows、Level Studio Windows 预设。写谱器通常输出至 `../Charts/minghe-chart-studio.exe`，关卡编辑器输出至 `../Levels/minghe-level-studio.exe`；更新配套游戏时同步 `game/minghe.exe` 和必需原生 DLL。

完整写谱器打包工具为 `tools/package_chart_studio_release.py`。若使用 `--base`，必须指定仍存在的有效发行 ZIP；历史 v0.1.2～v0.1.5 独立 ZIP 已列入阶段清理，不应继续使用旧文档中的失效路径。用户谱面不自动收进发行包。

## 资源与核验

`assets/pv.ogv` 是 Git 忽略的本地运行资源，构建机仍须保留。源素材在仓库外 `../Assets/pv.ogv`。策划表位于 `outputs/planning/策划参数.xlsx`；发行程序使用构建时封装的参数，开发工程使用工作簿。

背景 shader UID 必须唯一；过去重复 UID 曾导致源工程正常而导出背景白屏。保留 `tests/visual/run_background_shader_tests.gd`，发行验证要检查包内资源和真实画面，不能只凭启动成功判断。Ghost 关联和原生 BOSS 同样需要在包内加载验证，见 [关卡素材接口](level-editor-interfaces.md)。

`build/`、`builds/` 的采样和临时产物可重新生成；`builds/worktrees/` 是 Git 工作树，不能按缓存递归删除。阶段清理记录保存于 `outputs/cleanup-20260916/`，不修改两个参赛 ZIP。
