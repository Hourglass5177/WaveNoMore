# 关卡编辑器：数据与素材接口

## 文件分工

| 文件 | 内容 |
|---|---|
| `level.json` | `minghe-level` 版本 1；关卡 ID、标题、场景、歌曲引用、资源包、片头片尾、规则和奖励 |
| `show.json` | `minghe-show` 版本 1；对象、属性轨、动作/音频/显隐片段、BOSS 绑定、可复用组合 |
| `song/song.json` 与谱面 | 沿用写谱器 JSON，稳定音符 ID 与 tick 不重写 |
| `workspace.json` | 面板、游标、难度、缩放和谱面来源；不打入运行 ZIP |
| `assets/`、`packs/` | 普通素材与原生资源包，工程内相对路径 |

演出时间为各区段内的整数微秒，谱面使用原有 PPQ 480 tick 与 TempoMap。关卡目录为制作格式，ZIP 为交付格式。`LevelProjectIO` 收集声明的歌曲、难度和素材依赖；不打入恢复稿与历史备份。`LevelProjectLoader` 是工具预览和游戏共同的装配入口。

正式关卡难度身份为 `level_id:chart_id`；本地目录按 `level_id` 汇总关卡、按 `chart_id` 保存各难度成绩。下一关解锁填写目标 `level_id`。随从奖励引用游戏现有 PetDefinition，规则引用现有 GameplayRuleSet；不在工具中创建新规则实现。

## Godot 素材包

在 Game 工程中创建 `VisualAssetManifest`，为每项添加 `VisualAssetEntry`：

- `asset_id`：稳定 ID，关卡对象和反馈通过它引用。
- `display_name`、`thumbnail`：素材库显示名称和预览图。
- `category`：角色用 `actor`，环境用 `environment`，特效用 `effect`。
- `runtime_scene`：可实例化的 PackedScene，作者负责内部节点、骨骼、材质和状态机。
- `visual_bounds`：以场景根为基准的像素范围，用于选择框和操纵。
- `state_names`：允许调用的动作或状态名称。
- `anchors`：锚点名到 Vector2 或节点路径。节点路径相对素材根，例如 `"life": "Body/LifeSocket"`；出手时采样动画后的节点位置。
- `action_markers`：如 `{"attack": {"release_sec": 0.3}}`，时间以动作原始速率为准。
- `exposed_parameters`：允许策划编排的参数声明。

在 Godot「项目 → 工具 → 导出关卡素材包…」中选择清单并保存 `.pck`。插件同时写出 `.assetpack.json`，两者一起交付。导出会收集资源依赖、导入描述和实际导入产物；先在 Godot 完成导入再导出。

资源包保留原 `res://` 路径。不同团队素材使用各自目录和稳定 ID；示例放在 `res://level_assets/editor_example/`。PCK 更新使用重启工具的流程，避免旧缓存与新脚本混用。

参数声明示例：

```gdscript
{
    "亮度": {
        "node_path": "Body",
        "property": "material:shader_parameter/intensity",
        "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.05
    },
    "装饰位置": {
        "node_path": "Decoration", "property": "position",
        "default": [0.0, 0.0]
    },
    "发光颜色": {
        "node_path": "Body", "property": "modulate",
        "type": "color", "default": "ffffffff"
    }
}
```

文档里的向量使用双元素数组，颜色使用 RGBA 十六进制字符串。运行时按目标属性转换为 Vector2 / Color。材质按素材实例复制，开放的材质参数不会串到其他实例。

## 动画控制

`LevelAnimationDriver` 支持 AnimationPlayer、AnimatedSprite2D 和当前 Spine GDExtension。素材实例的常规自动处理被关闭，动画由关卡时钟控制。

AnimationPlayer 属性按绝对时刻取值，使用 `seek(..., update_only=true)`，不补播方法轨或音频轨；声音和反馈放到关卡音频／特效轨。动作离开片段后恢复基础属性或 RESET。序列帧根据帧时长定位。Spine 按固定 60 Hz 推进，回拖和换动作时重置再快进。

已有 AnimationTree 或自定义状态机可在素材根实现：

```gdscript
func level_reset(action: String, looping: bool) -> void:
    # 重置状态机、累计量和视觉状态，再选中目标动作。
    pass

func level_advance(delta: float, silent: bool) -> void:
    # 只推进受控状态；silent=true 时不要发出声音或玩法事件。
    pass
```

由素材作者负责把参数传给实际状态机。接口使用固定 1/60 秒步长；反向定位从起点重算，长时间有状态动画的定位成本取决于历史长度。多动画交叠的原生属性支持权重混合，Spine/自定义状态机使用当前活动动作，内部混合由素材接口处理。

## BOSS 与运行时

`LevelBossCompiler` 从当前难度的 BOSS 音符 ID 编译动作、声音、特效和提前运动数据，合并同刻动作。`ChartScheduler` 提前生成真实 Tap/Hold；`NoteVisualHost` 在同一实例上衔接 `BossEmissionPath` 与常规路径。Hold 沿用现有身体模拟及消耗逻辑。素音仍由正式声波系统计算。

锚点先采样出手动作，再应用对象／父组／镜头在出手时的变换。弹射曲线起点冻结，末端位置和速度接常规路径，不改变领域判定。`StageRoot` 在正常玩法结束后固定结果，播放收尾后一次性提交结算；试玩上下文不发正式奖励。

## 开发入口

工具场景：`res://scenes/tools/level_studio/studio.tscn`。开发启动参数为 `-- --level-editor`；独立工具预设为 `Level Studio Windows`。工具支持 `-- --open-level <level.json绝对路径>`，配套游戏支持 `-- --play-level <关卡ZIP绝对路径> --difficulty <difficulty_id>`。

主要模块在 `src/tools/level_studio/`、`src/content/level_format/` 和 `src/runtime/director/level_*`。素材导出插件在 `addons/level_asset_export/`。生成示例运行 `tests/editor/build_level_example.gd`；专项验证运行 `tests/editor/run_level_*_tests.gd`，使用 `-- --chart-editor` 隔离工具测试存档。

## 编辑器操作接口补充（2026-09-12）

运行关卡格式不变。`workspace.json` 新增可选 `panels` 和 `views`，后者按 `区段/难度` 保存视图；旧文件缺少时使用默认布局。视图不计入文档撤销历史。

`LevelDocument.begin_edit/end_edit` 汇总字段连续编辑，`last_changes` 提供此次涉及条目；预览修改结束后只提交一次历史。时间线用完整事件选区通知工作区，工作区拥有对象、轨道、事件以及当前编辑目标。BOSS 使用 `LevelBossPanel`，生成轨道保持只读。

关卡试玩沿用 `ChartTrialLaunch` 状态协议（request_id、stage、message），只有 `ready` 表示游戏已经加载；启动进程与编辑器前后台状态分别管理。
