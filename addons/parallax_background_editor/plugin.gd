@tool
extends EditorPlugin
## 独立主屏幕；不实例化关卡会话，不改变写谱器工作区。
const Workspace = preload("res://addons/parallax_background_editor/workspace.gd")
var workspace: Workspace


func _enter_tree() -> void:
	workspace = Workspace.new()
	workspace.name = "ParallaxBackgroundWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.hide()


func _exit_tree() -> void:
	if is_instance_valid(workspace): workspace.free()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "背景编辑器"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Parallax2D", &"EditorIcons")


func _make_visible(value: bool) -> void:
	if is_instance_valid(workspace):
		workspace.visible = value
		if not value: workspace.surface.cancel_gesture()
		workspace.surface.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED


func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(workspace) and workspace.document.is_dirty():
		return "背景编辑器有未保存修改：" + workspace.document.source_path
	return ""


func _save_external_data() -> void:
	if is_instance_valid(workspace) and workspace.document.is_dirty(): workspace.save_document()
