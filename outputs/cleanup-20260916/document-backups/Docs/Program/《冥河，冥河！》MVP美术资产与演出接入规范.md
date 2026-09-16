# 《冥河，冥河！》MVP 美术资产与演出接入规范

> 文档状态：接入规范与实现对照，正式素材待交付  
> 更新日期：2026-09-06；原方案日期：2026-08-23  
> 适用范围：Godot MVP、美术交付、技术美术接入、写谱器演出预览

## 当前接入状态（2026-09-06）

工程当前为 Godot 4.7 灰盒原型。下文保留原交付目标；实际接入时，以 `StageVisualTheme`、表现宿主和 ArtLab 已实现接口为准，不将示意资产包名称视为已有类型。

- 逻辑画布 1920×1080；生角色位于左上 (350, 280)，死角色位于右下 (1570, 800)，共同判定点为 (960, 540)。调整波源或判定位置须同步 GameplayRuleSet。
- 世界、角色、边界、音符、Hold、调频、疾振和时机环已有主题场景接入；钟、UI、随从等部分字段尚未完整接入主流程。
- 调频表现已使用有限圆弧、起点收束环、方向与折返提示，并允许多条未来滑条同时预告。频率跨度控制等效弦长，圆弧角度与输入共用 TuningArcGeometry；朝向和视觉偏移可分别配置。
- 相纹由两侧真实传播的载波叠加生成；素音从合法波交点中选择，不能用预摆白点替代领域结果。
- StageShowDirector 已按共同时间轴调度并支持 Seek；灰盒宿主接入教学文字及世界、镜头、VFX 代理，Actor / Audio cue 尚未完整落地。
- ArtLab 已能实例化场景、检查 Marker 与状态动画；当前 graybox_manifest 的 8 项仍为占位素材，正式资产及授权记录待补齐。

现行表现代码与限制见[工程代码导览](./《冥河，冥河！》Godot工程代码导览.md)，素材登记见[素材授权清单](../../Game/ASSET_LICENSES.md)。

## 音符光效接入更新（2026-09-13）

Tap 与 Hold 采用全局统一的漆色与光效资源 `Game/content/presentation/note_effect_style.tres`：生侧为赭红漆色和暖红柔光，死侧保留原图色调并叠加青黑柔光。关卡继续选择素材，不覆盖这套音符光色。

双押 Tap 与被实际调频接管的 Hold 叠加骨白本体提亮。Tap 在接受按键时播放短反馈、暗淡续行，声波真正接触后由保留原纹理的漆片与光尘替换。Hold 在消耗边缘产生稀疏细屑，成功结束时播放较轻的裂解。

PNG 素材替换后，用 `Game/tools/generate_note_glow_masks.py` 生成同目录的 `_glow.png` 距离遮罩；原图、眼球和身体纹样继续保持可替换。所有效果跟随视觉时钟，写谱器和 ArtLab 复用正式表现入口。

完整参数、坐标基准、接口与检查方法见[音符配色与裂解效果](../../Game/docs/note-effects.md)。

## 原接入方案（2026-08-23）

## 1. 目标

现有 Web 3.0 是玩法和时序原型，不是视觉参考。以下内容不复用：

- 酒红色几何底图；
- 圆点、圆环和直线滑槽式音符；
- 原型钟体和 HUD；
- 用 Canvas 图形直接决定最终构图；
- 把相纹固定成白点或几何波圈。

Godot 白模要验证的是一套可承载正式美术的表现骨架。美术决定对象长什么样，程序只定义它何时出现、在哪里、处于什么状态、怎样随玩法参数变化。

## 2. 关卡表现结构

