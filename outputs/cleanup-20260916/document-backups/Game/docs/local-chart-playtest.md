# 本地谱面与一键试玩

## 给谱师

**边写边试玩：**写谱器顶部点击“在游戏中试玩”。当前难度的未保存修改会进入独立快照，游戏从音乐开头开始，三秒准备后由你实际操作。写谱器暂停在原位置，可以继续编辑；正在运行的游戏始终使用启动时的版本。关闭试玩窗口后再次点击，才会使用新的编辑版本。

首次使用优先寻找写谱器旁的 `game/minghe.exe`。如果曾手动选择程序，则优先使用该配置；找不到时会提示选择 EXE。需要更换时打开“视图 → 试玩设置”。请选择配套游戏，不要选写谱器 EXE 或 Godot 编辑器。

**长期保留和分享：**写谱器点击“导出谱面”，选择要交付的难度。游戏中进入“选关 → 本地谱面 → 导入谱面”，选择 ZIP；也可将一个 ZIP 拖入本地谱面页面。导入后选择歌曲、难度，点击“试玩”。不需要解压、复制工程文件或安装 Godot。

导出和临时试玩都直接打包当前内存版本，不再隐式保存工程。需要保存项目请另按 Ctrl+S。缺少音乐、未知玩法或不可玩的对象会阻止打包，须先修正；BOSS 和其他已支持的兼容字段按原协议保留。

游戏会把导入的原 ZIP 复制到自己的本地库。以后移动或删除下载来的 ZIP，已导入谱面仍然可以玩。重复导入相同歌曲、谱面标识时，会先显示更新摘要；没有包含在新包里的其他难度继续保留。列表中的“移除”只移除当前难度及不再被引用的内部包，不删除导入源。

临时试玩的暂停和结算页提供“加入本地谱面”和“结束试玩”。加入后仍然将本局视为临时试玩，不保存本局成绩；以后从本地列表启动时才记录本地成绩。外部谱面不触发内置关卡解锁、随从奖励或正式进度。本地列表游玩使用当前装备的随从；写谱器临时试玩与内嵌预览默认不装备随从。不同编译版本的成绩分开保存。

出现“游戏未响应或不支持一键试玩”时，先关闭刚启动的游戏窗口，再到“试玩设置”选择配套游戏。加载失败信息会说明难度或对象；本次日志在错误提示所列位置，进程退出后保留最后一份到写谱器本机目录的 `last-trial.log`。

Tuning、Ghost 使用当前游戏的真实实现。多节点 Tuning 的分段适配、实际交点不足时 Ghost 数量可能少于请求值等边界，仍见 [Tuning / Ghost 编排](chart-editor-tuning.md)。这次接入不改变预测、计分或判定规则。

## 给开发者

### 接入位置

| 模块 | 职责 |
|---|---|
| `ChartPackageWriter.write(song, charts, directory, zip)` | 纯打包。资源必须是本次需要交付的内存版本；仅从项目目录读取必要的原始音频 |
| `StudioProjectIO.package_snapshot / export_zip` | 编辑文档深复制、难度选择；不调用 `save_project` |
| `ChartProjectLoader.inspect_package(path)` | 检查全部难度和音频，返回 `metadata`、类型化歌曲/谱面、结构化 `errors` |
| `ChartProjectLoader.load_stage(path, difficulty_id)` | 保留 ZIP / song.json 加载入口，复用当前路径适配与正式 StageDefinition |
| `ChartReadJobs` | 后台通过 `read_chart_data` 读文件、校验、解码；主线程装配 StageDefinition。页面只接收自己的请求编号，取消结果不再装配 |
| `LocalChartLibrary` | 原包、歌曲/难度索引、独立成绩。内部包名不来自歌曲 ID |
| `app_main` 的 `_run_context` | `origin=local/trial`、包路径、难度、song/chart ID、编译内容标识、返回选择；内置关卡使用空上下文 |
| `ChartReadyCountdown` | READY 状态下三秒准备；结束后调用正式 `StageSession.start` |
| `StudioPlaytest / ChartTrialLaunch` | 独立进程、参数数组、启动状态、退出与临时文件生命周期 |

后台不操作场景树。页面返回会作废请求编号；后台完成的旧结果不切回旧页面。正式实例化、准备与启动仍在主线程。列表读取缓存元信息，不反复解码音乐。

游戏的本地库位于 `user://local_charts/index.json`，内部原包为同目录下的 `package_*.zip`。索引只更新成功检查的难度；磁盘写入失败不发布新记录。成绩键包含 `song_id`、`chart_id` 和正式 Session 的 `compiled_chart.content_hash`。

写谱器配置在 `user://chart_studio/settings.cfg` 的 `[trial] game_executable`，快照在 `user://chart_studio/trials/trial_<request>/`。退出写谱器不会杀掉游戏或删除游戏仍在使用的包；后续启动只整理已结束请求的明确文件。

### 命令行

在 Game 目录执行工程内验证：

```powershell
& 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . -- --play-chart 'E:/大学/MEMO/编钟音游/Charts/output/test.zip' --difficulty normal
```

配套游戏接受相同自有参数：

```powershell
& '../Charts/game/minghe.exe' -- --play-chart 'E:/谱面/test.zip' --difficulty normal --trial-status 'E:/临时/status.json' --trial-request '本次唯一标识'
```

状态 JSON 的 `interface_version=1`，`request_id` 原样回传，`stage` 为 `recognized`、`ready` 或 `error`；错误包含 `message` 和日志位置。写谱器同时传入 `--log-file` 和 `--trial-log`，后者用于准确回传这次独立日志的位置。`ready` 表示正式 Session 准备成功，之后进行三秒倒数。参数不是新的谱面协议，歌曲仍为 JSON v1、谱面为 JSON v2。开发者可以用共享加载器读取 song.json；本地库导入只接收 ZIP。

没有网络服务、窗口复用或自动输入。CLI 临时入口不初始化玩家成绩存档，但读取游戏自己的音量、画面和校准设置。

### 构建与检查

保持识别器开发环境的现有构建命令，加 `-WithGame` 同时制作配套游戏：

```powershell
./tools/rhythm_analyzer/build.ps1 -PythonExe '<Python路径>' -GodotExe '<Godot 4.7.2路径>' -WithGame
```

不带 `-WithGame` 仍只导出写谱器，包清单不会因为运行目录残留游戏而自动把它收入。已有识别器不需重建时，可以分别执行两个 Godot export preset，再运行 `builds/rhythm-venv/Scripts/python.exe tools/rhythm_analyzer/package.py --with-game`。游戏使用 `Windows x86_64 Release`，写谱器使用 `Chart Studio Windows`。

新增 `run_local_chart_tests`、`run_trial_launcher_tests` 和 `run_trial_flow_tests` 已接入 `tests/editor/run.ps1`。流程测试自行建立隔离包和库，使用 CLI 临时入口跳过正式玩家存档；不导入用户测试项目作为发行示例。当前验证范围和待实机补验内容见 [验证记录](local-chart-validation.md)。
