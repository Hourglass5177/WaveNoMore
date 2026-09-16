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

### 循环环境扩展（可选，格式版本仍为 1）

`level.json.initial_background` 引用初始环境；省略时沿用关卡基础场景的背景。`show.json.scene_cues` 是可选数组，例如：

```json
{
  "id": "scene_river",
  "name": "渡口",
  "section": "song",
  "time_us": 12000000,
  "asset": "river_background",
  "difficulties": [],
  "effect": "fade",
  "blend_px": 128.0,
  "static_fade_us": 500000,
  "layers": {"foreground": {"effect": "none"}}
}
```

`asset` 使用素材清单 ID；内置背景使用 `stage:<场景 ID>`。`difficulties` 为空表示公共编排，区段使用 `intro/song/outro`。同一时刻按文档数组顺序处理。`layers` 按对应层标识覆盖效果字段；移除覆盖项恢复继承。保存只保留用户请求时间，实际入画、完成和换速时间不回写文档。

`VisualAssetEntry` 可选 `background: StageBackgroundDefinition` 与已有名称、缩略图一起提供环境素材；背景条目无需 `runtime_scene`。PCK 依赖遍历会收集背景、贴图、序列帧、材质及导入产物。关卡 ZIP 保留引用并包含声明的 PCK；缺失引用可定位到对应请求。更新资源包后仍按既有流程重启工具。

每个 `StageBackgroundSubLayer` 新增可选字段：

| 字段 | 用途及默认值 |
|---|---|
| `continuity_id` | 跨场景对应身份；默认空，回退为 `深度/子层 ID` |
| `cycle_direction` | 循环边界的法向方向；默认零向量，从有效滚动方向推导 |
| `cycle_start`、`cycle_end` | 沿方向投影的设计像素边界；默认相等，从素材组合外框推导 |

`StageEnvironmentSequence` 使用固定 1920×1080 设计画面和整数微秒安排。曲前映射到负时间，歌曲使用音频时间（包含首拍偏移），曲后接在歌曲尾端。各层在自己的可用边界接续；渐变带的前沿尚未入画才可开始，后沿完全退出才完成。速度和视差深度以累计位移接续；演出镜头参与求值，预览浏览变换及震动不参与排队。修改层覆盖项时复用未受影响层的安排。

`ParallaxController.set_environment/sample_environment` 仅管理背景来源，保留角色和音符注册项。纯单来源直接绘制，接缝附近才使用离屏来源与局部权重合成，长序列只实例化可见来源。原生材质先绘制，再施加接缝权重，保留透明度与生死分屏；未编排换景、未指定初始环境的旧关卡继续原链路。

序列帧按来源入画后的局部时间定位。动态材质声明 `uniform float environment_time = -1.0;`，在非负时使用该时间；普通背景可以在负值时继续使用 `TIME`。现有尘粒材质已接入。需要确定性定位的新材质不能只依赖真实帧数或全局 `TIME`。

### 原生场景素材

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

## 普通动画资源（2026-09-13）

普通动画继续使用 `animated_sprite` 对象及 `action` 轨道。导入统一输出 `assets/animations/<版本>/asset.animation.json` 和实际 PNG 依赖：

```json
{"format":"minghe-animation","name":"扩散环","animations":[{"name":"default","fps":12,"loop":true,"frames":[{"image":"image_0000.png","duration":1,"region":[0,0,96,96],"margin":[0,0,0,0]}]}]}
```

描述还可保存 `default_animation`，优先采用导入时用户所选动作；未指定时依次取 `default` 或首个动作。

`region`、`margin` 可省略，省略表示整张图片。`duration` 是相对于 FPS 的帧时长倍率。同张图集只携带一次。运行时 `LevelAnimationAsset` 从相对 PNG 构造 SpriteFrames，不需要开发机 `.godot/imported`。SpriteFrames 导入在来源工程目录解析依赖，缺失资源由用户定位；读取结束还原临时资源缓存。关卡保存、另存、恢复与 ZIP 沿用版本 1 和原 ID；ZIP 递归包含描述实际使用的图片。

`StageBackgroundLayer.display_name` 是可选的美术显示名称；深度仍决定遮挡位置。对象可选 `occlusion_inherit`：true 沿用父组，false 依据自身 `occlusion_order/depth`；缺失时沿用旧字段解释，旧 `none` 视为继承，旧 front/back 视为明确位置。HUD 不挂入背景。解组把此前有效位置保存为明确配置。

