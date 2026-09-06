# 《冥河，冥河！》Godot 工程

- 引擎：Godot 4.7.2（GDScript）
- 基准画布：1920×1080
- 启动场景：`scenes/app/app_main.tscn`
- 正式内容：`content/stages/<stage_id>/`

工程以 `SongChart` 的 PPQ 480 整数 tick 为唯一谱面时间。运行时、Replay 和写谱器共用 `src/domain/` 与 `src/content/`，表现层不得参与判定。

## 操作

- 鼠标左键或 F：死钟；鼠标右键或 J：生钟；
- PC 调频测试：单独按住一键时，鼠标水平拖动对应钟；两键同时按住时，同一拖动量暂时作用于两钟；
- 手柄：L1 按住死钟、左摇杆移动死钟游标；R1 按住生钟、右摇杆移动生钟游标；
- 摇杆和拖动只在谱面声明的调频场内改变频率；其他时段按住钟仍会按基准频率持续发波；
- Esc 或手柄 Start：暂停。

## 当前内容

- `s01/渡口试音`：全机制 Graybox 关，覆盖 Tap、双押、Hold、独立双钟调频、动态素音和双钟疾振；
- `s02/调频试验`：集中验证单钟持续载波、单侧滑条、双侧成组滑条和折返。

谱面已使用 `SongChart` Schema 2。调频场、单侧滑条和素音凝现分别存放；素音位置由运行时真实载波圆交点产生，不是预先摆放的固定靶点。缺少正式 BGM 时，运行时会生成可听的测试节拍，但严格交付校验不会把它视为正式内容。

## 自动测试

在仓库根目录执行：

```powershell
$godotExe = 'F:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
& $godotExe --headless --path Game --script res://tests/run_all.gd
& $godotExe --headless --path Game --script res://src/tools/validators/validate_content_cli.gd
```

提交参赛版本前再运行严格美术门禁：

```powershell
& $godotExe --headless --path Game --script res://src/tools/validators/validate_content_cli.gd -- --strict-art
```

严格模式在仍有 Graybox 素材时返回非零退出码，这是预期行为。

## 写谱与美术接入

- 新版独立写谱器入口：`scenes/tools/chart_studio/studio.tscn`，或启动参数 `-- --chart-editor`。仅支持生死 Tap/Hold，使用共同 JSON 协议保存、预览和交付。
- [谱师使用说明](docs/chart-editor-guide.md)、[共同接口](docs/chart-editor-interfaces.md)、[进度与验证记录](docs/chart-editor-progress.md)。当前为开发版，尚未完成全部验收。
- 新测试：在 Game 目录运行 `./tests/editor/run.ps1 -GodotExe <Godot控制台程序路径>`。
- 旧 `chart_editor` 与插件暂留作迁移参照；新版验收通过后移除，不再扩展旧工具。
- `scenes/tools/art_lab/art_lab.tscn` 用实际 runtime scene 检查锚点、状态、动画、画幅与遮挡。
- Windows 导出步骤见 `BUILDING.md`。
