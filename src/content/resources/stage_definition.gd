## 关卡组合根资源。目录中可只加载这份轻量入口，再通过路径按需解析歌曲、谱面、演出和美术。
@tool
class_name StageDefinition
extends Resource

@export_group("Identity")
## 关卡稳定 ID；存档、选关和奖励解锁都靠它引用。
@export var stage_id: String = ""
## 选关界面显示的关卡名称。
@export var display_name: String = ""
## 选关界面显示的多行关卡简介。
@export_multiline var description: String = ""
## 选关排序权重；数值越小越靠前，相同时再由调用方稳定排序。
@export var order_index: int = 0

@export_group("Selection Metadata")
## 轻量选关元数据中的歌曲标题，避免为列表预览加载完整 SongDefinition。
@export var song_title: String = ""
## 轻量选关元数据中的作者名。
@export var song_artist: String = ""
## 选关卡面纹理；只用于表现，不影响关卡内容。
@export var cover: Texture2D
## 新存档是否无需前置奖励即可进入此关。
@export var unlocked_by_default: bool = false

@export_group("Development")
## 仅供开发测试：伤害仍照常记录，魂火可以降到零以下，但关卡不会进入失败状态。
@export var debug_nonlethal: bool = false

@export_group("Composition")
## 已解析的歌曲数据；与下方路径二选一，运行前必须非空。
@export var song: SongDefinition
## 已解析的玩法谱面；与下方路径二选一。
@export var chart: SongChart
## 已解析的演出时间轴；与下方路径二选一。
@export var stage_show: StageShow
## 已解析的本关美术装配表；与下方路径二选一。
@export var visual_theme: StageVisualTheme
## 本关背景/前景视差素材；为空表示不添加视差对象。
@export var background: StageBackgroundDefinition
## 已解析的结算奖励；与下方路径二选一。
@export var reward: RewardDefinition
## 已解析的判定与物理规则；为空时可由目录默认规则补入。
@export var rule_set: GameplayRuleSet

@export_group("Lazy Composition Paths")
## SongDefinition 的 `.tres` 路径；仅在 song 尚未装入时使用。
@export_file("*.tres") var song_resource_path: String = ""
## SongChart 的 `.tres` 路径；仅在 chart 尚未装入时使用。
@export_file("*.tres") var chart_resource_path: String = ""
## StageShow 的 `.tres` 路径；仅在 stage_show 尚未装入时使用。
@export_file("*.tres") var stage_show_resource_path: String = ""
## StageVisualTheme 的 `.tres` 路径；仅在 visual_theme 尚未装入时使用。
@export_file("*.tres") var visual_theme_resource_path: String = ""
## StageBackgroundDefinition 的 `.tres` 路径；空路径与空资源表示无配置。
@export_file("*.tres") var background_resource_path: String = ""
## RewardDefinition 的 `.tres` 路径；仅在 reward 尚未装入时使用。
@export_file("*.tres") var reward_resource_path: String = ""
## GameplayRuleSet 的 `.tres` 路径；通常指向共享规则，仅在 rule_set 为空时使用。
@export_file("*.tres") var rule_set_resource_path: String = ""


func dependency_paths() -> Dictionary:
	# 只返回尚未装入内存的依赖，已赋值的组合槽不会被路径重复覆盖。
	var result: Dictionary = {}
	if song == null and not song_resource_path.is_empty():
		result["song"] = song_resource_path
	if chart == null and not chart_resource_path.is_empty():
		result["chart"] = chart_resource_path
	if stage_show == null and not stage_show_resource_path.is_empty():
		result["stage_show"] = stage_show_resource_path
	if visual_theme == null and not visual_theme_resource_path.is_empty():
		result["visual_theme"] = visual_theme_resource_path
	if background == null and not background_resource_path.is_empty():
		result["background"] = background_resource_path
	if reward == null and not reward_resource_path.is_empty():
		result["reward"] = reward_resource_path
	if rule_set == null and not rule_set_resource_path.is_empty():
		result["rule_set"] = rule_set_resource_path
	return result


func assign_dependency(slot: String, resource: Resource) -> bool:
	match slot:
		"song":
			if resource is SongDefinition:
				song = resource as SongDefinition
				return true
		"chart":
			if resource is SongChart:
				chart = resource as SongChart
				return true
		"stage_show":
			if resource is StageShow:
				stage_show = resource as StageShow
				return true
		"visual_theme":
			if resource is StageVisualTheme:
				visual_theme = resource as StageVisualTheme
				return true
		"reward":
			if resource is RewardDefinition:
				reward = resource as RewardDefinition
				return true
		"background":
			if resource is StageBackgroundDefinition:
				background = resource as StageBackgroundDefinition
				return true
		"rule_set":
			if resource is GameplayRuleSet:
				rule_set = resource as GameplayRuleSet
				return true
	return false


func dependencies_resolved() -> bool:
	return song != null and chart != null and stage_show != null and visual_theme != null and reward != null and rule_set != null and (background != null or background_resource_path.is_empty())


func resolve_dependencies_sync(cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE) -> bool:
	# 同步解析用于测试、编辑器和已经进入加载页后的收尾；菜单列表只需读取轻量元数据。
	var paths := dependency_paths()
	var keys: Array = paths.keys()
	keys.sort()
	for slot: String in keys:
		var resource := ResourceLoader.load(str(paths[slot]), "Resource", cache_mode)
		if resource == null or not assign_dependency(slot, resource):
			return false
	return dependencies_resolved()
