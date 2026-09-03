## 美术交付校验器。除检查 Manifest 资源中的字段外，还会真实实例化场景，检查锚点、动画和状态接口。
class_name ArtManifestValidator
extends RefCounted

## Manifest 声明坐标与场景实际锚点允许的最大距离，单位为设计画布像素。
const ANCHOR_POSITION_TOLERANCE := 1.0


static func validate(manifest: VisualAssetManifest, allow_placeholders: bool = true) -> Array[Dictionary]:
	# 第一层检查清单自身：身份不重复、场景可实例化、边界与必需声明齐全。
	var issues: Array[Dictionary] = []
	if manifest == null:
		issues.append(_issue("error", "manifest", "Manifest 为空。"))
		return issues
	var ids: Dictionary = {}
	for index: int in manifest.entries.size():
		var entry := manifest.entries[index]
		var location := "entries[%d]" % index
		if entry == null:
			issues.append(_issue("error", location, "资产条目为空。"))
			continue
		if entry.asset_id.is_empty():
			issues.append(_issue("error", location, "asset_id 不能为空。"))
		elif ids.has(entry.asset_id):
			issues.append(_issue("error", location, "asset_id 重复：%s" % entry.asset_id))
		else:
			ids[entry.asset_id] = true
		if entry.runtime_scene == null:
			issues.append(_issue("error", location, "缺少 runtime_scene。"))
		elif not entry.runtime_scene.can_instantiate():
			issues.append(_issue("error", location, "runtime_scene 无法实例化。"))
		else:
			issues.append_array(_validate_runtime_scene(entry, location))
		if entry.visual_bounds.size.x <= 0.0 or entry.visual_bounds.size.y <= 0.0:
			issues.append(_issue("error", location, "visual_bounds 必须为正尺寸。"))
		for anchor_name: String in entry.required_anchors:
			if not entry.anchors.has(anchor_name):
				issues.append(_issue("error", location, "Manifest 缺少锚点坐标：%s" % anchor_name))
		for state_name: String in entry.required_states:
			if state_name not in entry.state_names:
				issues.append(_issue("error", location, "Manifest 缺少状态声明：%s" % state_name))
		if entry.placeholder and not allow_placeholders:
			issues.append(_issue("error", location, "严格交付禁止 Graybox 占位资产：%s" % entry.asset_id))
	return issues


## 校验实例不会挂进正在运行的 SceneTree，所以状态接口不能依赖 _ready() 已经执行。
static func _validate_runtime_scene(entry: VisualAssetEntry, location: String) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var instance := entry.runtime_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if instance == null:
		issues.append(_issue("error", location, "runtime_scene 实例化返回空节点。"))
		return issues
	if not instance is CanvasItem:
		issues.append(_issue("error", location, "runtime_scene 根节点必须是 Node2D 或 Control。"))
	if instance.has_method("configure_from_manifest"):
		instance.call("configure_from_manifest", entry)
	issues.append_array(_validate_scene_anchors(instance, entry, location))
	issues.append_array(_validate_scene_states(instance, entry, location))
	instance.free()
	return issues


## 声明坐标与场景里的真实锚点必须同时存在；只容许一像素以内的浮点误差。
static func _validate_scene_anchors(instance: Node, entry: VisualAssetEntry, location: String) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for anchor_name: String in entry.required_anchors:
		var anchor := instance.find_child(anchor_name, true, false)
		if anchor == null:
			issues.append(_issue("error", location, "runtime_scene 缺少实际锚点节点：%s" % anchor_name))
			continue
		if not anchor is Node2D and not anchor is Control:
			issues.append(_issue("error", location, "锚点必须是 Marker2D/Node2D/Control：%s" % anchor_name))
			continue
		if not entry.anchors.has(anchor_name):
			continue
		var actual := _canvas_item_position_in_root(instance, anchor as CanvasItem)
		var expected := Vector2(entry.anchors[anchor_name])
		if actual.distance_to(expected) > ANCHOR_POSITION_TOLERANCE:
			issues.append(_issue(
				"error",
				location,
				"实际锚点 %s 与 Manifest 不一致（实际 %s，声明 %s）。" % [anchor_name, actual, expected]
			))
	return issues


static func _validate_scene_states(instance: Node, entry: VisualAssetEntry, location: String) -> Array[Dictionary]:
	# 角色以 AnimationPlayer 动画名为合同；音符和场域以可调用的状态接口为合同。
	var issues: Array[Dictionary] = []
	if entry.category == &"actor":
		var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			issues.append(_issue("error", location, "角色 runtime_scene 缺少 AnimationPlayer。"))
		else:
			for state_name: String in entry.required_states:
				if not player.has_animation(StringName(state_name)):
					issues.append(_issue("error", location, "角色缺少实际动画：%s" % state_name))
	else:
		if not instance.has_method("art_lab_set_state"):
			issues.append(_issue("error", location, "runtime_scene 未实现状态接口 art_lab_set_state(state, payload)。"))
		else:
			for state_name: String in entry.required_states:
				var state_accepted: Variant = instance.call("art_lab_set_state", StringName(state_name), {})
				if state_accepted is bool and not bool(state_accepted):
					issues.append(_issue("error", location, "runtime_scene 拒绝必需状态：%s" % state_name))
	if entry.category in [&"note", &"field"]:
		if not instance.has_method("art_lab_set_judgment"):
			issues.append(_issue("error", location, "音符/场域未实现判定接口 art_lab_set_judgment(grade)。"))
		else:
			for grade: int in range(GameplayTypes.JudgmentGrade.PERFECT, GameplayTypes.JudgmentGrade.MISS + 1):
				var judgment_accepted: Variant = instance.call("art_lab_set_judgment", grade)
				if judgment_accepted is bool and not bool(judgment_accepted):
					issues.append(_issue("error", location, "runtime_scene 拒绝判定等级：%d" % grade))
	return issues


static func _canvas_item_position_in_root(root: Node, item: CanvasItem) -> Vector2:
	if item is Node2D:
		var point := (item as Node2D).global_position
		if root is Node2D:
			return (root as Node2D).to_local(point)
		return point
	if item is Control:
		var point := (item as Control).global_position
		if root is Control:
			return point - (root as Control).global_position
		return point
	return Vector2.ZERO


static func _issue(severity: String, location: String, message: String) -> Dictionary:
	return {"severity": severity, "location": location, "message": message}
