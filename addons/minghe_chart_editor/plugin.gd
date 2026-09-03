## Godot 编辑器插件入口。它只负责把写谱工作区挂进主编辑区，并在插件卸载前留下恢复副本。
@tool
extends EditorPlugin

## 插件启用后实例化的写谱器主界面场景。
const WORKSPACE_SCENE := preload("res://scenes/tools/chart_editor/chart_editor_workspace.tscn")

## 当前挂在 Godot 主编辑区中的工作区；禁用插件时必须释放。
var _workspace: MingheChartEditorWorkspace


func _enter_tree() -> void:
	# 启用插件时 Godot 调用 _enter_tree()：此处只创建唯一工作区，不打开谱面或启动预览。
	_workspace = WORKSPACE_SCENE.instantiate() as MingheChartEditorWorkspace
	if _workspace == null:
		push_error("[MingheChartEditor] 无法实例化 ChartEditorWorkspace")
		return
	_workspace.name = "MingheChartEditorMainScreen"
	EditorInterface.get_editor_main_screen().add_child(_workspace)
	_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)


func _exit_tree() -> void:
	# 禁用插件或关闭编辑器时 Godot 调用 _exit_tree()：先写恢复稿，再释放 UI。
	if _workspace != null:
		_workspace.write_recovery()
		_workspace.queue_free()
		_workspace = null


func _has_main_screen() -> bool:
	# 返回 true 后，Godot 会把本插件当作 2D、3D、Script 同级的主屏幕。
	return true


func _make_visible(visible: bool) -> void:
	if _workspace != null:
		_workspace.visible = visible
		if visible:
			_workspace.grab_focus()


func _get_plugin_name() -> String:
	return "冥河写谱器"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"AudioStreamPlayer", &"EditorIcons")


func _save_external_data() -> void:
	# Godot 的「保存全部」回调不会直接覆盖正式谱面，只更新可恢复副本。
	if _workspace != null and _workspace.has_unsaved_changes():
		_workspace.write_recovery()
