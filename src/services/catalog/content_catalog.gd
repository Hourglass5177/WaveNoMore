extends Node

## 内容目录服务。把关卡、随从资源建立成稳定 ID 索引，供选关和结算流程查询。

## 内容目录加载并建立 ID 索引后发出。
signal catalog_ready
## 默认或指定目录无法加载时发出。
signal catalog_failed(message: String)

## 应用启动时默认加载的内容目录资源。
const DEFAULT_CATALOG_PATH := "res://content/catalogs/mvp_catalog.tres"
## 开发期自动发现关卡包的根目录；正式发布仍应显式登记到 Catalog。
const STAGES_ROOT := "res://content/stages"

## 当前已加载的目录资源，保存显式登记的关卡、随从和默认规则。
var data: ContentCatalogData
## 以稳定 `stage_id` 为键的关卡索引，避免界面依赖资源文件名或数组顺序。
var _stages_by_id: Dictionary = {}
## 以稳定 `pet_id` 为键的随从索引。
var _pets_by_id: Dictionary = {}


func _ready() -> void:
	load_catalog(DEFAULT_CATALOG_PATH)


func load_catalog(path: String) -> bool:
	# 不把脚本类名传给 ResourceLoader：导出后的 .tres 会重映射为二进制资源，
	# 加载器登记的是 Resource，而不是附着脚本的全局类名。
	var loaded := ResourceLoader.load(path, "Resource")
	if loaded == null or not loaded is ContentCatalogData:
		catalog_failed.emit("无法加载内容目录：%s" % path)
		return false
	data = loaded as ContentCatalogData
	_rebuild_indices()
	_discover_stage_packages()
	catalog_ready.emit()
	return true


func _rebuild_indices() -> void:
	_stages_by_id.clear()
	_pets_by_id.clear()
	if data == null:
		return
	for stage: StageDefinition in data.stages:
		if stage != null and not stage.stage_id.is_empty():
			_stages_by_id[stage.stage_id] = stage
	for pet: PetDefinition in data.pets:
		if pet != null and not pet.pet_id.is_empty():
			_pets_by_id[pet.pet_id] = pet


func _discover_stage_packages() -> void:
	# 启动时尝试扫描 stages 目录，把尚未登记的新关卡补进来，主要方便开发。
	# 正式导出仍应在 Catalog 中显式登记，确保相关资源会被打进发布包。
	# 直接打开 res:// 虚拟目录；资源进入 PCK 后，转换出的系统绝对路径不再适用。
	var directory := DirAccess.open(STAGES_ROOT)
	if directory == null:
		return
	var folders := directory.get_directories()
	folders.sort()
	for folder: String in folders:
		var path := STAGES_ROOT.path_join(folder).path_join("stage_definition.tres")
		if not ResourceLoader.exists(path):
			continue
		var stage := ResourceLoader.load(path, "Resource") as StageDefinition
		if stage == null or stage.stage_id.is_empty():
			push_error("Invalid stage package: %s" % path)
			continue
		if _stages_by_id.has(stage.stage_id):
			var registered := _stages_by_id[stage.stage_id] as StageDefinition
			if registered != null and registered.resource_path != stage.resource_path:
				push_error("Duplicate stage ID '%s': %s / %s" % [stage.stage_id, registered.resource_path, stage.resource_path])
			continue
		_stages_by_id[stage.stage_id] = stage


func get_stage(stage_id: String) -> StageDefinition:
	return _stages_by_id.get(stage_id) as StageDefinition


func get_stage_path(stage_id: String) -> String:
	var stage := get_stage(stage_id)
	return stage.resource_path if stage != null else ""


func get_pet(pet_id: String) -> PetDefinition:
	return _pets_by_id.get(pet_id) as PetDefinition


func all_stages() -> Array[StageDefinition]:
	var result: Array[StageDefinition] = []
	for value: Variant in _stages_by_id.values():
		if value is StageDefinition:
			result.append(value as StageDefinition)
	result.sort_custom(func(a: StageDefinition, b: StageDefinition) -> bool:
		if a.order_index == b.order_index:
			return a.stage_id < b.stage_id
		return a.order_index < b.order_index
	)
	return result


func default_rule_set() -> GameplayRuleSet:
	return data.default_rule_set if data != null else null
