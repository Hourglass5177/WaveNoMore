class_name BellVisual
extends Sprite2D

## 只采样表现时间和挥槌接触时刻，不改变真实声波、输入或判定坐标。
const STYLE := preload("res://content/presentation/note_effect_style.tres")
const SURFACE := preload("res://shaders/actors/bell_surface.gdshader")
const HALO := preload("res://shaders/actors/bell_halo.gdshader")
@export var float_period_sec: float = 3.6
@export var halo_width_px: float = 22.0
@export var strike_swing_degrees: float = 2.4
@export var strike_duration_sec: float = 0.38

var _base_position: Vector2
var _base_rotation: float
var _parent_scale: float
var _float_height := 4.0
var _strength := 1.0
var _surface := ShaderMaterial.new()
var _halo_material := ShaderMaterial.new()
var _halo: Sprite2D
var _sample_time := -INF
var _sample_hit := -INF
var _applied_light := -1.0
var strike_light := 0.0

func _ready() -> void:
	_base_position = position
	_base_rotation = rotation
	_parent_scale = (get_parent() as Node2D).scale.abs().y
	_surface.shader = SURFACE
	material = _surface
	_halo_material.shader = HALO
	_halo = Sprite2D.new()
	_halo.name = "Halo"
	_halo.show_behind_parent = true
	_halo.material = _halo_material
	# 复用离线距离场生成器，纹理大小不影响运行时采样次数。
	_halo.texture = load(texture.resource_path.get_basename() + "_glow.png")
	var source_size := float(maxi(texture.get_width(), texture.get_height()))
	_halo.scale = Vector2.ONE * source_size / 192.0
	_halo_material.set_shader_parameter(&"distance_unit_px", source_size * scale.y * _parent_scale / 96.0)
	_halo_material.set_shader_parameter(&"radius_px", halo_width_px)
	add_child(_halo)
	configure(GameplayTypes.Affinity.ZHU, 4.0, 1.0)

func configure(side: int, float_height: float, strength: float) -> void:
	_float_height = float_height
	_strength = strength
	_applied_light = -1.0
	_surface.set_shader_parameter(&"faction_color", STYLE.rim(side))
	_surface.set_shader_parameter(&"white_color", STYLE.white_color)
	_halo_material.set_shader_parameter(&"halo_color", STYLE.halo(side))
	_halo_material.set_shader_parameter(&"rim_color", STYLE.rim(side).lerp(STYLE.white_color, 0.35))
	reset_pose()

func inset(design_px: float) -> void:
	_base_position.x -= design_px / _parent_scale
	position = _base_position

func reset_pose() -> void:
	_sample_time = -INF
	_sample_hit = -INF
	set_visual_time(0.0)

func set_visual_time(time: float, hit_time: float = -INF) -> void:
	if time == _sample_time and hit_time == _sample_hit: return
	_sample_time = time
	_sample_hit = hit_time
	var age := time - hit_time
	var active := age >= 0.0 and age < strike_duration_sec
	var phase := age / strike_duration_sec if active else 1.0
	# 快速受力、一次轻微回摆，末端速度归零；不随帧率累计位移。
	var swing := sin(phase * TAU) * pow(1.0 - phase, 2.0) if active else 0.0
	var angle := deg_to_rad(strike_swing_degrees) * swing
	var pivot := Vector2(0.0, -texture.get_height() * scale.y * 0.33)
	var bob := sin(time * TAU / float_period_sec) * _float_height
	position = _base_position + pivot - pivot.rotated(angle) + Vector2(0.0, bob / _parent_scale)
	rotation = _base_rotation + angle
	strike_light = smoothstep(0.0, 0.018, age) * (1.0 - smoothstep(0.025, 0.24, age)) if active else 0.0
	# 静息时只更新浮动位置，不反复提交相同材质参数。
	if strike_light != _applied_light:
		_applied_light = strike_light
		_surface.set_shader_parameter(&"strike", strike_light * _strength)
		_halo_material.set_shader_parameter(&"strength", (0.42 + strike_light * 0.72) * _strength)
