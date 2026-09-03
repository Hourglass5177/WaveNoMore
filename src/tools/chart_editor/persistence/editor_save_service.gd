## 写谱器持久化服务。正式 Chart/Show 采用事务日志（Journal）保存，自动恢复稿和历史备份写入 user://。
@tool
class_name MingheChartEditorSaveService
extends RefCounted

## 保存事务日志的默认路径；全工程同一时刻只允许一笔未完成事务。
const JOURNAL_PATH := "user://minghe_chart_editor/save_journal.json"
## 覆盖正式谱面前保存旧版本的默认根目录。
const BACKUP_ROOT := "user://minghe_chart_editor/backups"
## 自动恢复稿的默认根目录，按 chart_id 分子目录。
const RECOVERY_ROOT := "user://minghe_chart_editor/recovery"
## 新关卡不复制公共判定规则，只让 StageDefinition 指向这份共享 Resource。
const DEFAULT_RULE_SET_PATH := "res://content/rules/default_gameplay_rules.tres"

## 当前实例实际使用的 Journal 路径；测试会替换为隔离目录以注入故障。
var journal_path: String = JOURNAL_PATH
## 当前实例实际使用的历史备份根目录。
var backup_root: String = BACKUP_ROOT
## 当前实例实际使用的未保存恢复稿根目录。
var recovery_root: String = RECOVERY_ROOT


