extends Node

## 玩家存档服务。用“临时文件→回读校验→备份轮换”的方式提交，降低写坏正式存档的风险。

## 存档加载、迁移或创建完成后发出；参数是当前数据的深拷贝。
signal save_loaded(data: Dictionary)
## 一次存档通过临时文件校验并成功提交后发出。
signal save_written
## 加载保护或写入任一步骤失败时发出。
signal save_failed(message: String)

## 当前程序能够读写的存档结构版本。修改字段含义时应递增并补迁移逻辑。
const CURRENT_SCHEMA_VERSION := 1
## 正式玩家存档路径，`user://` 会映射到系统为本游戏分配的用户数据目录。
const SAVE_PATH := "user://player_save.json"
## 原子保存时先写入并回读校验的临时文件路径。
const TEMP_PATH := "user://player_save.tmp"
## 新存档提交前保留的上一版存档路径，用于正式文件损坏时恢复。
const BACKUP_PATH := "user://player_save.backup.json"

## 当前内存中的规范化玩家数据；修改后需调用 `save_now()` 才会落盘。
var data: Dictionary = {}
## 开发测试形态不写入存档，不降低已经获得的进阶状态。
var debug_pet_tiers: Dictionary = {}
## 实际使用的正式存档路径，可由隔离测试在 `_ready()` 前替换。
var _save_path: String = SAVE_PATH
## 实际使用的临时存档路径。
var _temp_path: String = TEMP_PATH
## 实际使用的备份存档路径。
var _backup_path: String = BACKUP_PATH
## 是否检测到高于当前程序支持版本的存档；为 true 时禁止写入，避免覆盖未来数据。
var writes_blocked_by_future_version: bool = false


func _ready() -> void:
	if StudioLaunch.is_active() or ChartTrialLaunch.arguments().has("path"): return
	load_or_create()


func configure_storage_paths(save_path: String, temp_path: String, backup_path: String) -> void:
	# 供隔离测试或便携存档使用。必须在加入 SceneTree 前调用，避免 _ready() 先访问默认路径。
	_save_path = save_path
	_temp_path = temp_path
	_backup_path = backup_path


func default_data() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"unlocked_stages": [],
		"stage_results": {},
		"pets": {},
		"equipped_pet_id": "",
		"tutorial_flags": {},
	}


func load_or_create() -> void:
	writes_blocked_by_future_version = false
	var loaded := _read_valid_dictionary(_save_path)
	if loaded.has("__future_version"):
		writes_blocked_by_future_version = true
		data = default_data()
		save_failed.emit("存档版本 %d 高于当前支持版本 %d；本次运行不会覆盖它。" % [int(loaded["__future_version"]), CURRENT_SCHEMA_VERSION])
		save_loaded.emit(data.duplicate(true))
		return
	if loaded.is_empty() and FileAccess.file_exists(_backup_path):
		loaded = _read_valid_dictionary(_backup_path)
	if loaded.is_empty():
		data = default_data()
		save_now()
	else:
		data = _migrate_and_normalize(loaded)
	save_loaded.emit(data.duplicate(true))