```text
StagePresentationRoot
├─ StageFrame                     1920×1080 逻辑构图
│  ├─ WorldPair
│  │  ├─ LifeWorldRoot           生界，左上
│  │  └─ DeathWorldRoot          死界，右下
│  ├─ WorldGameplayLayer
│  │  ├─ NoteHosts
│  │  ├─ HoldHosts
│  │  └─ EnemyHosts
│  ├─ FieldLayer
│  │  ├─ LifeWaveSlot
│  │  ├─ DeathWaveSlot
│  │  ├─ InterferenceFieldSlot
│  │  └─ RapidFieldSlot
│  ├─ GameplayCueLayer            时机和调频提示，保持正向
│  ├─ ForegroundArt
│  └─ PresentationVfx
├─ HudLayer
└─ ScreenFxLayer
```

生死两界是两个独立实例。基础环境可以将生界结构绕屏幕中心旋转 180° 派生为死界，再叠加死界调色、扰动、遮罩和专用覆盖层。角色、怪物、音符和演出行为互不绑定。

HUD、文字、判定反馈和必要的时机提示保持屏幕正向，不随死界旋转。

## 3. 资产包接口

```text
StageVisualTheme
├─ WorldVisualSet
├─ CharacterVisualSet[life, death]
├─ BellVisualSet[life, death]
├─ NoteVisualSet[zhu, xuan, su, hold]
├─ TuningVisualSet
├─ RapidVisualSet
├─ EnemyVisualSet
├─ FollowerVisualSet
├─ BoundaryVisualSet
├─ VfxPresetBank
├─ UiTheme
└─ DirectorCueLibrary
```

所有主要表现对象用 `PackedScene` 或 Resource 接入。程序向表现宿主提供：

```text
affinity                 朱 / 玄 / 素
approach_progress        0..1
hold_progress            0..1
tune_value               0..1
target_proximity         0..1
region_progress          0..1
rapid_ratio              0..1
judgment_grade
source_anchor
wave_strength
path_transform
```

程序不规定 Tap 必须是圆、鸟、轮、鬼或符咒。美术可以将它设计为怪物、魂魄、器物、异象或投射物，只要场景实现规定状态。

调频提示使用 `TuningGuideSlot`。它可以被画成魂丝、骨裂、星轨、河脉或祭器纹路；程序只提供起点、方向、当前位置、目标值和时间进度，不写死成滑槽。

## 4. 表现对象的最小状态

### 4.1 音符与怪物宿主

每个视觉变体至少响应：

```text
prepare(view_model)
set_approach_progress(value)
set_hold_progress(value)
set_target_proximity(value)
play_judgment(grade)
play_miss()
reset_for_pool()
```

状态名可以由 AnimationPlayer、AnimatedSprite2D、Shader 或组合方式实现。判定层不读取动画当前帧。

### 4.2 角色与编钟

MVP 动画合同：

- `idle_loop`
- `strike`
- `hold_start`
- `hold_loop`
- `hold_release`
- `rapid_loop`
- `damage`
- `fail`
- `stage_intro`
- `stage_outro`

角色场景必须提供：

- `wave_origin`
- `mallet_tip`
- `body_center`
- `hit_fx_anchor`
- `follower_anchor`

动画事件只触发表现和音效。判定时机来自谱面，不从动画 Call Method 反推。

## 5. 各类素材怎样制作和交付

