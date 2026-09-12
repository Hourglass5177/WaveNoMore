@tool
extends EditorPlugin
var source_dialog: EditorFileDialog
var destination_dialog: EditorFileDialog
var message_dialog: AcceptDialog
var manifest_path := ""

func _enter_tree() -> void:
	source_dialog = EditorFileDialog.new()
	source_dialog.title = "选择要交付的素材清单"; source_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	source_dialog.filters = PackedStringArray(["*.tres ; 美术素材清单"])
	get_editor_interface().get_base_control().add_child(source_dialog)
	source_dialog.file_selected.connect(_source_selected)
	destination_dialog = EditorFileDialog.new()
	destination_dialog.title = "导出关卡素材包"; destination_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	destination_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	destination_dialog.filters = PackedStringArray(["*.pck ; Godot 资源包"])
	get_editor_interface().get_base_control().add_child(destination_dialog)
	destination_dialog.file_selected.connect(_export)
	message_dialog = AcceptDialog.new(); get_editor_interface().get_base_control().add_child(message_dialog)
	add_tool_menu_item("导出关卡素材包…", func(): source_dialog.popup_centered_ratio(0.7))

func _source_selected(path: String) -> void:
	manifest_path = path; destination_dialog.current_file = path.get_file().get_basename() + ".pck"
	destination_dialog.popup_centered_ratio(0.7)

func _export(path: String) -> void:
	var error := LevelAssetPackWriter.write(manifest_path, path)
	message_dialog.dialog_text = error if not error.is_empty() else "已导出 PCK 和 .assetpack.json。\n把两个文件一起交给策划，在关卡编辑器中导入 .assetpack.json。"
	message_dialog.popup_centered(Vector2i(580, 180))

func _exit_tree() -> void:
	remove_tool_menu_item("导出关卡素材包…")
	source_dialog.queue_free(); destination_dialog.queue_free(); message_dialog.queue_free()