func save_now() -> bool:
	if writes_blocked_by_future_version:
		save_failed.emit("检测到未来版本存档，已阻止写入。")
		return false
	data = _migrate_and_normalize(data)
	var file := FileAccess.open(_temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("无法写入临时存档：%s" % FileAccess.get_open_error())
	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()
	# 临时文件能重新解析后才轮换正式存档，以降低写入中断或数据异常时损坏旧存档的风险。
	var verification := _read_valid_dictionary(_temp_path)
	if verification.is_empty():
		return _fail("临时存档回读校验失败。")
	var save_abs := ProjectSettings.globalize_path(_save_path)
	var temp_abs := ProjectSettings.globalize_path(_temp_path)
	var backup_abs := ProjectSettings.globalize_path(_backup_path)
	if FileAccess.file_exists(_backup_path):
		var remove_error := DirAccess.remove_absolute(backup_abs)
		if remove_error != OK:
			return _fail("无法轮换旧备份：%s" % error_string(remove_error))
	if FileAccess.file_exists(_save_path):
		var backup_error := DirAccess.rename_absolute(save_abs, backup_abs)
		if backup_error != OK:
			return _fail("无法建立存档备份：%s" % error_string(backup_error))
	var commit_error := DirAccess.rename_absolute(temp_abs, save_abs)
	if commit_error != OK:
		if FileAccess.file_exists(_backup_path) and not FileAccess.file_exists(_save_path):
			DirAccess.rename_absolute(backup_abs, save_abs)
		return _fail("无法提交新存档：%s" % error_string(commit_error))
	save_written.emit()
	return true


func _read_valid_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {}
	var dictionary := parsed as Dictionary
	var version := int(dictionary.get("schema_version", 0))
	if version <= 0:
		return {}
	if version > CURRENT_SCHEMA_VERSION:
		return {"__future_version": version}
	return dictionary


func _migrate_and_normalize(source: Dictionary) -> Dictionary:
	var normalized := default_data()
	for key: String in normalized.keys():
		if source.has(key):
			normalized[key] = source[key]
	normalized["schema_version"] = CURRENT_SCHEMA_VERSION
	return normalized


func is_stage_unlocked(stage: StageDefinition) -> bool:
	if stage == null:
		return false
	if stage.unlocked_by_default:
		return true
	return stage.stage_id in data.get("unlocked_stages", [])


func unlock_stage(stage_id: String) -> void:
	if stage_id.is_empty():
		return
	var unlocked: Array = data.get("unlocked_stages", [])
	if stage_id not in unlocked:
		unlocked.append(stage_id)
		data["unlocked_stages"] = unlocked


func stage_result(stage_id: String) -> Dictionary:
	var results: Dictionary = data.get("stage_results", {})
	return (results.get(stage_id, {}) as Dictionary).duplicate(true)


func record_stage_result(stage: StageDefinition, result: Dictionary) -> Dictionary:
	if stage == null:
		return {}
	var stage_results: Dictionary = data.get("stage_results", {})
	var previous: Dictionary = stage_results.get(stage.stage_id, {})
	var score := int(result.get("score", 0))
	var best_score := maxi(score, int(previous.get("best_score", 0)))
	var merged := {
		"best_score": best_score,
		"cleared": bool(previous.get("cleared", false)) or bool(result.get("cleared", false)),
		"full_combo": bool(previous.get("full_combo", false)) or bool(result.get("full_combo", false)),
		"all_perfect": bool(previous.get("all_perfect", false)) or bool(result.get("all_perfect", false)),
		"play_count": int(previous.get("play_count", 0)) + 1,
		"last_result": result.duplicate(true),
	}
	stage_results[stage.stage_id] = merged
	data["stage_results"] = stage_results
	if bool(result.get("cleared", false)) and stage.reward != null:
		unlock_stage(stage.reward.next_stage_id)
		_apply_pet_reward(stage.reward, result)
	save_now()
	return merged


func _apply_pet_reward(reward: RewardDefinition, result: Dictionary) -> void:
	if reward.pet == null:
		return
	var pets: Dictionary = data.get("pets", {})
	var state: Dictionary = pets.get(reward.pet.pet_id, {"owned": false, "advanced": false})
	if reward.fc_grants_base_pet and bool(result.get("full_combo", false)):
		state["owned"] = true
	if reward.ap_grants_advanced_pet and bool(result.get("all_perfect", false)):
		state["owned"] = true
		state["advanced"] = true
	pets[reward.pet.pet_id] = state
	data["pets"] = pets


func equip_pet(pet_id: String) -> bool:
	if pet_id.is_empty():
		data["equipped_pet_id"] = ""
		return save_now()
	var state: Dictionary = (data.get("pets", {}) as Dictionary).get(pet_id, {})
	if ContentCatalog.get_pet(pet_id) == null or not bool(state.get("owned", false)):
		return false
	data["equipped_pet_id"] = pet_id
	return save_now()


func equipped_pet_id() -> String:
	var id := str(data.get("equipped_pet_id", ""))
	return id if ContentCatalog.get_pet(id) != null else ""


func pet_state(pet_id: String) -> Dictionary:
	return ((data.get("pets", {}) as Dictionary).get(pet_id, {}) as Dictionary).duplicate(true)


func set_tutorial_seen(flag: StringName) -> void:
	var flags: Dictionary = data.get("tutorial_flags", {})
	flags[String(flag)] = true
	data["tutorial_flags"] = flags


func _fail(message: String) -> bool:
	push_error(message)
	save_failed.emit(message)
	return false


func equipped_pet_advanced() -> bool:
	var id := equipped_pet_id()
	if OS.is_debug_build() and debug_pet_tiers.has(id): return bool(debug_pet_tiers[id])
	return bool(pet_state(id).get("advanced", false))

func debug_grant_pet(id: String, advanced: bool) -> bool:
	if not OS.is_debug_build() or ContentCatalog.get_pet(id) == null: return false
	var state := pet_state(id)
	state.owned = true
	state.advanced = advanced or bool(state.get("advanced", false))
	data.pets[id] = state
	debug_pet_tiers[id] = advanced
	return equip_pet(id)