| 对象 | Godot 侧实现 | 美术交付 |
| --- | --- | --- |
| 场景 | 分层 Sprite2D、Parallax2D、AnimationPlayer、CanvasItem Shader | 分层 PSD/CLIP 源文件；导出透明 PNG、遮罩和调色参考 |
| 生死角色 | Bone2D/Skeleton2D + AnimationPlayer，关键姿势局部换帧 | 分件 PNG、绑定姿势图、锚点表、关键姿势替换层 |
| 编钟 | 分层 Sprite2D + AnimationPlayer + Shader | 钟体、钟口、内阴影、辉光遮罩、槌和握点 |
| Tap | 可替换 PackedScene | 主体、轮廓/发光遮罩、受击层、碎片；不烘焙进度提示 |
| Hold | Line2D/Polygon2D 生成长度 | 头部、尾部、可平铺中段、中心纹和遮罩 |
| 素音与调频引导 | 可替换 VisualSet + 程序曲线 | 目标主体、魂丝/骨裂/星轨等引导纹理、发光和破碎层 |
| 相纹 | 低分辨率内部场 + Shader/材质重构 | 点描、刮擦、骨白笔刷、噪声、流场、遮罩和调色板 |
| 疾振 | 程序按交替数叠加结构 | 纹核/白茧、丝线、节点、裂纹阶段、碎屑和爆发图层 |
| 小型怪物 | AnimatedSprite2D 或少量分件 | 同枢轴序列帧，或分件 PNG |
| 大型怪物 | 分件动画 + 局部手绘换帧 | 分件、关键姿势、破坏阶段、特效遮罩 |
| 随从 | 短序列或小型分件 | 基础/进阶形态、图标、待机、触发和获得演出 |
| UI | Control、Theme、NinePatchRect | 九宫格面板、按钮状态、印章、图标、字体及许可证 |
| 瞬时 VFX | GPUParticles2D、翻页图集、Shader | 骨屑、朱砂、灰烬、水滴、闪光等小图集和遮罩 |
| 动态线、路径、波场 | `_draw()`、Line2D、Shader | 可平铺线条/笔刷纹理；不逐帧绘制 |

复杂 Gameplay VFX 不交付 MP4。视频只适合一次性片头、幕后参考或确定不需互动的背景片段。

## 6. 角色采用混合动画

纯逐帧工作量过高，纯骨骼容易出现廉价纸片感。MVP 使用混合方案：

- 身体、头、上下臂、手、槌、裙片、发饰、巫帛分件；
- 身体和硬质部件使用刚性 Bone2D；
- 衣摆、袖口和流苏只在必要处使用 Polygon2D 蒙皮；
- 击钟瞬间、受击和高潮姿势可替换 2～3 张手绘关键帧；
- AnimationPlayer 管理状态，MVP 不先引入复杂 AnimationTree。

生死角色优先共享骨架和动画库，换皮肤、轮廓和材质。若最终形体差异较大，两侧也可以分别提供完整场景，运行时接口不变。

第一件角色资产应是一套精修的 `strike`。若击钟动作、槌点和钟体反馈达不到预期，先调整动画管线，不批量拆角色。

## 7. 场景资产

每关建议使用 6～8 类层：

1. 底色与纸张、水汽纹理；
2. 远景天象、山和月；
3. 中景建筑、祭柱、林木；
4. 地表或水下结构；
5. 近景草木、枝杈、墓葬构件；
6. 前景遮挡；
7. 可单独演出的关卡核心物；
8. 可选的雾、雨、魂屑遮罩。

不要为一首 90 秒歌曲绘制一张超长背景。使用可循环层、2～4 个模块段和少量重点场景，由 `StageShow` 在音乐段落中切换、移动、调色和显隐。

中心分界是 `BoundaryVisualSet`，程序只提供 `song_progress` 和状态。它可以是河面、漆裂、绳索、祭纹或黑色空隙，不固定为直线进度条。

## 8. 相纹 Renderer

相纹由两部分组成：

1. 程序生成的场或遮罩，输入是双源锚点、强度、调频值、区域进度和目标接近度；
2. 美术材质重构，将场变成笔刷、骨白、潮湿刮擦、魂丝或其他造型。

建议在四分之一或三分之一分辨率的内部 Viewport 计算，再放大合成。低、中、高画质调整内部采样率和粒子数量。

相纹只读取判定状态，绝不通过像素碰撞决定命中。Shader 失效时，游戏仍能给出完全相同的成绩。

## 9. 参考画布与运行时规格

