# 构建目录

## 2026-09-15 全部程序更新

以当前 develop 工作区（包含未提交的界面、声音和角色资源修改）导出三个 Windows Release 预设，更新 `builds/windows/minghe-mvp.exe`、`../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe`；两个编辑器的 `game/minghe.exe` 和原生 DLL 同步使用本次游戏构建。

实际游戏和写谱器通过 Compatibility 图形启动；关卡编辑器实际 EXE 的 20 项检查、游戏的 8 项检查通过，包括外部动画和 PCK、另存、多尺寸布局、试玩 ready 及试玩期间继续编辑。旧发布探针补上异步快照准备等待，避免过早读取 PID。导入、导出及最终启动日志无错误。日志和截图保存在 `../Levels/output/build-all-20260915/`。

更新写谱器 v0.1.5 发布包和开发包，新增关卡编辑器 2026-09-15 发布包；旧日期发行包保留为历史版本。识别器源码未变化，沿用既有程序、模型和许可。发布脚本兼容含顶层目录和无顶层目录两种旧 ZIP。用户关卡与谱面不纳入发布包。真实触摸板、中文组合输入、跨屏 DPI 和长时间真人制作未测。

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

2026-09-14 性能与 2K 设置构建：重新导出 `../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe` 和 `builds/windows/minghe-mvp.exe`，本体及 DLL 同步到两个编辑器的 `game/`。包含关卡性能优化、720p～4K 分辨率设置、混合双押与计时提示，以及当前工作区的关卡编辑器、动画改动。版本保持 0.1.4.0，未生成发行 ZIP。三个导出包各通过 40 项滑条图形检查和 63 项分辨率／真实波前像素检查；三个实际 EXE 启动以 0 退出，配套游戏加载教程2 normal 返回 `ready`。首次导入发现临时 `build/pet-animation` 资源 UID 重复，给不被正式素材引用的 `build/` 增加本地 `.gdignore` 后重新导入，最终导入、导出及启动日志无错误或警告。日志在 `builds/performance-release/`，性能数据和限制见 [关卡性能与分辨率](performance-and-resolution.md)。

2026-09-13 滑条填充与柔光微调：填充不透明度改为 0.52／贴合 0.62，轮廓与填充光强改为 1.0／0.8。重新构建三个程序并同步两个编辑器的配套游戏及 DLL；工程通过 41 项图形检查，三个导出包各通过 40 项滑条检查，三个 EXE 启动正常，教程2 normal 试玩返回 `ready`。日志位于 `builds/tuning-strength-release/`。更新时临时保留了正在运行的写谱器旧 EXE；用户关闭后已清理，并确认正常入口与最新构建一致。版本保持 0.1.4.0，未更新发行 ZIP。

2026-09-13 调频滑条与局部折射更新：重新导出写谱器、关卡编辑器和 `builds/windows/minghe-mvp.exe`，本体及 DLL 同步到 Charts、Levels 的 `game/`。包含半透明阵营填充、轮廓白光、起点圆帽预填及更集中的声波折射。三个导出包各通过 40 项滑条与 36 项声波图形检查；三个 EXE 的 Compatibility 启动均正常退出，配套游戏加载教程2 normal 难度返回 `ready`。导入、导出及最终运行日志未发现错误或警告，记录在 `builds/tuning-release/`。版本沿用 0.1.4.0，未更新发行 ZIP。

2026-09-13 生死换色与声波折射更新：按当前工作区重新导出写谱器、关卡编辑器及 `builds/windows/minghe-mvp.exe`，本体和 DLL 同步到 Charts、Levels 的 `game/`。三个导出包各通过 31 项背景图形回归与 22 项声波折射像素检查；三个 EXE 的 Compatibility 启动均正常退出，写谱器配套游戏加载教程2 normal 难度返回 `ready`。导入、导出和启动日志无错误或警告，位于 `builds/note-wave-release/`。版本沿用 0.1.4.0，未更新发行 ZIP。