func save_document(
	document: MingheChartEditorDocument,
	target_chart_path: String = "",
	target_show_path: String = ""
) -> Dictionary:
	# 两份正式资源必须成对提交；先写临时文件并重载验签，确认可读后才移动旧文件。
	var chart_target := target_chart_path if not target_chart_path.is_empty() else document.chart_path
	var show_target := target_show_path if not target_show_path.is_empty() else document.show_path
	if document.chart == null or document.stage_show == null:
		return _failure("没有可保存的 SongChart / StageShow")
	if chart_target.is_empty() or show_target.is_empty():
		return _failure("必须先指定 SongChart 与 StageShow 的保存路径")
	if not chart_target.ends_with(".tres") or not show_target.ends_with(".tres"):
		return _failure("正式谱面必须保存为 .tres")

	var token := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var chart_temp := chart_target.trim_suffix(".tres") + ".minghe_tmp_%s.tres" % token
	var show_temp := show_target.trim_suffix(".tres") + ".minghe_tmp_%s.tres" % token
	var chart_old := chart_target.trim_suffix(".tres") + ".minghe_old_%s.tres" % token
	var show_old := show_target.trim_suffix(".tres") + ".minghe_old_%s.tres" % token
	var directory_error := _ensure_parent_directory(chart_target)
	if directory_error == OK:
		directory_error = _ensure_parent_directory(show_target)
	if directory_error != OK:
		return _failure("无法创建保存目录：%s" % error_string(directory_error))

	var chart_error := ResourceSaver.save(document.chart.duplicate(true), chart_temp)
	if chart_error != OK:
		return _failure("SongChart 临时写入失败：%s" % error_string(chart_error))
	var show_error := ResourceSaver.save(document.stage_show.duplicate(true), show_temp)
	if show_error != OK:
		_safe_remove(chart_temp)
		return _failure("StageShow 临时写入失败：%s" % error_string(show_error))
	var reloaded_chart := ResourceLoader.load(chart_temp, "", ResourceLoader.CACHE_MODE_IGNORE)
	var reloaded_show := ResourceLoader.load(show_temp, "", ResourceLoader.CACHE_MODE_IGNORE)
	if reloaded_chart == null or reloaded_show == null:
		_cleanup_temps(chart_temp, show_temp)
		return _failure("临时文件重载校验失败，正式文件未改动")
	var verification_document := MingheChartEditorDocument.new()
	verification_document.chart = reloaded_chart
	verification_document.stage_show = reloaded_show
	if verification_document.content_signature() != document.content_signature():
		_cleanup_temps(chart_temp, show_temp)
		return _failure("临时文件内容哈希不一致，正式文件未改动")

	var chart_had_original := FileAccess.file_exists(chart_target)
	var show_had_original := FileAccess.file_exists(show_target)
	var backup := _create_backup(document, chart_target, show_target)
	if not bool(backup.get("ok", false)):
		_cleanup_temps(chart_temp, show_temp)
		return _failure(String(backup.get("message", "备份失败")))
	# phase 是崩溃恢复状态：准备、暂存旧文件、逐份替换，最后才标记提交完成。
	var journal := {
		"schema_version": 2,
		"chart_target": chart_target,
		"show_target": show_target,
		"chart_temp": chart_temp,
		"show_temp": show_temp,
		"chart_old": chart_old,
		"show_old": show_old,
		"had_original": {"chart": chart_had_original, "show": show_had_original},
		"backup_directory": backup.get("directory", ""),
		"phase": "prepared",
	}
	var journal_error := _write_journal(journal)
	if journal_error != OK:
		_cleanup_temps(chart_temp, show_temp)
		return _failure("保存 Journal 写入失败：%s；正式文件未改动" % error_string(journal_error))

	if chart_had_original and _rename(chart_target, chart_old) != OK:
		_cleanup_temps(chart_temp, show_temp)
		var clear_error := _clear_journal()
		if clear_error != OK:
			return _failure("无法暂存旧 SongChart，且 Journal 清理失败：%s" % error_string(clear_error))
		return _failure("无法暂存旧 SongChart；正式文件未改动")
	if show_had_original and _rename(show_target, show_old) != OK:
		if chart_had_original:
			_rename(chart_old, chart_target)
		_cleanup_temps(chart_temp, show_temp)
		var clear_error := _clear_journal()
		if clear_error != OK:
			return _failure("无法暂存旧 StageShow，且 Journal 清理失败：%s" % error_string(clear_error))
		return _failure("无法暂存旧 StageShow；正式文件未改动")

	journal.phase = "originals_staged"
	journal_error = _write_journal(journal)
	if journal_error != OK:
		return _abort_transaction(journal, "更新 Journal 失败，已回滚旧文件：%s" % error_string(journal_error))
	if _rename(chart_temp, chart_target) != OK:
		return _abort_transaction(journal, "替换 SongChart 失败，已恢复旧版本")
	journal.phase = "chart_replaced"
	journal_error = _write_journal(journal)
	if journal_error != OK:
		return _abort_transaction(journal, "SongChart 替换后 Journal 落盘失败，已回滚：%s" % error_string(journal_error))
	if _rename(show_temp, show_target) != OK:
		return _abort_transaction(journal, "替换 StageShow 失败，已回滚两份文件")
	journal.phase = "show_replaced"
	journal_error = _write_journal(journal)
	if journal_error != OK:
		return _abort_transaction(journal, "StageShow 替换后 Journal 落盘失败，已回滚：%s" % error_string(journal_error))

	# 先把 committed 状态可靠写入磁盘，再删除旧副本。即使清理阶段崩溃，恢复逻辑也会保留新文件。
	journal.phase = "committed"
	journal_error = _write_journal(journal)
	if journal_error != OK:
		return _abort_transaction(journal, "提交 Journal 落盘失败，已回滚：%s" % error_string(journal_error))
	var cleanup_error := _safe_remove(chart_old)
	if cleanup_error == OK:
		cleanup_error = _safe_remove(show_old)
	document.chart_path = chart_target
	document.show_path = show_target
	document.mark_saved()
	if cleanup_error != OK:
		return _failure("新谱已提交，但旧文件清理失败：%s" % error_string(cleanup_error), true)
	var clear_error := _clear_journal()
	if clear_error != OK:
		return _failure("新谱已提交，但 Journal 清理失败：%s" % error_string(clear_error), true)
	return {
		"ok": true,
		"message": "已原子保存 SongChart 与 StageShow",
		"chart_path": chart_target,
		"show_path": show_target,
		"backup_directory": backup.get("directory", ""),
	}


