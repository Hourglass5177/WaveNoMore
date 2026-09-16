# 构建目录

从 2026-09-12 起，写谱器运行文件移到与 `Game` 同级的 `Charts`。下文旧日期中的 `builds/chart-studio` 是历史路径。

- `../Charts/`：写谱器 EXE、原生 DLL、使用说明、`game/` 配套游戏及 `rhythm_analyzer/` 离线识别器。
- `../Charts/charts/`：用户谱面与示例；`教程2/` 原地保留，原运行目录的 `test/`、`示例项目/`、`Tuning示例工程/` 整体迁入。
- `../Charts/output/`：用户导出的谱面 ZIP；与完整程序发行包分开。
- `../Charts/releases/`：最新完整发行包。v0.1.2、v0.1.3 旧包移到 `archive/旧发行包/`，这里保留 v0.1.4；原发布 ZIP 内容不因本次移动而重写。
- `../Charts/archive/旧空白工程/`：Charts 顶层原先无音符的工程、音频和工作区备份，保留相对目录结构。

`Game/builds/` 留给构建中间物和测试日志；本次没有改动关卡编辑器的运行目录或正在开发的源码。

从 Game 单独导出写谱器：

```powershell
New-Item -ItemType Directory -Force ../Charts | Out-Null
& $godotExe --headless --path . --export-release 'Chart Studio Windows' ../Charts/minghe-chart-studio.exe
```

需要更新配套游戏时显式导出到 `../Charts/game/minghe.exe`。完整识别器构建脚本也向 Charts 输出程序；Python 开发环境、模型下载缓存及 PyInstaller 中间文件仍在 `Game/builds`，不与谱师运行文件混放。

更新发行包：`python tools/package_chart_studio_release.py --version 0.1.4 --base ../Charts/releases/冥河写谱器-v0.1.4-Windows.zip`。允许读取并更新同版本包，通过临时文件完成后替换；个人工程不被扫描入包。以后生成的示例项目统一放到 ZIP 的 `charts/` 中，运行目录里已经修改的示例不被构建覆盖。

清理命令被自动审批策略拦截，永久删除和回收站操作均未执行；因此旧包采用移动归档，约 662.5 MiB 尚未释放。Game/builds/chart-studio 已没有文件，仅留空目录。迁移前后 3000 个运行及项目文件校验一致（之后仅同步当前说明），教程2全部文件原地不变。写谱器启动、识别器启动、配套游戏加载教程2及 test 的真实试玩往返均通过；测试后再次核对用户项目文件不变。

## 历史记录

以下为迁移前的整理与发布记录。

- `chart-studio/`：写谱器、`game/` 配套游戏、识别器及离线模型。这里的 `test/`、示例工程和 `output/` 含用户项目与交付文件，不能作为构建垃圾删除。
- `冥河写谱器-v0.1.4-Windows.zip`：本次发布包。新版本验证完成后再清理旧包，不额外保留一份完整解压目录。
- 临时日志、测量录音、截图、探针脚本及中间导出，验证结束后清理；需要留存的结论写入 `docs`，发布说明使用的少量图片存入 `docs/screenshots`。

识别器的 Python 环境和下载缓存可以重建。清理后首次重建识别器，运行 `tools/rhythm_analyzer/build.ps1` 时需加 `-InstallDependencies`；仅更新 Godot 写谱器与游戏时不需要重建识别器。

2026-09-10 清理前：约 4.23 GiB、31,388 个文件、269 个顶层条目。清理后约 1.11 GiB、2,988 个文件，顶层仅剩上述运行目录、最新 ZIP 和 `.gdignore`。

旧导出、重复发布包、历史诊断、测试录音、临时脚本和可重建环境已移入回收站，约 3.12 GiB；清空回收站后才会释放对应磁盘空间。批量永久删除被自动审批拦截，因此采用可恢复的清理方式。

用户项目的 19 个文件核对大小与修改时间均未变化；项目 JSON、音频和各难度文件可正常读取。正式打包截图及一张白光效果图已移入文档目录，查询基准留存简短摘要，打包脚本不再依赖 `builds/tuning-review`。

2026-09-10 更新 v0.1.3：写谱器及 `game/minghe.exe` 同步重新导出，写谱器文件版本为 0.1.3.0。发布包共 2,992 个文件、约 331.4 MiB；保留上一发布包的全部文件，并增加 Tap／半径说明及截图。识别器、模型与示例共 2,926 项内容保持一致，未收集运行目录中的个人改谱。ZIP 完整性检查通过。

只更新 Godot 程序时，可导出两个现有 preset 后运行 `tools/package_chart_studio_release.py --version 0.1.3 --base builds/冥河写谱器-v0.1.2-Windows.zip`。此入口沿用已发布依赖、许可和示例，更新对应程序、DLL、文档与已有源码摘录，不需要重新创建识别器 Python 环境。

发布检查：导出无报错；写谱器 EXE 的无窗口及 Compatibility 图形启动均以 0 退出；配套游戏通过 `--play-chart` 加载 Tuning 示例并返回 `ready`。自动退出时仍报告 3 个 ObjectDB 实例、1 个资源未释放；从 v0.1.2 包中取出旧 EXE 对照运行，提示完全相同。源码功能验证见 Tap／半径专项记录，本次没有将外部探针脚本未执行的结果计为功能通过。

## v0.1.4 构建

两个 Windows preset 的文件版本统一为 0.1.4.0。先同步 `editor` 与 `develop`，再分别导出到 `builds/chart-studio/minghe-chart-studio.exe` 和 `builds/chart-studio/game/minghe.exe`。导出日志与本次发布检查记录保存在 `builds/`，不纳入源码提交。

制作完整 ZIP 使用 `tools/package_chart_studio_release.py --version 0.1.4 --base builds/冥河写谱器-v0.1.3-Windows.zip`。脚本同时更新场景说明、接口说明和根目录使用说明中的链接；上一版已有的玩法说明不会重复追加。

2026-09-12 更新仍使用 v0.1.4：新谱默认目录最后一个场景（目前为 s08），覆盖上述 EXE 与 ZIP。重新打包继续使用 v0.1.3 包作为依赖来源，不能同时读取并覆盖同一个 ZIP。发布检查记录保存在 `builds/release-0.1.4-verification.json`。
