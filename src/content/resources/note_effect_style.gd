class_name NoteEffectStyle
extends Resource

## 所有关卡共用的音符视觉语言；不写入谱面，也不参与判定。
@export var enabled: bool = true
@export_group("生音符")
@export var life_shadow := Color("45201f")
@export var life_base := Color("87382e")
@export var life_highlight := Color("ba5841")
@export var life_halo := Color("ad4638")
@export_group("死音符")
@export var death_halo := Color("102a2c")
@export var death_rim := Color("416466")
@export_group("柔光")
@export var halo_width_px: float = 36.0
@export var rim_width_px: float = 3.0
@export var halo_strength: float = 0.80
@export var surface_strength: float = 0.18
@export var white_color := Color("e6ddc9")
@export var white_strength: float = 0.48
@export var tap_lead_sec: float = 0.60
@export var tap_rise_sec: float = 0.15
@export var hold_rise_sec: float = 0.10
@export var fall_sec: float = 0.08
@export_group("命中与裂解")
@export var hit_sec: float = 0.08
@export var accepted_brightness: float = 0.45
@export var crack_sec: float = 0.03
@export var shard_sec: float = 0.26
@export var dust_sec: float = 0.34
@export var shard_count: int = 8
@export var dust_count: int = 12
@export var spread_px: float = 66.0
@export var hold_finish_sec: float = 0.24
@export var hold_shard_count: int = 5
@export var hold_dust_count: int = 6
@export var consume_spacing_px: float = 24.0

func halo(side: int) -> Color:
	return death_halo if side == GameplayTypes.Affinity.XUAN else life_halo

func rim(side: int) -> Color:
	return death_rim if side == GameplayTypes.Affinity.XUAN else life_highlight

func apply_to(target: ShaderMaterial, side: int) -> void:
	## 只在装配或换阵营时同步静态色板，逐帧仅更新强度和事件年龄。
	target.set_shader_parameter(&"effects_enabled", enabled)
	target.set_shader_parameter(&"life_tint", side == GameplayTypes.Affinity.ZHU)
	target.set_shader_parameter(&"lacquer_shadow", life_shadow)
	target.set_shader_parameter(&"lacquer_base", life_base)
	target.set_shader_parameter(&"lacquer_highlight", life_highlight)
	target.set_shader_parameter(&"surface_color", rim(side))
	target.set_shader_parameter(&"surface_strength", surface_strength)
	target.set_shader_parameter(&"white_color", white_color)
	target.set_shader_parameter(&"white_strength", white_strength)