- 逻辑构图：1920×1080。
- 场景源文件建议按 2560×1440 或更高制作，中心 1920×1080 是关键构图区。
- 超宽屏外围只放可裁切或可延展氛围，不把判定对象移到安全区外。
- 运行时贴图使用 sRGB、8 位、直通 Alpha。
- UI、角色和细线素材优先 Lossless；大型背景是否使用 VRAM 压缩，以目标机测试决定。
- 单张运行时贴图最大边建议不超过 4096。
- 小特效图集使用 512² 或 1024²。
- SVG 只用于结构简单的印章、图标和线形 UI；复杂笔刷使用 PNG。

建议初始尺寸：

| 对象 | 游戏内显示 | 导出有效尺寸 |
| --- | ---: | ---: |
| 主角 | 高 240～360 px | 高 600～800 px |
| 编钟 | 180～260 px | 约 512 px |
| 普通目标 | 80～160 px | 256～384 px |
| 随从 | 80～140 px | 256～384 px |
| UI 图标 | 依界面 | 最终显示尺寸 2 倍 |

这些值是首轮模板，不是永久限制。美术尖峰通过后再冻结最终尺寸。

## 10. 锚点与 Manifest

每份可交互素材至少记录：

```text
pivot
visual_bounds
wave_origin
hit_anchor
attach_anchor
facing_direction
progress_anchor（可选）
```

美术不必手写 Godot Resource。美术提交源文件、导出文件、绑定姿势图和锚点示意；程序或技术美术将其录入 `VisualAssetManifest.tres`。

裁切贴图后不得凭肉眼重新摆位置。导入校验器读取 Manifest，检查尺寸、枢轴、动画帧画布和必需锚点。

## 11. 目录与命名

绘画源文件放在 Godot 工程外，避免自动导入 PSD/CLIP：

```text
ArtSource/
├─ _templates/
├─ characters/
├─ stages/
├─ notes/
├─ enemies/
├─ followers/
├─ ui/
└─ vfx/
```

运行时只放导出物和 Godot 资源：

```text
Game/assets/art/
├─ common/
├─ characters/
├─ stages/s01/
├─ stages/s02/
├─ notes/
├─ enemies/
├─ followers/
├─ ui/
└─ vfx/

Game/content/visual/
├─ characters/
├─ stages/
├─ note_sets/
├─ followers/
└─ vfx_banks/
```

运行时文件名使用 ASCII `snake_case`，版本交给版本管理和 Manifest，不写进文件名：

```text
chr_life_torso.png
bell_death_body.png
note_zhu_tap_a.png
vfx_su_contact_atlas.png
pet_jiao_advanced_body.png
```

序列帧共用同一画布和枢轴，使用 `_f0001` 递增。透明前景紧裁；需要共用画布的动画帧不得各自紧裁。

PSD、CLIP、WAV 和视频参考建议走 Git LFS；`.godot/` 不入库，Godot 生成的 `.import` 设置需要入库。

## 12. 程序驱动演出

`StageShow` 只保存 cue 和参数：

- `actor_animation`
- `spawn_visual`
- `world_state`
- `palette_change`
- `camera_cue`
- `boundary_state`
- `vfx_cue`
- `screen_fx`
- `tutorial_cue`

cue 引用 `DirectorCueLibrary` 中的稳定 ID，不引用深层 NodePath。美术可以在不改谱面的情况下替换 cue 对应的场景、动画和材质。

命中反馈按强度分为小、中、大三档。它们组合声音、角色动作、材质闪烁、碎片、局部震动和短暂形变。音游不能用 `Engine.time_scale` 停止歌曲时钟；所谓顿帧只能冻结局部角色或特效，BGM、输入和判定继续运行。

## 13. ArtLab 与白模

新建 `ArtLab.tscn`，不依赖完整歌曲即可预览：

- 生/死角色和编钟的全部状态；
- 朱、玄、素、Hold、调频和疾振；
- Perfect、Good、Pass、Miss；
- 随从基础/进阶形态和被动触发；
- 不同背景亮度和遮挡压力；
- 16:9、20:9、16:10、安全区；
- 低、中、高画质。

