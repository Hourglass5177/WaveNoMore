class_name WaveDistortionStyle
extends Resource

## 全局声波折射，仅改变最终像素；距离均为 1920×1080 设计像素。
@export var enabled := true
@export_range(0.0, 40.0, 0.5) var displacement_px := 12.0
## 主波带以真实波前为中心，峰值位于波前，两端连续归零。
@export_range(1.0, 200.0, 1.0) var band_half_width_px := 36.0
@export_range(0.0, 60.0, 0.5) var total_limit_px := 14.0
@export_range(1.0, 300.0, 1.0) var source_fade_px := 120.0
@export_range(0.0, 1.0, 0.01) var far_strength := 0.70
@export_range(1.0, 160.0, 1.0) var edge_fade_px := 64.0
## 从主波带后缘起算的短尾长度；只回弹一次，不生成新的波前。
@export_range(1.0, 300.0, 1.0) var tail_length_px := 32.0
## 短尾相对于主峰的反向位移强度（叠加限幅前）。
@export_range(0.0, 1.0, 0.005) var tail_strength := 0.025

func apply_to(surface: ShaderMaterial) -> void:
	for key: StringName in [&"displacement_px", &"band_half_width_px", &"total_limit_px", &"source_fade_px", &"far_strength", &"edge_fade_px", &"tail_length_px", &"tail_strength"]:
		surface.set_shader_parameter(key, get(key))
