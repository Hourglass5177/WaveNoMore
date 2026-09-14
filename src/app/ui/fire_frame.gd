@tool
extends TextureRect
## 透明边框共用贴图，按 UI 时间播放，玩法暂停不冻结菜单。
@export var frames_per_second := 12.0
var _time := 0.0
var _frame := -1
var _textures: Array[Texture2D] = []
func _ready() -> void:
	for index in range(1,9):
		_textures.append(load("res://assets/ui/art/粉焰火框_8帧_透明PNG/粉焰火框_%02d.png" % index))
	texture = _textures[0]
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree(): return
	_time += delta
	var index := int(_time*frames_per_second)%8
	if index != _frame:
		_frame = index
		texture = _textures[index]
