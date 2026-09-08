@tool
class_name PetDefinition
extends Resource
## 身份、两阶技能和美术入口。技能参数与局内场景各自替换，互不依赖。
@export var pet_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_multiline var base_description: String = ""
@export_multiline var advanced_description: String = ""
@export var base_effect: PetEffectProfile
@export var advanced_effect: PetEffectProfile
@export var base_icon: Texture2D
@export var advanced_icon: Texture2D
@export var base_scene: PackedScene
@export var advanced_scene: PackedScene
## 1920×1080 设计坐标中相对生界角色的偏移；死界由父级中心对称变换。
@export var world_offset := Vector2(-96, 70)
@export var world_scale: float = 1.0

func effect(advanced: bool) -> PetEffectProfile:
	var profile := advanced_effect if advanced else base_effect
	return profile.duplicate(true) as PetEffectProfile if profile != null else PetEffectProfile.new()

func icon(advanced: bool) -> Texture2D:
	return advanced_icon if advanced and advanced_icon != null else base_icon

func visual_scene(advanced: bool) -> PackedScene:
	return advanced_scene if advanced and advanced_scene != null else base_scene
