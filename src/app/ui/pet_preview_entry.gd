class_name PetPreviewEntry
extends Resource
## 菜单展示专用资源，预览大小不反向影响关卡内的随从。
@export var pet_id: String
@export var heading: Texture2D
@export var scene: PackedScene
@export var preview_scale := 4.2
@export var preview_offset := Vector2.ZERO

@export_group("预览投影")
@export var shadow_color := Color("c83050")
@export var shadow_size := Vector2(460,104)
@export var shadow_position := Vector2(960,641)
@export_range(0.0,1.5,0.05) var shadow_strength := 0.85
