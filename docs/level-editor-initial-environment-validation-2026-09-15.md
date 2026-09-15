# 初始环境选择修复 · 2026-09-15

核对时工作区为 develop，HEAD `43d3999`，与远端 editor 一致。保留其他任务的美术、加载页与策划参数修改。本次没有构建 EXE、提交或推送。

## 复现与修复

实际点击「选择初始环境」产生 `popup_centered: !is_inside_tree()`：共用选择器创建 Window 后没有加入工作区。窗口无法弹出，也影响「在游标处添加换景」「更换目标环境」。已补齐窗口挂载，并在无选项时禁用确认，显示搜索或缺少素材的说明。

同时修复：

- 选择后属性未同步初始环境名称及恢复按钮；现在复用控件更新，撤销／重做也同步。
- 起步引导「主题与初始环境」打开的关卡设置没有初始环境入口；现已补上。
- 可选初始环境字段原先不存在时，撤销留下 null 引用；现在恢复缺省状态。
- 尚未载入歌曲时基础背景未装配，恢复沿用会显示空白；现在保留独立预览的基础背景宿主。

## 验证

`tests/editor/run_level_initial_environment_tests.gd` 从实际按钮输入开始，经过选择器确认、取消、焦点返回、无结果搜索、关卡设置入口、撤销／重做、恢复沿用及另外两个换景入口。嵌入弹窗的鼠标输入经根 Viewport 按窗口位置路由。资源列表使用测试素材包，不修改用户工程。

| 检查 | 结果与证据 |
|---|---|
| 修复前点击 | 弹窗未挂载，7 项失败；`Levels/output/environment/initial-before.log` |
| 修复后完整操作链 | 通过；`Levels/output/environment/initial-gpu.log` |
| 实际显示所选环境 | GPU 读取预览纹理，蓝色环境像素符合素材；截图 `Levels/output/environment/initial/initial-environment.png` |
| 既有环境操作 | 通过；`Levels/output/environment/initial-environment-regression.log` |
| 多选、撤销与资源可靠性 | 通过；`Levels/output/environment/initial-reliability.log` |

Godot 4.7.2，Windows，RTX 4060 Laptop GPU，OpenGL Compatibility。本轮没有验证交付 EXE；旧程序不会自动获得源码修复。
