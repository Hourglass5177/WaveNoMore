# 《冥河，冥河！》Windows 构建说明

## 环境

- Godot `4.6.2.stable` 标准版（非 .NET 版）；
- 同版本的 Windows Desktop 导出模板；
- 目标平台：Windows x86_64；
- 构建预设：`Windows x86_64 Release`。

引擎与导出模板的补丁版本必须一致。模板可在 Godot 编辑器的“编辑器 → 管理导出模板”中安装。

## 发布构建

在 `Game` 目录执行：

```powershell
$godotExe = 'F:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force 'builds/windows' | Out-Null

# 先完成一次无界面导入，并暴露脚本或资源解析错误。
& $godotExe --headless --path . --editor --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot 项目导入失败' }

# 回归与内容校验。RC 必须让 strict-art 返回 0。
& $godotExe --headless --path . --script res://tests/run_all.gd
if ($LASTEXITCODE -ne 0) { throw '自动测试失败' }
& $godotExe --headless --path . --script res://src/tools/validators/validate_content_cli.gd -- --strict-art
if ($LASTEXITCODE -ne 0) { throw '正式素材或内容合同未通过' }

# 生成单文件 Release 可执行程序，PCK 嵌入 EXE。
& $godotExe --headless --path . --export-release 'Windows x86_64 Release' 'builds/windows/minghe-mvp.exe'
if ($LASTEXITCODE -ne 0) { throw 'Windows Release 导出失败' }
```

成功产物为：

```text
builds/windows/minghe-mvp.exe
```

## 导出边界

参赛构建只打包运行时依赖。预设明确排除：

- `tests/`：自动化测试与测试夹具；
- `addons/`：Godot 编辑器插件宿主；
- `editor_assets/`：写谱器模板与波形缓存；
- `src/tools/`、`scenes/tools/`：写谱器与 ArtLab 等编辑期工具；
- `content/visual/`：只供 ArtLab 使用的素材清单；正式场景由 `StageVisualTheme` 引用；
- `*.md`：工程内开发说明。

若运行时代码直接依赖上述目录，导出器会报告缺失资源；应先解除这类依赖，不要把整个编辑器工具链重新放进参赛包。

## 发布前检查

1. 运行完整自动化测试与 Perfect / 失败 Replay；
2. 在 60、120 Hz 显示环境分别试玩鼠标和手柄输入；
3. 检查窗口化、全屏、暂停、失焦、重试与结算流程；
4. 删除旧构建后重新导出，确认产物不是历史文件；
5. 在未安装 Godot 的 Windows 机器上进行一次冷启动测试；
6. 核对第三方歌曲、字体、图片与音效的授权清单。

授权登记模板见 `ASSET_LICENSES.md`。当前 Graybox 构建会被 strict-art 有意拦截；只有正式素材替换完成后才能标记为参赛 RC。

当前预设未启用代码签名。提交比赛可直接使用；公开分发时，未签名 EXE 可能触发 Windows SmartScreen 提示，应另行配置可信证书，且不得把证书密码提交到仓库。

## 常见问题

- `No export template found`：安装与引擎版本完全一致的 `4.6.2.stable` Windows 模板。
- `Preset not found`：命令中的预设名必须与 `export_presets.cfg` 完全一致。
- 脚本或资源解析失败：先运行上面的无界面导入命令；修复错误后再导出。
- 写入失败：确认 `builds/windows` 可写，并关闭仍在运行的旧版 `minghe-mvp.exe`。
