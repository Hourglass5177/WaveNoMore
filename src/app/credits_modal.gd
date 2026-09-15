@tool
extends "res://src/app/ui/art_screen.gd"
## 制作名单保存在可编辑场景；复用弹窗适配、淡入淡出和宿主焦点恢复。
signal close_requested

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	%Back.pressed.connect(func(): close_requested.emit())
	%Back.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		get_node("/root/MenuAudioService").play_ui(&"cancel")
		close_requested.emit()
