extends SceneTree

## 存档服务的集成测试。
## 使用独立的 `user://tests` 路径，避免覆盖开发者自己的游戏进度。

## 被测脚本直接实例化而不使用 Autoload，便于注入隔离的测试路径。
var SaveServiceScript: GDScript

## 已执行断言数，用于确认正常、损坏和版本过新等分支都跑到。
var _checks := 0
## 累计失败消息；测试结束时统一决定进程退出码。
var _failures: PackedStringArray = []
## 本测试专用的 `user://` 目录；不与玩家或开发者的实际存档混用。
var _test_dir := "user://tests/save_service"
## 模拟正式玩家存档的目标路径。
var _save_path := _test_dir.path_join("player.json")
## 模拟写入事务中尚未替换正式文件的临时路径。
var _temp_path := _test_dir.path_join("player.tmp")
## 模拟恢复流程读取的上一版存档路径。
var _backup_path := _test_dir.path_join("player.backup.json")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 等待 Catalog 单例就绪，再编译依赖它的存档服务。
	SaveServiceScript = load("res://src/services/save/save_service.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_test_dir))
	_cleanup_files()
	# 不使用 Autoload 实例，这样可以给服务注入测试专用路径。
	var service = SaveServiceScript.new()
	service.configure_storage_paths(_save_path, _temp_path, _backup_path)
	root.add_child(service)
	_expect(FileAccess.file_exists(_save_path), "first launch creates a validated save")

	var authored_stage := load("res://content/stages/s01/stage_definition.tres") as StageDefinition
	_expect(authored_stage != null and authored_stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "save fixture stage resolves")
	# 五张玩法测试关都明确不发随从；存档测试在内存中装配奖励，不能反过来污染测试关内容。
	var stage := authored_stage.duplicate(true) as StageDefinition
	stage.reward = authored_stage.reward.duplicate(true) as RewardDefinition
	stage.reward.pet = load("res://content/pets/pet_nu_tu_fu.tres") as PetDefinition
	stage.reward.fc_grants_base_pet = true
	stage.reward.ap_grants_advanced_pet = true
	service.record_stage_result(stage, {
		"cleared": true,
		"full_combo": true,
		"all_perfect": false,
		"score": 10000,
	})
	var base_state: Dictionary = service.pet_state(stage.reward.pet.pet_id)
	_expect(bool(base_state.get("owned", false)), "FC grants the base pet")
	_expect(not bool(base_state.get("advanced", false)), "FC alone does not advance the pet")

	service.record_stage_result(stage, {
		"cleared": true,
		"full_combo": true,
		"all_perfect": true,
		"score": 12000,
	})
	var advanced_state: Dictionary = service.pet_state(stage.reward.pet.pet_id)
	_expect(bool(advanced_state.get("advanced", false)), "AP advances the pet")
	_expect(FileAccess.file_exists(_backup_path), "subsequent saves retain a backup")
	_expect(service.equip_pet(stage.reward.pet.pet_id), "owned pet can occupy the single equipment slot")
	_expect_equal(service.equipped_pet_id(), stage.reward.pet.pet_id, "equipped pet ID persists in service data")
	service.free()

	# 故障注入一：主动写坏主存档，确认服务能从上一次备份恢复。
	var broken := FileAccess.open(_save_path, FileAccess.WRITE)
	broken.store_string("{not valid json")
	broken.close()
	var recovered = SaveServiceScript.new()
	recovered.configure_storage_paths(_save_path, _temp_path, _backup_path)
	root.add_child(recovered)
	_expect_equal(int(recovered.data.get("schema_version", 0)), 1, "corrupt main save recovers a valid backup")
	_expect(bool(recovered.pet_state(stage.reward.pet.pet_id).get("advanced", false)), "backup recovery keeps AP pet progression")
	recovered.free()

	# 故障注入二：伪造未来 schema，确认旧版本只读保护不会覆盖未知数据。
	var future_file := FileAccess.open(_save_path, FileAccess.WRITE)
	future_file.store_string(JSON.stringify({"schema_version": 99, "future_field": "keep_me"}))
	future_file.close()
	var future_service = SaveServiceScript.new()
	future_service.configure_storage_paths(_save_path, _temp_path, _backup_path)
	root.add_child(future_service)
	_expect(future_service.writes_blocked_by_future_version, "future save version enters read-only protection")
	_expect(not future_service.save_now(), "future save cannot be overwritten by older build")
	var future_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	_expect(future_data is Dictionary and int(future_data.get("schema_version", 0)) == 99, "future save bytes remain intact")
	future_service.free()
	_cleanup_files()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_dir))
	_finish()


func _cleanup_files() -> void:
	for path: String in [_save_path, _temp_path, _backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("SAVE TESTS: %d checks passed." % _checks)
		quit(0)
		return
	printerr("SAVE TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - " + failure)
	quit(1)