`LevelTransformEdit` 只承担变换候选与提交数据生成，保持区段、难度、时间及插值语义。`LevelShowPlayer` 持有演出对象，`ParallaxController` 的独立 Canvas 只借用挂载；释放与配置清理会归还对象。拾取查询播放器的显示顺序。


## 2026-09-14 编辑器内部约定

关卡和演出格式仍为版本 1。分量提交、粘贴作用域、选区历史和变更影响判断属于编辑器内部能力，不改变歌曲、判定或 Replay 数据。

`LevelDocument` 在提交前整批检查对象、父组及轨道限制。历史可附带前后选区；普通撤销恢复对应区段和难度，不恢复整套旧布局。字段预览合并后一次写入历史，取消恢复文档与控件。

`LevelProjectIO.references` 返回引用及文档路径、对象／轨道／事件／绑定定位信息，覆盖模板与字体键；`dependencies` 递归展开动画描述的图片。普通导入用独立路径表达版本。资源包沿用原描述，已挂载版本切换通过 `--resume-level-session` 读取本地重启会话，恢复文档、历史、保存游标、剪贴板和工作区；该会话不写入正式关卡或运行 ZIP。

`workspace.json` 可选保存轨道筛选、对象搜索、各区段和难度视图、面板显隐与待应用的资源包。恢复稿按关卡 ID 和目录区分；恢复前的未保存文档另留一份，兼容旧单文件恢复稿。

`LevelShowPlayer.refresh_visuals` 重采样外观时保留现有声音；`seek` 是明确时间跳转，会清理旧音。`update_show` 只重建更换类型／素材的对象。一次采样内部复用已求值对象状态，任意时间的锚点查询仍独立求值；没有改变时间函数或插值语义。

后台复制和 ZIP 压缩由 `level_package_job.gd` 协调，文件块间检查取消，工作线程不访问 UI。临时 ZIP 仅在完整关闭后发布，取消不发布半成品。另存未完成时保留原工程为当前工程，已复制的独立资源可留在目标目录中。
# 独立 Spine 骨骼素材（2026-09-15）

工程内 `assets/spine_*/asset.skeleton.json` 是可选素材描述，包含 `format: minghe-spine`、名称、相对骨骼文件、图集、图片页、动作名称与时长、默认动作、显示比例及逐动作出手标记（素材秒）。依赖由 `LevelSpineAsset.dependencies` 接入原有统一枚举，不改变关卡格式版本。

运行时读取原始图片、SpineSkeletonFileResource 和 SpineAtlasResource，构建 PackedScene；对象沿用 `actor`，动作沿用现有 action 轨道。`LevelAnimationDriver` 使用手动骨骼更新，固定 60 Hz 推进；回拖、换动作和改变循环设置重新定位，避免沿用上一动作状态。对象中心取导出骨骼范围中心，显示比例属于素材内部变换。

此入口接受当前运行库兼容的 Spine 4.3 JSON / SKEL，不转换旧版骨骼，不把美术审看工具中的脚本特效自动打包为骨骼动作。

## 编辑与发行核对要点

- 素材导入采用独立路径保留同名原资源；SpriteFrames 的窗口拖放与普通动画导入共用转换及依赖收集，跳过空动作。预览无法读取时不创建不可见对象。骨骼图集与图片随包收集，导出后在隔离目录验证。
- 失败拖入、取消长任务和空选择确认不提交文档命令；失焦提交不得在属性控件已退出树后发生。旧模态窗口退出后才开启下一个窗口。读取无效工程时继续维护当前工程的自动恢复。
- 初始环境及换景应统一控制背景显示宿主，包含随机装饰实例；恢复基础环境不应改写素材自身显隐。
- Ghost 导出关联依赖 `GhostEvent` 的编辑器工具支持及同类型 `PackedStringArray` 初始化。实际发行资源必须保留 `tuning_ids`，验证应加载包内每关并执行 `StageRoot.load_stage`，不能只验证源资源或放宽校验。
- 保留真实入口回归：`run_level_entrypoint_tests.gd`、`run_level_reliability_tests.gd`、`run_level_spriteframes_drop_tests.gd`、`run_level_pack_restart_tests.gd`（均在 `tests/editor`）。验证成功需同时检查完成标记、退出码和引擎错误；真实触摸板、中文组合输入和跨屏 DPI 仍需要人工检查。

内置 BOSS 的发行资源通过 ResourceLoader 读取导入后的纹理、图集及骨骼，不能用原始文件读取接口代替；外部原始骨骼的成功加载不能代表此分支已验证。单一已配置 BOSS 可接收未分配音符，显式绑定优先；多个 BOSS 不自动猜测归属。静息播放不依赖战斗状态。
