class_name StageCatalogIndex
extends RefCounted
## 游戏目录与写谱器共用的关卡发现规则；只读取资源，不依赖 Autoload 或场景树。
const DEFAULT_CATALOG_PATH := "res://content/catalogs/mvp_catalog.tres"
const STAGES_ROOT := "res://content/stages"

static func read(catalog: ContentCatalogData, stages_root := STAGES_ROOT, cache_mode := ResourceLoader.CACHE_MODE_REUSE) -> Dictionary:
	var stages := {}
	if catalog == null: return stages
	for source: StageDefinition in catalog.stages:
		var stage := source
		# 刷新目录时重读入口，避免 Catalog 中已经缓存的外部资源遮住新名称或新路径。
		if stage != null and not stage.resource_path.is_empty() and cache_mode != ResourceLoader.CACHE_MODE_REUSE:
			stage = ResourceLoader.load(stage.resource_path, "Resource", cache_mode) as StageDefinition
		if stage != null and not stage.stage_id.is_empty(): stages[stage.stage_id] = stage
	var directory := DirAccess.open(stages_root)
	if directory == null: return stages
	var folders := directory.get_directories()
	folders.sort()
	for folder: String in folders:
		var path := stages_root.path_join(folder).path_join("stage_definition.tres")
		if not ResourceLoader.exists(path): continue
		var stage := ResourceLoader.load(path, "Resource", cache_mode) as StageDefinition
		if stage == null or stage.stage_id.is_empty():
			push_error("无法读取关卡入口：%s" % path)
			continue
		if stages.has(stage.stage_id):
			if stages[stage.stage_id].resource_path != stage.resource_path:
				push_error("关卡 ID 重复：%s（%s / %s）" % [stage.stage_id, stages[stage.stage_id].resource_path, path])
			continue
		stages[stage.stage_id] = stage
	return stages

static func sorted_stages(stages: Dictionary) -> Array[StageDefinition]:
	var result: Array[StageDefinition] = []
	result.assign(stages.values())
	result.sort_custom(func(a: StageDefinition, b: StageDefinition) -> bool:
		return a.stage_id < b.stage_id if a.order_index == b.order_index else a.order_index < b.order_index)
	return result