2026-09-13 灵均静息与受击更新：正式角色引用增强呼吸、静息受击、攻击受击及死亡灰烬资源，重新导出 `../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe` 和 `builds/windows/minghe-mvp.exe`，游戏本体及 DLL 同步到两个编辑器的 `game/`。三个导出包均在 Compatibility 下通过 30 项角色姿态、受击、死亡与正式场景接入检查；三个 EXE 图形启动正常退出，配套游戏加载教程2 normal 难度返回 `ready`。导入、导出和运行日志无错误或警告，记录位于 `builds/lingjun-states-release/`。版本沿用 0.1.4.0，本次未更新发行 ZIP。

2026-09-13 白底预览修复：此前记录中的背景 shader UID 重复警告实际会让导出包引用错误材质，不能视为无影响。已修复资源 UID 并重新导出三个程序、同步两个编辑器的配套游戏；直接对三个导出包运行背景图形回归，每个包 17 项通过，1920×1080 与 960×540 的背景均恢复。详情与截图见 [白底修复记录](background-preview-fix.md)，日志在 `builds/background-fix/`。

2026-09-13 音符光效更新：按当前工作区重新导出 `../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe` 和 `builds/windows/minghe-mvp.exe`，本体与 DLL 同步到两个编辑器的 `game/`。三个程序通过 Compatibility 图形启动，配套游戏加载 `教程2/song.json` 的 normal 难度返回 `ready`，均以 0 退出，启动日志无错误或警告。导出仍有既存的背景 shader UID 重复警告。日志在 `builds/note-effects-release/`，版本沿用 0.1.4.0，未更新发行 ZIP。

2026-09-13 灵均两招更新：正式角色使用“下击 → 上挑”及各招末尾约 0.17 秒站姿停顿。已重新导出 `../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe` 和 `builds/windows/minghe-mvp.exe`，并将游戏 EXE、DLL 同步到两个编辑器的 `game/`。三个程序均通过 Compatibility 图形启动；写谱器配套游戏加载 `教程2/song.json` 的 normal 难度返回 `ready`，运行日志无报错。导入与导出保留已有的两份 screen_half_material_split shader UID 重复警告，未影响启动。日志位于 `builds/attack-two-release/`。版本沿用 0.1.4.0，未改动发行 ZIP、识别器或用户工程。

2026-09-12 灵均动画更新：使用修复后的单招及连续裙摆资源，重新导出 `../Charts/minghe-chart-studio.exe`、`../Levels/minghe-level-studio.exe` 和 `builds/windows/minghe-mvp.exe`；游戏本体连同 DLL 同步到 Charts、Levels 的 `game/` 目录。版本沿用 0.1.4.0。三个 preset 补充排除 `build/**` 和 `tools/**`，避免打入动画采样与生成工具。三个 EXE 的 Compatibility 图形启动均正常退出；导出及启动日志保存在 `builds/animation-release/`。本次未更新发行 ZIP，也未覆盖用户工程与识别器。

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


## 关卡动画修复产物（2026-09-13）

本轮不导出 EXE。事件测试、GPU 截图、隔离加载工程与日志位于 `Levels/output/editor-fixes/`。猴子动画作者资源仍在 `Game/assets/image/animation/monkey/`；其生成 PCK 与描述文件已移到 `Levels/output/asset-packs/monkey/`。已有渡口示例的 `packs/example.pck` 是示例运行依赖，继续保留。

已比对内容相同且无引用的 `assets/image/animation/assets/monkey.tres` 副本被移除，消除重复 UID。Godot 热重载的两个 `~*.dll` 临时文件不再纳入版本控制，并加入对应忽略规则；原 DLL 保留。原动画目录中的既有工程和图片未按临时文件删除。


2026-09-13 关卡编辑器九项修复构建：使用现有 Windows Release 预设导出编辑器和配套游戏，版本保持 0.1.4.0。程序及 DLL 已更新至 Levels 正式入口，新示例放入 Levels/examples/动画与遮挡，既有 example 与 projects 保留。构建日志、临时程序及实际 EXE 验收记录位于 Levels/output/editor-build-20260913；编辑器 20 项、游戏 8 项检查通过，试玩 ready。另存的 Windows 分隔符问题在实际 EXE 验收中修复并重建。未生成完整发行 ZIP，也未更新 Charts。