func save_new_stage_package(document: MingheChartEditorDocument, directory: String) -> Dictionary:
	# 新关卡使用六文件约定；共享 GameplayRuleSet 只记录路径，不在每关复制一份。
	if document.stage_definition == null or document.song_definition == null \
			or document.chart == null or document.stage_show == null \
			or document.visual_theme == null or document.reward_definition == null \
			or document.rule_set == null:
		return _failure("新关卡内存合同不完整，无法生成关卡包")
	var normalized := directory.trim_suffix("/")
	if not normalized.begins_with("res://") and not normalized.begins_with("user://"):
		return _failure("关卡包必须保存在工程 res:// 或 user:// 目录")
	var directory_error := _ensure_directory(normalized)
	if directory_error != OK:
		return _failure("无法创建关卡目录：%s" % error_string(directory_error))
	var paths := {
		"song": normalized + "/song_definition.tres",
		"chart": normalized + "/song_chart.tres",
		"show": normalized + "/stage_show.tres",
		"reward": normalized + "/reward_definition.tres",
		"theme": normalized + "/stage_visual_theme.tres",
		"stage": normalized + "/stage_definition.tres",
	}
	if FileAccess.file_exists(paths.stage):
		return _failure("目标已有 stage_definition.tres；请打开该关卡后再保存，避免覆盖")

	# 先提交依赖，最后写轻量 StageDefinition。中途崩溃不会让半成品关卡暴露给内容目录。
	for entry: Dictionary in [
		{"resource": document.song_definition, "path": paths.song, "label": "SongDefinition"},
		{"resource": document.chart, "path": paths.chart, "label": "SongChart"},
		{"resource": document.stage_show, "path": paths.show, "label": "StageShow"},
		{"resource": document.reward_definition, "path": paths.reward, "label": "RewardDefinition"},
		{"resource": document.visual_theme, "path": paths.theme, "label": "StageVisualTheme"},
	]:
		var save_error := _save_single_resource_atomic(entry.resource, String(entry.path))
		if save_error != OK:
			return _failure("%s 写入失败：%s；stage_definition.tres 未提交" % [entry.label, error_string(save_error)])

	var marker := document.stage_definition.duplicate(true) as StageDefinition
	marker.song = null
	marker.chart = null
	marker.stage_show = null
	marker.visual_theme = null
	marker.reward = null
	marker.rule_set = null
	marker.song_resource_path = paths.song
	marker.chart_resource_path = paths.chart
	marker.stage_show_resource_path = paths.show
	marker.visual_theme_resource_path = paths.theme
	marker.reward_resource_path = paths.reward
	var rules_path := String(document.rule_set.resource_path)
	marker.rule_set_resource_path = rules_path if not rules_path.is_empty() else DEFAULT_RULE_SET_PATH
	marker.song_title = String(document.song_definition.get("title"))
	marker.song_artist = String(document.song_definition.get("artist"))
	var marker_error := _save_single_resource_atomic(marker, paths.stage)
	if marker_error != OK:
		return _failure("StageDefinition commit marker 写入失败：%s" % error_string(marker_error))

	document.stage_path = paths.stage
	document.chart_path = paths.chart
	document.show_path = paths.show
	var stage := document.stage_definition as StageDefinition
	stage.song_resource_path = paths.song
	stage.chart_resource_path = paths.chart
	stage.stage_show_resource_path = paths.show
	stage.visual_theme_resource_path = paths.theme
	stage.reward_resource_path = paths.reward
	stage.rule_set_resource_path = marker.rule_set_resource_path
	document.mark_saved()
	return {
		"ok": true,
		"message": "已生成完整六文件关卡包",
		"stage_path": paths.stage,
		"chart_path": paths.chart,
		"show_path": paths.show,
		"paths": paths,
	}


func autosave(document: MingheChartEditorDocument) -> Dictionary:
	# 自动保存只生成恢复对，不改变文档的正式目标路径和「已保存」签名。
	if document.chart == null or document.stage_show == null:
		return _failure("没有可恢复的文档")
	var chart_id := String(document.chart.get("chart_id"))
	if chart_id.is_empty():
		chart_id = "untitled"
	var directory := "%s/%s" % [recovery_root, _safe_name(chart_id)]
	var directory_error := _ensure_directory(directory)
	if directory_error != OK:
		return _failure("自动恢复目录创建失败：%s" % error_string(directory_error))
	var chart_recovery := directory + "/song_chart.tres"
	var show_recovery := directory + "/stage_show.tres"
	var chart_error := ResourceSaver.save(document.chart.duplicate(true), chart_recovery)
	var show_error := ResourceSaver.save(document.stage_show.duplicate(true), show_recovery)
	if chart_error != OK or show_error != OK:
		return _failure("自动恢复文件写入失败")
	var metadata := {
		"chart_id": chart_id,
		"chart_source": document.chart_path,
		"show_source": document.show_path,
		"base_signature": document.last_saved_signature,
		"recovery_signature": document.content_signature(),
		"timestamp": Time.get_unix_time_from_system(),
	}
	var metadata_error := _write_json(directory + "/metadata.json", metadata)
	if metadata_error != OK:
		return _failure("自动恢复 metadata 写入失败：%s" % error_string(metadata_error))
	return {"ok": true, "message": "已写入自动恢复", "directory": directory}


