# 关卡编辑器可靠性与制作流程验收 · 2026-09-14

## 范围与版本

本轮修改限于 Game 中的关卡编辑器、共用演出／依赖接口、测试、示例与文档。保留工作区其他任务正在进行的玩法、随从及写谱器修改，没有提交或覆盖这些文件。未导出程序；现有 Levels 中的 EXE 不代表本轮源码。

验证环境为 Windows、Godot 4.7.2、RTX 4060 Laptop GPU（OpenGL Compatibility）。产物在 `Levels/output/reliability/`；GPU 布局截图在 `Levels/output/ui/`。

## 结果性缺陷

| 项目 | 实现与结果 | 证据 |
|---|---|---|
| 多选向量回写 | 按 X／Y 绝对分量提交；取消和撤销恢复其他分量 | `delivery-core.log` |
| 跨区段／难度粘贴 | 来源对象保留；公共仍公共、专属去当前难度；同时间替换保留键 ID | `delivery-core.log`、`delivery-interaction.log` |
| 锁定与删除目标 | 命令入口整批拒绝不可编辑成员；专用按钮与通用删除分开；历史恢复选区 | `delivery-core.log` |
| 同名导入覆盖 | 独立资源路径，原内容保留 | `delivery-core.log` |
| 模板／字体／动画依赖 | 统一枚举；模板独占字体在隔离解压目录加载为 Font；图片保留 | `delivery-core.log`、`final-package.log` |
| 外观打断声音／实例 | 视觉重采样保留声音；替换单对象仅重建该实例 | `delivery-core.log`、`final-runtime.log` |
| BOSS 素材时间与身份 | 局部动作时间不乘主片段速率；逐素材帧；同素材对象切换正确 | `final-boss.log`、`final-mixed.log` |
| 属性同步／面板入口 | 共同字段复用；环境选区可进入关卡设置；取消同步字段，问题可定位引用 | `delivery-core.log`、`final-workspace.log` |

## 新制作流程

- 动画窗口的追加图片、所选帧创建动作、重命名、跳过文件清单、帧读数与多动作落盘经真实控件信号验证，见 `final-animation.log`。连续图片、精灵表及 SpriteFrames 的原有编解码继续沿用；本轮没有替换原资源格式。
- 对象树补充搜索、类型筛选、显隐／锁定和拖动层级。跨父组仅采样涉及的父链；长动画计算显示进度、可取消，完成后一次历史。相同父组排序不烘焙动画。`delivery-core.log` 覆盖静态换父组与撤销、长动画计算中取消不改文档。
- 轨道视图补充所选对象／难度／空轨筛选、前后事件和适应选区。工具栏低频操作按组进入“更多”，侧栏可从边缘收起，提供三种布局预设。“更多”保留嵌套菜单及原命令、勾选、禁用状态，另有回归检查。
- 环境属性增加前后环境与逐层定位；BOSS 列表增加类型、生死侧、段落和绑定筛选，多音符时序读数逐项列出。环境连续操作回归见 `environment-ui.log`。
- 整关审片覆盖曲前、歌曲、无音频时长和曲后切换；字段编辑开始时暂停，退出恢复此前游标且保持暂停。见 `delivery-core.log`。
- 导出检查、后台压缩和另存复制有进度与取消；取消不发布半成品 ZIP。普通恢复稿按工程区分，恢复前另留未保存状态，清理保护同工程的恢复稿依赖。
- 资源包重启测试实际生成 A／B 两版 PCK，并启动独立 Godot 进程读取 B。新进程保留未保存历史；撤销版本切换进入重启流程。见 `final-pack-restart.log` 与 `pack-restart/child.log`。
- 工程内真实游戏子进程报告 `ready`，启动快照不保存文档；游戏仍运行时继续编辑，退出后按钮恢复。见 `delivery-source-trial.log`。
- 扩展 `examples/level-studio/渡口演出/`：增加循环相纹、0.5 倍速、结束保持及独立动画模板，资源随示例携带。未重新构建已有发行示例。

## 画面与性能

GPU 布局覆盖 1024×720、1280×720、1920×1080、2560×1440、3440×1440，以及实际最大化／还原。大窗口自动倍率为 200%；小窗口限制过高倍率以维持可操作空间。画布坐标往返与鼠标锚点缩放通过。截图：`level-ui-maximized.png`、`level-ui-maximized-boss.png`、`level-ui-restored.png`。

