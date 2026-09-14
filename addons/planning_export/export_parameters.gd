@tool
extends EditorExportPlugin
## GUI 导出和命令行构建共用此入口，不依赖提前手工生成文件。
func _get_name() -> String: return "MinghePlanningSnapshot"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var snapshot := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	if not FileAccess.file_exists(PlanningParameters.WORKBOOK_PATH): snapshot.errors.append("缺少构建参数表")
	if not snapshot.errors.is_empty():
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,"构建参数","；".join(snapshot.errors))
		return
	add_file(PlanningParameters.BUNDLED_PATH, JSON.stringify({"values":snapshot.values}).to_utf8_buffer(),false)
	print("已封装构建参数：",snapshot.values.size()," 项")