func load_recovery(chart_id: String) -> Dictionary:
	var directory := "%s/%s" % [recovery_root, _safe_name(chart_id if not chart_id.is_empty() else "untitled")]
	var chart_path := directory + "/song_chart.tres"
	var show_path := directory + "/stage_show.tres"
	if not ResourceLoader.exists(chart_path) or not ResourceLoader.exists(show_path):
		return _failure("没有找到恢复版本")
	var chart := ResourceLoader.load(chart_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var show := ResourceLoader.load(show_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if chart == null or show == null:
		return _failure("恢复版本已损坏")
	return {"ok": true, "chart": chart, "stage_show": show, "directory": directory}


func recover_interrupted_save() -> Dictionary:
	# committed 说明新文件已生效，只需清理；其他阶段都回滚到操作前的成对文件。
	if not FileAccess.file_exists(journal_path):
		return {"ok": true, "message": "没有未完成保存"}
	var journal_value: Variant = _read_json(journal_path)
	if not journal_value is Dictionary:
		return _failure("保存 Journal 已损坏，请检查备份目录")
	var journal: Dictionary = journal_value
	var phase := String(journal.get("phase", "prepared"))
	var recovery_error := OK
	if phase == "committed":
		recovery_error = _cleanup_committed(journal)
	else:
		recovery_error = _rollback_uncommitted(journal)
	if recovery_error != OK:
		return _failure("中断保存恢复失败：%s；Journal 已保留" % error_string(recovery_error))
	var clear_error := _clear_journal()
	if clear_error != OK:
		return _failure("已恢复文件，但 Journal 清理失败：%s" % error_string(clear_error))
	return {"ok": true, "message": "已从中断保存中恢复正式文件", "phase": phase}


func _create_backup(document: MingheChartEditorDocument, chart_target: String, show_target: String) -> Dictionary:
	var chart_id := String(document.chart.get("chart_id"))
	if chart_id.is_empty():
		chart_id = "untitled"
	var directory := "%s/%s/%d_%d" % [backup_root, _safe_name(chart_id), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var directory_error := _ensure_directory(directory)
	if directory_error != OK:
		return {"ok": false, "message": "备份目录创建失败：%s" % error_string(directory_error)}
	if FileAccess.file_exists(chart_target):
		var chart_copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(chart_target), ProjectSettings.globalize_path(directory + "/song_chart.tres"))
		if chart_copy_error != OK:
			return {"ok": false, "message": "SongChart 备份写入失败：%s" % error_string(chart_copy_error)}
	if FileAccess.file_exists(show_target):
		var show_copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(show_target), ProjectSettings.globalize_path(directory + "/stage_show.tres"))
		if show_copy_error != OK:
			return {"ok": false, "message": "StageShow 备份写入失败：%s" % error_string(show_copy_error)}
	return {"ok": true, "directory": directory}


func _save_single_resource_atomic(resource: Resource, target: String) -> Error:
	var parent_error := _ensure_parent_directory(target)
	if parent_error != OK:
		return parent_error
	var token := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temp := target.trim_suffix(".tres") + ".minghe_package_%s.tres" % token
	var old := target.trim_suffix(".tres") + ".minghe_package_old_%s.tres" % token
	var save_error := ResourceSaver.save(resource.duplicate(true), temp)
	if save_error != OK:
		return save_error
	if ResourceLoader.load(temp, "", ResourceLoader.CACHE_MODE_IGNORE) == null:
		_safe_remove(temp)
		return ERR_FILE_CORRUPT
	var had_original := FileAccess.file_exists(target)
	if had_original:
		var stage_error := _rename(target, old)
		if stage_error != OK:
			_safe_remove(temp)
			return stage_error
	var replace_error := _rename(temp, target)
	if replace_error != OK:
		if had_original:
			_rename(old, target)
		_safe_remove(temp)
		return replace_error
	_safe_remove(old)
	return OK


func _abort_transaction(journal: Dictionary, message: String) -> Dictionary:
	var rollback_error := _rollback_uncommitted(journal)
	if rollback_error != OK:
		return _failure("%s；回滚又失败：%s，Journal 已保留" % [message, error_string(rollback_error)])
	var clear_error := _clear_journal()
	if clear_error != OK:
		return _failure("%s；Journal 清理失败：%s" % [message, error_string(clear_error)])
	return _failure(message)


func _rollback_uncommitted(journal: Dictionary) -> Error:
	var had: Dictionary = journal.get("had_original", {}) as Dictionary
	var phase := String(journal.get("phase", "prepared"))
	var first_error := OK
	for side: String in ["chart", "show"]:
		var target := String(journal.get(side + "_target", ""))
		var old := String(journal.get(side + "_old", ""))
		var had_original := bool(had.get(side, FileAccess.file_exists(old)))
		if had_original:
			if FileAccess.file_exists(old):
				var remove_error := _safe_remove(target)
				if first_error == OK and remove_error != OK:
					first_error = remove_error
				var restore_error := _rename(old, target)
				if first_error == OK and restore_error != OK:
					first_error = restore_error
			elif phase != "prepared" and first_error == OK:
				first_error = ERR_FILE_NOT_FOUND
		else:
			var remove_new_error := _safe_remove(target)
			if first_error == OK and remove_new_error != OK:
				first_error = remove_new_error
	for temp_key: String in ["chart_temp", "show_temp"]:
		var temp_error := _safe_remove(String(journal.get(temp_key, "")))
		if first_error == OK and temp_error != OK:
			first_error = temp_error
	return first_error


func _cleanup_committed(journal: Dictionary) -> Error:
	var first_error := OK
	for key: String in ["chart_old", "show_old", "chart_temp", "show_temp"]:
		var cleanup_error := _safe_remove(String(journal.get(key, "")))
		if first_error == OK and cleanup_error != OK:
			first_error = cleanup_error
	return first_error


func _rename(from_path: String, to_path: String) -> Error:
	if from_path.is_empty() or to_path.is_empty():
		return ERR_INVALID_PARAMETER
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _safe_remove(path: String) -> Error:
	if path.is_empty() or not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_temps(chart_temp: String, show_temp: String) -> void:
	_safe_remove(chart_temp)
	_safe_remove(show_temp)


func _write_journal(value: Dictionary) -> Error:
	# Journal 记录成对替换进行到了哪一步，是崩溃恢复时选择“清理”还是“回滚”的依据。
	return _write_json(journal_path, value)


func _clear_journal() -> Error:
	return _safe_remove(journal_path)


func _write_json(path: String, value: Dictionary) -> Error:
	# 所有恢复用 JSON 都先写临时文件再替换目标，避免中断时只留下半截内容。
	var parent_error := _ensure_parent_directory(path)
	if parent_error != OK:
		return parent_error
	var token := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temp_path := path + ".writing_" + token
	var old_path := path + ".old_" + token
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  ", true))
	file.flush()
	if file.get_error() != OK:
		var write_error := file.get_error()
		file = null
		_safe_remove(temp_path)
		return write_error
	file = null
	var had_original := FileAccess.file_exists(path)
	if had_original:
		var stage_error := _rename(path, old_path)
		if stage_error != OK:
			_safe_remove(temp_path)
			return stage_error
	var replace_error := _rename(temp_path, path)
	if replace_error != OK:
		if had_original and FileAccess.file_exists(old_path):
			_rename(old_path, path)
		_safe_remove(temp_path)
		return replace_error
	return _safe_remove(old_path)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	if text.strip_edges().is_empty():
		return null
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _ensure_parent_directory(path: String) -> Error:
	var base := path.get_base_dir()
	if base.is_empty():
		return OK
	return _ensure_directory(base)


func _ensure_directory(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _safe_name(value: String) -> String:
	var result := ""
	for character in value:
		result += character if character.is_valid_filename() and character not in ["/", "\\"] else "_"
	return result


func _failure(message: String, committed: bool = false) -> Dictionary:
	return {"ok": false, "message": message, "committed": committed}
