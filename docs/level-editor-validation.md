# 关卡编辑器验证记录

日期：2026-09-12；分支：`editor`；引擎及导出模板：Godot 4.7.2 Windows x86_64。

## 本轮：操作体验重整（工程源码）

本轮没有导出工具或游戏 EXE。下文旧的 Release 检查属于此前交付版本，不能作为此次界面改动的发布验证。当前结果来自工程内运行；真实试玩使用已有配套游戏检查其正式握手协议。

| 场景 | 本轮结果 |
|---|---|
| 高精度双轴滚动、缩放锚点、Shift 增减选、拖动阈值、Alt、失焦取消 | Viewport 事件路由检查通过；headless 和实际 GPU 均通过 |
| 数值事务、多选同步、区段视图、折叠行命中、专注预览 | 交互专项通过 |
| 集成 BOSS 面板、默认出手标记、绑定撤销与复制配置 | 示例及流程专项通过；主时间线没有模态阻断 |
| 颜色实时预览、一次撤销，改名／调色不重建玩法及攻击 | 流程专项通过，GPU 复测通过 |
| 另存依赖、输入框中 Ctrl+S、恢复稿时间和工作区状态 | 流程专项通过，使用临时副本，未修改示例文件 |
| 素材搜索选择器与模态焦点 | 流程专项通过 |
| 真实游戏启动、ready 握手、未保存快照、游戏运行时继续编辑 | 使用已有配套游戏通过；测试只关闭自身启动的进程 |
| 最大化／还原、应用倍率、面板尺寸、画布拾取 | GPU 布局专项通过；查看最大化 BOSS 面板和还原布局截图 |
| 文档、运行时、BOSS、分组、打包、基础工作区 | 相关既有专项回归通过 |
| 预览重演冻结、最新定位替换、后台恢复 | 原有 preview_frame 专项通过 |
| 工程解析 | 无脚本解析错误；仍有既有 shader UID 重复警告 |

性能样本：RTX 4060 Laptop / OpenGL Compatibility，100 个对象、10,000 个关键帧、5 分钟区段，连续浏览 60 帧；输入到下一帧 P95 **16.78 ms**，帧间隔 P95 **16.788 ms**，最大 **20.702 ms**。这是浏览场景的本机数据，不代表长歌曲玩法重演、复杂美术或音频负载的定位耗时。结果位于 `../Levels/output/ux/dense-ui.json`。

新增专项：`run_level_interaction_tests.gd`、`run_level_flow_tests.gd`、`run_level_dense_ui_tests.gd`、`run_level_trial_ui_tests.gd`。现有 layout/example_ui 专项已切换到集成 BOSS 面板。事件测试覆盖 23 个操作断言，流程测试覆盖 19 个；断言数量不替代下面的实际设备验证。

尚未实测：实体触摸板手感、Windows 系统 DPI 逐档切换／跨显示器移动、中文输入法组合态、长期人工制作和新工具 Release 包。已接入窗口 DPI 变化信号；当前只验证了应用倍率和本机最大化。没有把这些未测项标记为通过。

## 此前交付版本记录

## 已完成检查

| 检查 | 结果 |
|---|---|
| 文档、历史和复制 | 13 项通过 |
| 共用演出播放、序列化、HUD、原生动作定位 | 13 项通过 |
| BOSS 提前生成、连续衔接、曲前曲后及一次结算 | 17 项通过 |
| 分组与解组、多难度、采样和节拍 | 9 项通过 |
| 示例 ZIP、歌曲目录、封面、动态锚点、特效及草稿预览 | 14 项通过 |
| 工作区、关键帧、拆分、复制、组合与恢复稿 | 9 项通过 |
| 示例与 BOSS 编排弹窗 | 7 项通过 |
| 原有正式预览重演、定位取消及后台暂停 | 14 项通过 |
| 独立工具 Release EXE | 12 项通过，headless 与实际 GPU 各运行一次 |
| 配套游戏 Release EXE | 7 项通过，headless 与实际 GPU 各运行一次 |

专项脚本共 96 项，加上实际发布程序的 19 项检查，共 115 项。所有上述最终运行退出码为 0。最终导入和两项导出无脚本解析错误；导入仍提示项目既有的两份 shader UID 重复。

实际 EXE 检查通过普通外部素材包加载测试节点，走产品正常启动入口，没有用编辑器代替 Release 模板，也没有把测试入口打进产品。检查覆盖外部原生动画、PCK 内导入纹理、多难度、真实玩法预览、另存依赖、提前发射、试玩存档隔离及后台暂停。测试素材包单独位于 `../Levels/output/release-qa/`，不包含在交付包。

