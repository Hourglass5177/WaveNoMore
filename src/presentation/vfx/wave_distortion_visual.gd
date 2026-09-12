class_name WaveDistortionVisual
extends CanvasLayer

## 整个玩法画面只复制一次。数据直接来自相纹已筛选的波前，不查询领域历史。
const SHADER: Shader = preload("res://shaders/fields/wave_distortion.gdshader")
@export var style: WaveDistortionStyle = preload("res://content/presentation/wave_distortion_style.tres")
var surface := ShaderMaterial.new()
var copy := BackBufferCopy.new()
var pass_rect := ColorRect.new()
var _fronts: Dictionary = {}

func _ready() -> void:
	layer = 3
	surface.shader = SHADER
	pass_rect.material = surface
	pass_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(copy)
	add_child(pass_rect)
	refresh_style()

func bind(field: TuningInterferenceVisual) -> void:
	field.render_fronts_changed.connect(set_fronts)
	set_fronts(field.render_fronts)

func refresh_style() -> void:
	style.apply_to(surface)
	set_fronts(_fronts)

func set_fronts(fronts: Dictionary) -> void:
	_fronts = fronts
	var active := style.enabled and (int(fronts.get("life_wavefront_count", 0)) + int(fronts.get("death_wavefront_count", 0)) > 0)
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if active else BackBufferCopy.COPY_MODE_DISABLED
	pass_rect.visible = active
	if not active: return
	pass_rect.size = fronts.canvas_size
	for key: String in fronts: surface.set_shader_parameter(key, fronts[key])
	sync_transform(transform)

func sync_transform(pose: Transform2D) -> void:
	transform = pose
	# Window 拉伸与编辑器 SubViewport 都以实际目标像素换算偏移。
	var pixels := get_viewport().get_stretch_transform() * pose
	surface.set_shader_parameter(&"pixel_x", pixels.x)
	surface.set_shader_parameter(&"pixel_y", pixels.y)
