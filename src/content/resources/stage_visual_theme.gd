## 单关美术装配表。替换这里的 PackedScene 和色板即可换关，不应为新关复制玩法脚本。
@tool
class_name StageVisualTheme
extends Resource

@export_group("Identity")
## 主题稳定 ID，供关卡组合与调试工具识别；不影响判定。
@export var theme_id: String = "graybox"

@export_group("World")
## 生界背景的可实例化场景；应按设计画布制作。
@export var life_world_scene: PackedScene
## 死界背景的可实例化场景；通常与生界保持中心对称构图。
@export var death_world_scene: PackedScene
## 生死分界线及关卡进度表现的场景。
@export var boundary_scene: PackedScene
## 模拟摄像头的持续速度，单位为设计像素/秒；按绝对歌曲时间采样。
@export var camera_velocity: Vector2 = Vector2.ZERO

@export_group("Actors")
## 位于左上生界的生角色场景。
@export var life_actor_scene: PackedScene
## 位于右下死界的死角色场景。
@export var death_actor_scene: PackedScene
## 将生死角色放入背景深度 0 的 actors 子层，便于由背景子层顺序安排遮挡。
@export var actors_in_parallax: bool = false
## 生角色使用的编钟场景。
@export var life_bell_scene: PackedScene
## 死角色使用的编钟场景。
@export var death_bell_scene: PackedScene

@export_group("Gameplay Visuals")
## 朱（生）Tap 音符场景；留空时由表现层使用 Graybox 默认物。
@export var zhu_note_scene: PackedScene
## 玄（死）Tap 音符场景；留空时使用 Graybox 默认物。
@export var xuan_note_scene: PackedScene
## 朱（生）默认 Tap 图片；拖入 PNG/WebP 等 Texture2D 后替换程序绘制。
@export var zhu_tap_texture: Texture2D
## 朱（生）Tap 的 ShaderMaterial；为空时使用默认材质。
@export var zhu_tap_material: ShaderMaterial
## 朱（生）Tap 是否绘制常驻透明边缘泛光。
@export var zhu_tap_glow_enabled: bool = true
## 朱（生）Tap 的边缘泛光颜色。
@export var zhu_tap_glow_color: Color = Color("f24033")
## 玄（死）默认 Tap 图片；拖入 PNG/WebP 等 Texture2D 后替换程序绘制。
@export var xuan_tap_texture: Texture2D
## 玄（死）Tap 的 ShaderMaterial；为空时使用默认材质。
@export var xuan_tap_material: ShaderMaterial
## 玄（死）Tap 是否绘制常驻透明边缘泛光。
@export var xuan_tap_glow_enabled: bool = true
## 玄（死）Tap 的边缘泛光颜色。
@export var xuan_tap_glow_color: Color = Color("5973bf")
## 素音动态凝现场景；留空时使用 Graybox 默认物。
@export var su_note_scene: PackedScene
## Hold 的头、身、尾组合场景。
@export var hold_scene: PackedScene
## 生界默认 Hold 头部图片；仅作用于使用 GrayboxHoldVisual 的默认场景。
@export var zhu_hold_head_texture: Texture2D
## 死界默认 Hold 头部图片；仅作用于使用 GrayboxHoldVisual 的默认场景。
@export var xuan_hold_head_texture: Texture2D
## 朱（生）Hold 头部、身体和尖尾是否绘制常驻边缘泛光。
@export var zhu_hold_glow_enabled: bool = true
## 朱（生）Hold 完整轮廓的边缘泛光颜色。
@export var zhu_hold_glow_color: Color = Color("f24033")
## 玄（死）Hold 头部、身体和尖尾是否绘制常驻边缘泛光。
@export var xuan_hold_glow_enabled: bool = true
## 玄（死）Hold 完整轮廓的边缘泛光颜色。
@export var xuan_hold_glow_color: Color = Color("5973bf")
## 调频滑槽与引导场景。
@export var tuning_scene: PackedScene
## 双钟疾振区域的表现场景。
@export var rapid_scene: PackedScene
## 音符圆形时机进度环场景。
@export var timing_ring_scene: PackedScene

@export_group("Palette")
## 生界及生波主色；改变只影响表现。
@export var life_color: Color = Color("b93a31")
## 死界及死波主色；改变只影响表现。
@export var death_color: Color = Color("242738")
## 素音与双波叠加使用的中性色。
@export var su_color: Color = Color("e4ddc8")
## 深色描边、阴影和墨迹的基准色。
@export var ink_color: Color = Color("0a0d14")
## 浅色底面和低强调元素的基准色。
@export var paper_color: Color = Color("6d7180")

@export_group("UI")
## 本关 UI Theme；为空时使用项目全局默认主题。
@export var ui_theme: Theme
