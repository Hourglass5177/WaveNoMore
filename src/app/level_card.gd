extends Panel

signal clicked
var _effect_frames: SpriteFrames
var _effect_animation := &"default"
var _effect_frame := 0
var _effect_elapsed := 0.0
var _effect_scale := 1.0
var _effect_offset := Vector2.ZERO
var _eye_selected: Texture2D
var _eye_unselected: Texture2D

## 背景围绕卡片中心等比缩放，1.0 对应素材原始尺寸。
@export_range(0.01, 10.0, 0.01, "or_greater") var background_scale: float = 1.0:
	set(value):
		background_scale = value
		if is_node_ready(): _update_background_scale()

func _ready() -> void:
	set_process(false)
	resized.connect(_layout_effect)
	# 卡片共享 shader，但每个实例独立保存 uniform。
	if $MonsterIcon.material is ShaderMaterial:
		$MonsterIcon.material = $MonsterIcon.material.duplicate(false)
	if $Background.material is ShaderMaterial:
		$Background.material = $Background.material.duplicate(false)
	if $BackgroundEffect.material is ShaderMaterial:
		$BackgroundEffect.material = $BackgroundEffect.material.duplicate(false)
	$Background.resized.connect(_update_background_scale)
	_update_background_scale()

## 在卡片布局尺寸改变后同步缩放中心，避免背景偏移。
func _update_background_scale() -> void:
	$Background.pivot_offset = $Background.size * 0.5
	$Background.scale = Vector2.ONE * background_scale

func configure(data: Dictionary, index: int) -> void:
	$Score.text = "%02d  %s" % [index + 1, str(data.get("score", ""))]
	$Rating.text = str(data.get("rating", data.get("title", "未命名关卡")))
	$Description.text = str(data.get("description", ""))
	$MonsterIcon.texture = data.get("monster_icon", data.get("image")) as Texture2D
	_eye_selected = data.get("eye_icon_selected") as Texture2D
	_eye_unselected = data.get("eye_icon_unselected") as Texture2D
	$EyeIcon.texture = _eye_unselected if _eye_unselected != null else _eye_selected
	$Background.texture = (data.get("background") as Texture2D) if data.get("background") != null else data.get("image") as Texture2D
	background_scale = float(data.get("background_scale", background_scale))
	_effect_frames = data.get("background_effect_frames") as SpriteFrames
	var animation_value: Variant = data.get("background_effect_animation", "default")
	_effect_animation = StringName(str(animation_value)) if animation_value != null and not str(animation_value).is_empty() else &"default"
	var scale_value: Variant = data.get("background_effect_scale", 1.0)
	_effect_scale = float(scale_value) if scale_value != null and is_finite(float(scale_value)) and float(scale_value) > 0.0 else 1.0
	var offset_value: Variant = data.get("background_effect_offset", Vector2.ZERO)
	_effect_offset = offset_value if offset_value is Vector2 else Vector2.ZERO
	_effect_frame = 0; _effect_elapsed = 0.0; _update_effect_frame()
	set_process(_effect_frames != null and _effect_frames.has_animation(_effect_animation) and _effect_frames.get_frame_count(_effect_animation) > 0 and _effect_frames.get_animation_speed(_effect_animation) > 0.0)
	_layout_effect()

func _process(delta: float) -> void:
	if _effect_frames == null or not _effect_frames.has_animation(_effect_animation): return
	_effect_elapsed += delta
	var speed := _effect_frames.get_animation_speed(_effect_animation)
	var frame_count := _effect_frames.get_frame_count(_effect_animation)
	if speed <= 0.0 or frame_count == 0: return
	var duration := _effect_frames.get_frame_duration(_effect_animation, _effect_frame) / speed
	var changed := false
	# 保留不足一帧的余量；长帧跨过多张素材时补齐，火框播放速度不随 FPS 改变。
	while _effect_elapsed >= duration:
		_effect_elapsed -= duration
		if _effect_frame == frame_count-1 and not _effect_frames.get_animation_loop(_effect_animation):
			set_process(false)
			break
		_effect_frame = (_effect_frame+1)%frame_count
		changed = true
		duration = _effect_frames.get_frame_duration(_effect_animation, _effect_frame) / speed
	if changed: _update_effect_frame()

func _update_effect_frame() -> void:
	if _effect_frames == null or not _effect_frames.has_animation(_effect_animation) or _effect_frames.get_frame_count(_effect_animation) == 0:
		$BackgroundEffect.texture = null; return
	$BackgroundEffect.texture = _effect_frames.get_frame_texture(_effect_animation, _effect_frame)
	_layout_effect()

func _layout_effect() -> void:
	if $BackgroundEffect.texture == null: return
	var texture_size: Vector2 = $BackgroundEffect.texture.get_size()
	# 尺寸保持纹理原始大小，倍率只作用于渲染变换，避免 TextureRect 布局刷新覆盖缩放。
	$BackgroundEffect.size = texture_size
	$BackgroundEffect.pivot_offset = texture_size * 0.5
	$BackgroundEffect.scale = Vector2.ONE * _effect_scale
	$BackgroundEffect.position = size * 0.5 - texture_size * 0.5 + _effect_offset

## 供轮播或编辑器在运行中修改特效倍率，并立即应用到当前帧。
func set_background_effect_scale(value: float) -> void:
	_effect_scale = value if is_finite(value) and value > 0.0 else 1.0
	_layout_effect()

## 接收轮播平滑计算的中心权重，同步当前卡片的怪物透明度与背景 k。
func set_selection_weight(weight: float) -> void:
	var icon_material := $MonsterIcon.material as ShaderMaterial
	if icon_material != null:
		icon_material.set_shader_parameter("image_transparency", clampf(weight, 0.0, 1.0))
	var background_material := $Background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("k", clampf(weight, 0.0, 1.0))
	var effect_material := $BackgroundEffect.material as ShaderMaterial
	if effect_material != null:
		effect_material.set_shader_parameter("k", clampf(weight, 0.0, 1.0))
	$EyeIcon.texture = _eye_selected if weight >= 0.5 and _eye_selected != null else _eye_unselected

## 重构后的卡片不含锁定遮罩；使用提示，并转交材质支持的锁定效果。
func set_locked(value: bool) -> void:
	tooltip_text = "未解锁" if value else ""
	set_locked_shader_state(value)

## 仅向声明了 locked 参数的怪物材质传值，不修改其他美术参数。
func set_locked_shader_state(value: bool) -> void:
	var icon_material := $MonsterIcon.material as ShaderMaterial
	if icon_material == null or icon_material.shader == null: return
	for uniform in icon_material.shader.get_shader_uniform_list():
		if uniform.name == "locked":
			icon_material.set_shader_parameter("locked", value)
			return

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit()
