class_name ChartSceneLibrary
extends RefCounted
## 内置场景的只读来源与按需表现缓存。调用方只修改装配出的运行副本。
const LEGACY_THEMES := {
	"default": "res://content/stages/s02/stage_visual_theme.tres",
	"s01_free_carrier_theme": "res://content/stages/s01/stage_visual_theme.tres",
	"s02_tap_lab_theme": "res://content/stages/s02/stage_visual_theme.tres",
	"s03_hold_lab_theme": "res://content/stages/s03/stage_visual_theme.tres",
	"s04_rotary_tuning_theme": "res://content/stages/s04/stage_visual_theme.tres",
	"s05_combined_lab_theme": "res://content/stages/s05/stage_visual_theme.tres",
}
static var _shared: ChartSceneLibrary
var _stages := {}
var _presentations := {}
var _cache_mode := ResourceLoader.CACHE_MODE_REUSE
var _catalog_path: String
var _stages_root: String
var error := ""

func _init(catalog_path := StageCatalogIndex.DEFAULT_CATALOG_PATH, stages_root := StageCatalogIndex.STAGES_ROOT) -> void:
	_catalog_path = catalog_path
	_stages_root = stages_root
	_read_catalog()

static func shared() -> ChartSceneLibrary:
	# 共享库仅在主线程使用；后台任务接收复制出的 ID 或检查结果。
	if _shared == null: _shared = ChartSceneLibrary.new()
	return _shared

func _read_catalog() -> void:
	var mode := ResourceLoader.CACHE_MODE_IGNORE if _cache_mode != ResourceLoader.CACHE_MODE_REUSE else _cache_mode
	var catalog := ResourceLoader.load(_catalog_path, "Resource", mode) as ContentCatalogData
	error = "无法读取场景目录：" + _catalog_path if catalog == null else ""
	_stages = StageCatalogIndex.read(catalog, _stages_root, mode)

func refresh() -> void:
	# 深层绕过缓存，保证保存后的嵌套场景、材质和纹理也重读；不替换其他会话持有的资源。
	_cache_mode = ResourceLoader.CACHE_MODE_IGNORE_DEEP
	_presentations.clear()
	_read_catalog()

func all_stages() -> Array[StageDefinition]:
	return StageCatalogIndex.sorted_stages(_stages)

func scene_ids() -> PackedStringArray:
	return PackedStringArray(_stages.keys())

func contains_source(stage: StageDefinition) -> bool:
	return _stages.has(stage.stage_id) and _stages[stage.stage_id].resource_path == stage.resource_path

static func selection(presentation: Dictionary) -> Dictionary:
	# 配色不参与场景重建；旧主题与新场景保持不同身份，避免打开旧谱时隐式升级。
	if presentation.has("scene_id"):
		return {"scene_id": presentation.scene_id, "use_scene_show": presentation.get("use_scene_show", false)}
	return {"theme_id": presentation.get("theme_id", "default")}

func resolve(presentation: Dictionary) -> Dictionary:
	var identity := selection(presentation)
	var key := JSON.stringify(identity)
	if not _presentations.has(key): _presentations[key] = _load_presentation(identity)
	return _presentations[key]

func theme_copy(presentation: Dictionary) -> StageVisualTheme:
	var resolved := resolve(presentation)
	if resolved.theme == null: return null
	var theme := resolved.theme.duplicate(true) as StageVisualTheme
	for key in ["life", "death", "su", "ink", "paper"]:
		if presentation.get("palette_overrides", {}).has(key):
			theme.set(key + "_color", Color(str(presentation.palette_overrides[key])))
	return theme

func _load_presentation(identity: Dictionary) -> Dictionary:
	var result := {"theme": null, "background": null, "show": null, "errors": []}
	if not identity.has("scene_id"):
		var theme_id := str(identity.theme_id)
		if not LEGACY_THEMES.has(theme_id):
			result.errors.append({"message": "未知主题：" + theme_id})
		else:
			var dependency_error := _dependency_error(LEGACY_THEMES[theme_id], {})
			if not dependency_error.is_empty():
				result.errors.append({"message": dependency_error})
				return result
			result.theme = ResourceLoader.load(LEGACY_THEMES[theme_id], "Resource", _cache_mode) as StageVisualTheme
			if result.theme == null: result.errors.append({"message": "无法读取主题：" + theme_id})
		return result
	var id := str(identity.scene_id)
	if not error.is_empty():
		result.errors.append({"message": error})
		return result
	if not _stages.has(id):
		result.errors.append({"message": "找不到场景：" + id})
		return result
	var source: StageDefinition = _stages[id]
	# 刷新后的第一次选择也重读直接嵌在入口里的资源；字符串式懒加载路径在下面单独解析。
	if _cache_mode != ResourceLoader.CACHE_MODE_REUSE and not source.resource_path.is_empty():
		source = ResourceLoader.load(source.resource_path, "Resource", _cache_mode) as StageDefinition
	if source == null:
		result.errors.append({"message": "无法读取场景：" + id})
		return result
	var checked := {}
	for slot: String in ["visual_theme", "background", "stage_show"]:
		if slot == "stage_show" and not identity.use_scene_show: continue
		var resource: Resource = source.get(slot)
		var path := str(source.get(slot + "_resource_path"))
		var dependency_path := resource.resource_path.get_slice("::", 0) if resource != null else path
		var dependency_error := _dependency_error(dependency_path, checked) if not dependency_path.is_empty() else ""
		if not dependency_error.is_empty():
			result.errors.append({"message": "场景 %s：%s" % [id, dependency_error]})
			continue
		if resource == null and not path.is_empty() and ResourceLoader.exists(path):
			resource = ResourceLoader.load(path, "Resource", _cache_mode)
		var valid := resource is StageVisualTheme if slot == "visual_theme" else (resource is StageBackgroundDefinition if slot == "background" else resource is StageShow)
		if resource == null and path.is_empty() and slot != "visual_theme": continue
		if not valid:
			result.errors.append({"message": "场景 %s 的%s无法读取：%s" % [id, {"visual_theme": "美术主题", "background": "背景", "stage_show": "演出"}[slot], path]})
		else:
			result[{"visual_theme": "theme", "background": "background", "stage_show": "show"}[slot]] = resource
	return result

func _dependency_error(path: String, checked: Dictionary) -> String:
	# Godot 可返回缺图的部分场景，因此先检查资源声明的引用。结果随场景缓存，普通编辑不扫文件。
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(uid): path = ResourceUID.get_id_path(uid)
	if checked.has(path): return ""
	checked[path] = true
	# 工程中还要确认源文件存在；已缓存但被删除的资源也会使 ResourceLoader.exists 返回 true。
	# 发布包则由 ResourceLoader 处理 .tres/.tscn 的二进制重映射。
	if not ResourceLoader.exists(path) or (OS.has_feature("editor") and not FileAccess.file_exists(path)):
		return "缺少场景资源：" + path
	if path.get_extension() in ["tres", "tscn", "res", "scn", "gdshader"]:
		for dependency: String in ResourceLoader.get_dependencies(path):
			var message := _dependency_error(dependency.split("::")[-1], checked)
			if not message.is_empty(): return message
	return ""
