class_name TimingCueStyle
extends Resource

## 全局计时提示参数；色板复用音符资源，不写入谱面。
@export var note_style: NoteEffectStyle
## 仅作用于 Tap/Hold 整套圆环，与判定淡出相乘，不影响调频缩圈。
@export_range(0.0, 1.0, 0.01) var note_opacity: float = 0.90
@export_range(0.0, 1.0, 0.01) var white_mix: float = 0.30
## 提示比本体稍偏青绿／暖铜，仍从同一音符色板派生。
@export_range(-0.1, 0.1, 0.005) var life_hue_shift: float = -0.045
@export_range(-0.1, 0.1, 0.005) var death_hue_shift: float = 0.025
@export var progress_width: float = 6.0
@export var approach_width: float = 3.0
@export var approach_alpha_start: float = 0.45
@export var approach_alpha_end: float = 0.75
@export var progress_glow_width: float = 10.0
@export var progress_glow_strength: float = 0.55
@export var approach_glow_width: float = 8.0
@export var approach_glow_strength: float = 0.40
@export var glow_enabled: bool = true

func line_color(side: int) -> Color:
	return _shift(note_style.rim(side), side).lerp(note_style.white_color, white_mix) if side != GameplayTypes.Affinity.SU else note_style.white_color

func halo_color(side: int) -> Color:
	return _shift(note_style.halo(side), side) if side != GameplayTypes.Affinity.SU else note_style.white_color

func _shift(color: Color, side: int) -> Color:
	var offset := death_hue_shift if side == GameplayTypes.Affinity.XUAN else life_hue_shift
	return Color.from_hsv(fposmod(color.h + offset, 1.0), color.s, color.v, color.a)

func approach_alpha(progress: float) -> float:
	return lerpf(approach_alpha_start, approach_alpha_end, smoothstep(0.0, 1.0, progress))
