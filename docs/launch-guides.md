# 耳机与控制器引导

两页使用纯黑底、骨白线稿和工程的 `assets/fonts/huiwen.otf` 汇文字体。耳机采用最初的古典纹样版本。文字与按键引线由 Godot 绘制，避免把生成图中的文字误差带入正式界面。

## 启动与设置

正式游戏每次启动依次显示：MEMO 工作室 → 耳机提示 → 操作说明 → 原有标题等待页。操作说明完整显示后，确认键或“继续”按钮进入标题页；输入不会穿透开屏。返回主菜单不重复显示，写谱器与外部试玩入口保持原有启动方式。

设置左侧增加“操作说明”。打开时暂停设置内容的导航，返回后保留草稿、分类、滚动位置，焦点回到该按钮。开屏与设置复用 `src/app/ui/instruction_guide.gd`。

## 按键图

图样使用 Xbox 非对称摇杆布局；只标注当前实际使用的按键。LT、RT、视图键和系统键不引出说明线。

| 按键 | 游戏内 | 菜单内 |
| --- | --- | --- |
| RB／右摇杆按下 | 敲击生钟；按住持续发波 | RB 切换条目或分类 |
| LB／左摇杆按下 | 敲击死钟；按住持续发波 | LB 切换条目或分类 |
| 右摇杆 | 生侧调频 | — |
| 左摇杆 | 死侧调频 | 导航 |
| 方向键 | — | 导航 |
| A／B | — | 确认／返回 |
| X／Y | — | 选关中的设置／随从 |
| 菜单键 | 暂停 | — |

依据 `project.godot`、`src/runtime/input/input_event_buffer.gd` 与 `src/app/ui/input_hints.gd`。示意图明确标为 Xbox 布局；继续／返回的键帽沿用当前设备家族。页面文案不改变开发用键鼠输入或游戏判定。

## 素材与复现

- 图样：`assets/ui/art/boot/guides/headphones.png`、`controller.png`。均为内置图像生成工具生成的独立素材，图像提示词见 [生成记录](launch-guides-prompts.md)。
- 排版：1920×1080 设计画布，窗口等比居中，非 16:9 留黑边。
- 完整黑底图片：`outputs/launch-guides/headphones-3840.png`、`controller-3840.png`，另有 1920 与 1280 宽度版本。此目录用 `.gdignore` 隔离，游戏只加载两张源图样和排版脚本。
- 重新采样：`tools/ui/run_ui_review.ps1 -Suites launch-guides`，使用正式 Compatibility 渲染与字体，不导出应用。
- 启动／设置输入回归：`tools/ui/run_ui_review.ps1 -Suites title,app-flow,art`。截图在 `builds/title-review`。
- 时长配置与表格同步见 [开屏引导参数](planning/12-开屏引导.md)。
