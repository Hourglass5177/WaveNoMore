## 一项美术交付规范：既记录运行时场景，也声明 Pivot、可视边界、锚点和必须支持的状态。
@tool
class_name VisualAssetEntry
extends Resource

## 资产稳定 ID；美术清单和运行时槽位靠它查找本条目。
@export var asset_id: String = ""
## 资产分类键，例如 actor 或 note；用于校验和 ArtLab 筛选。
@export var category: StringName = &""
## 美术源文件路径，仅用于追溯交付物，不在运行时实例化。
@export_file var source_file: String = ""
## 游戏实际实例化的 Godot 场景。
@export var runtime_scene: PackedScene
## 素材对齐原点，单位本地像素；X/Y 增大分别向右/向下偏移。
@export var pivot: Vector2 = Vector2.ZERO
## 预期可视边界，单位本地像素；宽高越大，声明的占屏范围越大。
@export var visual_bounds: Rect2 = Rect2(-128, -128, 256, 256)
## 锚点名到本地坐标或节点路径；节点路径会采样出手帧的动画位置。
@export var anchors: Dictionary = {}
## 素材默认朝向向量；X 正为向右、Y 正为向下，长度通常保持 1。
@export var facing_direction: Vector2 = Vector2.RIGHT
## 场景实际提供的动画/状态名称列表。
@export var state_names: PackedStringArray = []
## 供关卡时间线使用的动作标记，例如 attack: {release_sec: 0.24}。
@export var action_markers: Dictionary = {}
## 仅这些参数向策划开放；键为名称，值声明 node_path、property、默认值与范围。
@export var exposed_parameters: Dictionary = {}
## 清单在素材库中的名称和缩略图，不改变资产的稳定 ID。
@export var display_name: String = ""
@export var thumbnail: Texture2D
## 此资产类型必须具备的锚点名；缺少任一项即不满足交付规范。
@export var required_anchors: PackedStringArray = []
## 此资产类型必须具备的动画/状态名；缺少任一项即不满足交付规范。
@export var required_states: PackedStringArray = []
## 是否仍是占位资产；开启时发布校验可将其标为未完成。
@export var placeholder: bool = true
