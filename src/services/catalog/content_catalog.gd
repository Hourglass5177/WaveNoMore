extends Node

## 内容目录服务。把关卡、随从资源建立成稳定 ID 索引，供选关和结算流程查询。

## 内容目录加载并建立 ID 索引后发出。
signal catalog_ready
## 默认或指定目录无法加载时发出。
signal catalog_failed(message: String)

## 应用启动时默认加载的内容目录资源。
const DEFAULT_CATALOG_PATH := StageCatalogIndex.DEFAULT_CATALOG_PATH
## 开发期自动发现关卡包的根目录；正式发布仍应显式登记到 Catalog。
const STAGES_ROOT := StageCatalogIndex.STAGES_ROOT

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
	catalog_ready.emit()
	return true


func _rebuild_indices() -> void:
	_stages_by_id = StageCatalogIndex.read(data)
	_pets_by_id.clear()
	if data == null:
		return
	for pet: PetDefinition in data.pets:
		if pet != null and not pet.pet_id.is_empty():
			_pets_by_id[pet.pet_id] = pet


func get_stage(stage_id: String) -> StageDefinition:
	return _stages_by_id.get(stage_id) as StageDefinition


func get_stage_path(stage_id: String) -> String:
	var stage := get_stage(stage_id)
	return stage.resource_path if stage != null else ""


func get_pet(pet_id: String) -> PetDefinition:
	return _pets_by_id.get(pet_id) as PetDefinition


func all_stages() -> Array[StageDefinition]:
	return StageCatalogIndex.sorted_stages(_stages_by_id)


func default_rule_set() -> GameplayRuleSet:
	return data.default_rule_set if data != null else null
