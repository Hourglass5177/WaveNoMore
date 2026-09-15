class_name GhostNoteStyle
extends Resource

## Ghost 全局眼睛表现；素材维持共同画布，UV 锚点落在瞳孔中心。
@export var closed_texture: Texture2D
@export var open_texture: Texture2D
@export var closed_glow: Texture2D
@export var open_glow: Texture2D
@export var eye_anchor_uv := Vector2(0.48, 0.35)
@export var width_px := 112.0
@export var halo_width_px := 36.0
@export var bone_color := Color("e6ddc9")
@export var appear_sec := 0.12
## 判定前开始睁眼，完成后保持亮白直到结果反馈。
@export var open_before_sec := 0.72
@export var open_duration_sec := 0.24
@export var closed_glow_strength := 0.13
@export var open_glow_strength := 0.95
@export var closed_surface_light := 0.08
@export var open_surface_light := 0.62
