class_name WaveDistortionStyle
extends Resource

## 全局声波折射，仅改变最终像素；距离均为 1920×1080 设计像素。
@export var enabled := true
@export_range(0.0, 8.0, 0.1) var displacement_px := 2.0
@export_range(1.0, 100.0, 1.0) var band_half_width_px := 24.0
@export_range(0.0, 8.0, 0.1) var total_limit_px := 3.0
@export_range(1.0, 300.0, 1.0) var source_fade_px := 48.0
@export_range(0.0, 1.0, 0.01) var far_strength := 0.35
@export_range(1.0, 100.0, 1.0) var edge_fade_px := 24.0

func apply_to(surface: ShaderMaterial) -> void:
	for key: StringName in [&"displacement_px", &"band_half_width_px", &"total_limit_px", &"source_fade_px", &"far_strength", &"edge_fade_px"]:
		surface.set_shader_parameter(key, get(key))
