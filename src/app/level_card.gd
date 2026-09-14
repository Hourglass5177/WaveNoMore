extends Panel

signal clicked

## 背景围绕卡片中心等比缩放，1.0 对应素材原始尺寸。
@export_range(0.01, 10.0, 0.01, "or_greater") var background_scale: float = 1.0:
	set(value):
		background_scale = value
		if is_node_ready(): _update_background_scale()

func _ready() -> void:
	# 卡片共享 shader，但每个实例独立保存 uniform。
	if $MonsterIcon.material is ShaderMaterial:
		$MonsterIcon.material = $MonsterIcon.material.duplicate(false)
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
	$EyeIcon.texture = data.get("eye_icon") as Texture2D
	$Background.texture = (data.get("background") as Texture2D) if data.get("background") != null else data.get("image") as Texture2D
	background_scale = float(data.get("background_scale", background_scale))

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