白模使用 `GrayboxVisualTheme`，但不再画 Web 原型式圆点和滑槽。它至少包含：

- 灰阶手绘场景分层；
- 最终尺寸的生/死角色剪影；
- 三类可替换音符宿主；
- 可换笔刷和遮罩的相纹 Renderer；
- 使用头、中、尾素材的 Hold 几何；
- 最终层级、锚点、遮挡和安全区；
- 纸纹、墨蚀、水面扰动和骨白辉光的材质代理。

白模以“替换美术素材后无需改场景结构和玩法代码”为成功标准。

## 14. 美术尖峰

正式批量制作前，完成一段 10～15 秒的近成片片段：

- 一次朱 Tap；
- 一次玄 Hold；
- 一次素调频；
- 一段疾振高潮；
- 一次 Miss 掉血；
- 一次随从被动触发；
- 一次场景 cue 和镜头 cue。

该片段同时验证角色、场景、音符、相纹、读谱和移动端性能。如果结构容纳不了美术，在这里改；不要等整关做完再返工。

## 15. MVP 美术包建议

### 通用包

- 生/死主角各 1 套；
- 生/死编钟各 1 套；
- 朱/玄/素各 1 个基础视觉族；
- Hold、调频、疾振各 1 套系统表现；
- 共用判断反馈、魂火、UI 和随从触发 VFX；
- 共用纸纹、噪声、笔刷和调色资源。

### 每关专用包

- 1 套分层场景；
- 1 个重点怪物或核心异象；
- 少量普通目标变体；
- 1 个随从的基础和进阶形态；
- 1 套关卡调色与 cue 库；
- 1 张选关封面和结算图。

第一关完整精修。第二关优先复用角色、钟、音符宿主、UI 和 VFX，只替换场景、重点怪物、调色和随从。

## 16. 工作量边界

- 普通音符与怪物演出解耦，不要求每个音符都是一只全动画怪物。
- 生死世界共享结构，差异优先由覆盖层、调色和材质表现。
- Hold 长度、相纹密度和疾振层数由程序生成。
- 背景变化优先使用层移动、遮罩、调色和 Shader。
- 随从进阶优先增加轮廓、纹样、饰物和特效，不重做整套动画。
- 一关只安排一个重点异象，其余使用少量视觉族组合。
- 美术不直接修改玩法节点；表现场景通过稳定 ID、节点组或标记连接。

## 17. 风险与检查

| 风险 | 对策 |
| --- | --- |
| 相纹、透明背景和粒子造成 fill-rate 压力 | 相纹低分辨率渲染；限制全屏透明层；提供质量档 |
| 死界文字和提示倒置 | 世界美术与 GameplayCue/HUD 分层 |
| 骨骼动画出现廉价木偶感 | 先做精修击钟尖峰；关键帧局部替换 |
| 裁切破坏枢轴和动画 | Manifest + 导入校验器 |
| 美术改场景树导致 NodePath 失效 | 稳定 ID、节点组、标记和薄适配器 |
| 演出遮挡读谱 | GameplayCue 保护层；高潮时动态压低背景对比 |
| 视觉变体影响判定 | 判定不读取像素、碰撞、动画帧和 Shader |
| Renderer 能力差异 | 以当前 GL Compatibility 为最低基线；重效果先做目标机尖峰 |

## 18. 接入验收

一套资产进入正式内容前必须满足：

1. 在 ArtLab 中通过三种画幅和三档画质预览。
2. 必需状态、锚点、动画名和 VisualSet 引用完整。
3. 朱、玄、素在静止、运动和强 VFX 下仍可辨识。
4. 替换 Graybox 资源不需要改共享核心和判定代码。
5. Perfect、Miss、掉血和疾振高潮的反馈强弱有明确层级。
6. 贴图尺寸、透明 overdraw 和 GPU 帧时在目标机内可接受。
7. 写谱器能加载该主题并预览全部 cue。
