extends Panel

signal clicked

func configure(data: Dictionary, index: int) -> void:
	$Number.text = "%02d" % (index + 1)
	$Title.text = str(data.get("title", "未命名关卡"))
	$Description.text = str(data.get("description", ""))
	$Image.texture = data.get("image") as Texture2D

func set_locked(value: bool) -> void:
	$Locked.visible = value
	$LockedOverlay.visible = value
	set_locked_shader_state(value)

func set_locked_shader_state(value: bool) -> void:
	if $Image.material is ShaderMaterial:
		$Image.material.set_shader_parameter("locked", value)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit()