Space 检查单独记录了 `window=true background=false` 的真实前台状态，通过按钮焦点后的播放测试，见 `final-layout-foreground.log`。一次未明确取得前台的 GPU 运行曾失败，保留在 `final-layout-gpu.log`，不将它与前台结论混为一谈。测试命令必须附加 `-- --level-editor`，否则游戏显示服务可能干扰测试窗口的渲染尺寸；早期错误启动的截图已用正确入口重采。

混合长工程含 86 个对象、139 条轨道、约 5 分钟动画，包含图片、文字、图片动画、声音、原生 BOSS、镜头与环境请求。`final-mixed.log` / `mixed-performance.json` 的本机 headless 测量：

| 操作 | P95 | 最大值 |
|---|---:|---:|
| 两轴浏览 | 16.701 ms | 16.753 ms |
| 外观编辑至下一帧 | 66.132 ms | 77.318 ms |
| 对象切换至下一帧 | 16.668 ms | 16.671 ms |

早期 84 对象基准曾测得外观编辑约 450 ms；主要耗时来自全量依赖检查、深复制关键帧和属性面板重建。保留 `mixed.log` 与阶段测量日志。上述数据是本机测量，不代表低配置或真实输入设备延迟；正式 GPU 画面检查与 headless 性能测量分开记录。

## 自动化与人工边界

通过的测试包括可靠性连续链、动画窗口、BOSS、对象分组、工作区、输入路由、运行采样、依赖包、环境 UI、资源包独立进程恢复、源码试玩与 GPU 布局。成功必须同时检查退出码和日志中的脚本错误，不能只看断言总数。

尚未实测：真实触摸板、中文输入法组合输入、跨屏 DPI、长时间真人制作、实际交付 EXE、人工听辨连续音频和所有美术素材的淡化接缝。测试中的声音连续性检查的是播放实例及参数生命周期；GPU Space 使用真实前台窗口和合成按键事件。后续用户要求构建时，需在实际工具和配套游戏中重复导入、编排、保存恢复、试玩、导出与倍率关键流程。

工作期间其他任务新增了玩法全局类；补做 Godot 类索引扫描时遇到并行编辑器占用临时 GDExtension DLL 的提示。没有删除或替换这些 DLL。后续干净测试日志见 `final-*` 和 `delivery-*`，扫描日志单独保留，不作为关卡功能通过证据。

## SpriteFrames 文件拖入补充回归

队友反馈的「拖入素材栏后放到预览不显示」暴露了上轮未覆盖的入口：窗口文件拖放仍按普通文件复制 `.tres`／`.res`，没有转换并收集来源工程图片；另有空 `default` 动作被自动选中的问题。现已让该入口打开同一动画导入窗口，跳过空动作，并在素材无法读取时阻止创建不可见对象。

`run_level_spriteframes_drop_tests.gd` 从窗口 `files_dropped` 信号开始，使用外部 Godot 工程、两帧 AtlasTexture、空 `default` 和非等长帧，经过确认导入、素材栏、画布 `_drop_data`、自动片段、撤销与重做。暂时移走来源图片后，独立装配仍通过。GPU 模式另检查预览纹理中心像素确实为第二帧蓝色，见 `spriteframes-drop-gpu.log` 与 `spriteframes-drop/spriteframes-preview.png`；原动画窗口回归见 `spriteframes-animation-regression.log`。

尚未拿到队友实际资源或运行版本，因此不能断言其文件没有其他问题；本次没有重新构建 EXE。

## 重跑命令

在 Game 目录运行，例如：

```powershell
& 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/editor/run_level_reliability_tests.gd --quit-after 1800 --log-file 'E:/大学/MEMO/编钟音游/Levels/output/reliability/recheck.log' -- --level-editor
```

GPU 布局去掉 `--headless`、选择 `--rendering-method gl_compatibility`，脚本改为 `run_level_layout_tests.gd`。动画、混合工程和资源包重启测试分别使用 `run_level_animation_workflow_tests.gd`、`run_level_mixed_workflow_tests.gd`、`run_level_pack_restart_tests.gd`。