工具在 1024×720、1280×720、1440×900、1920×1080 实际渲染并保存截图；查看了小窗口与常用窗口布局。实际 GPU 为 RTX 4060 Laptop，Compatibility / OpenGL 3.3。配套游戏已在正式入口装入外部 ZIP 和外部 BOSS 素材，截图及日志保存在上述 QA 目录。

## 复现

在 Game 目录，使用 Godot 控制台程序：

```powershell
& $godotExe --headless --path . --editor --import --quit
& $godotExe --headless --path . --script tests/editor/build_level_example.gd -- --chart-editor
& $godotExe --headless --path . --script tests/editor/run_level_package_tests.gd -- --chart-editor
& $godotExe --headless --path . --export-release 'Level Studio Windows'
& $godotExe --headless --path . --export-release 'Windows x86_64 Release' ../Levels/game/minghe.exe
```

完整专项列表为 `run_level_document_tests`、`run_level_runtime_tests`、`run_level_boss_tests`、`run_level_group_tests`、`run_level_package_tests`、`run_level_workspace_tests`、`run_level_example_ui_tests`、`run_preview_frame_tests`，均在 `tests/editor/`，扩展名 `.gd`。

实际 EXE 验收素材由 `tests/editor/build_level_release_probe.gd` 生成。工具用 `-- --open-level <QA目录/level.json> --qa-report <结果JSON>` 启动；游戏用 `-- --play-level <QA目录/probe.level.zip> --difficulty hard --qa-report <结果JSON>` 启动。`--qa-report` 仅由测试包内脚本读取，正常程序没有相应测试分支。

## 验证边界

### 窗口与交互优化补充

本轮 GPU 检查 31 项通过；工作区 9 项、示例弹窗 7 项回归通过。工具已重新导出，其实际 Release EXE 的 12 项 GPU 检查再次通过；配套游戏保持原构建。

`run_level_layout_tests.gd` 专项覆盖 1024×720、1280×720、1920×1080、2560×1440、3440×1440、自动/手动缩放、小窗口倍率限制、侧栏宽度保持、预览拾取与鼠标位置缩放、连续数字编辑、Space 输入分流、播放跟随和弹窗焦点恢复。另以 GPU 实际最大化和还原窗口并检查截图。本机最大化为 2560×1566、自动倍率 200%、逻辑画布 1280×783；BOSS 弹窗和底部按钮在画面内。窗口测试会按本机屏幕允许的尺寸运行。

此项已经覆盖应用自身的倍率与窗口状态切换；下面的 Windows 系统 DPI 各档及手柄实按仍未全测。截图为 `../Levels/output/ui/level-ui-maximized.png`、`../Levels/output/ui/level-ui-maximized-boss.png`、`../Levels/output/ui/level-ui-restored.png`。

独立 EXE 已在本机直接运行并装入外部素材，但尚未在一台从未安装 Godot 的干净 Windows 机器上验收。窗口检查使用本机显示设置，未逐档测试 Windows DPI 缩放或逐控件实按手柄。没有进行长关卡性能基准测试。

旧的 `tests/integration/stage/run_stage_runtime_tests.gd` 引用已移除的 InputRouter 等接口，运行前解析失败；本轮未扩大范围修复旧测试。新的相关测试和原有正式预览测试已通过，不能据此声称整套历史测试全部通过。

对自定义状态机和 Spine 的受控推进接口已接入；随交付包提供的示例素材使用原生 AnimationPlayer。正式美术接入后仍需按其具体骨骼物理和状态图检查回拖成本、混合表现与素材效果。本轮未将开发版标记为参赛 RC。

## 构建目录整理

运行目录已迁到根目录 `Levels/`，Godot 的 `Level Studio Windows` 预设直接输出 `../Levels/minghe-level-studio.exe`。配套游戏、DLL、示例和启动脚本保持相对目录关系；本次没有重新构建 EXE。

源码示例和测试脚本继续留在 Game。截图写入 `../Levels/output/ui/`，性能数据写入 `../Levels/output/ux/`，重新生成的 Release 验收包写入 `../Levels/output/release-qa/`。验收探针的中间 Godot 资源使用 `.godot/level-release-staging/` 缓存，避免在 builds 中留下交付副本。

此前测试工程（含 demo 音频）保存在 `../Levels/projects/test-level/`，唯一历史发行 ZIP 保存在 `../Levels/releases/`。旧日志、过期截图和临时 API 探针已清理；旧 Release 验收工程删除被自动审批策略拦截，保留在 `../Levels/archive/旧验收文件/`，其结果 JSON 单独保存在 `../Levels/output/release-reports/`。
