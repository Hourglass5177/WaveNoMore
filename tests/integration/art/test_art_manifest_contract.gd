extends RefCounted

## 美术资源接入规范测试。
## 验证的是真实运行场景、锚点和动画，不只相信 Manifest 中写下的元数据。

## 仓库当前的真实美术清单夹具，用来验证每项资产声明与运行时场景一致。
const MANIFEST := preload("res://content/visual/graybox_manifest.tres")
## 可打包成临时测试资产的通用占位场景，用于构造缺节点等反例。
const PLACEHOLDER_SCENE := preload("res://scenes/tools/art_lab/graybox_asset_placeholder.tscn")

## 已执行断言数量，用于确认清单中的各类合同确实被遍历。
var _checks := 0
## 累计失败文本；测试结尾一次汇报，避免首错掩盖后续资源问题。
var _failures: PackedStringArray = []


func run() -> Dictionary:
	_test_graybox_scene_contracts()
	_test_strict_placeholder_gate()
	_test_declared_metadata_cannot_hide_missing_nodes()
	_test_actor_requires_actual_animations()
	_test_canvas_instantiates_runtime_scene()
	var ok := _failures.is_empty()
	if ok:
		print("ART CONTRACT TESTS: %d checks passed." % _checks)
	else:
		printerr("ART CONTRACT TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
		for failure: String in _failures:
			printerr("  - " + failure)
	return {"ok": ok, "checks": _checks, "failures": Array(_failures)}


func _test_graybox_scene_contracts() -> void:
	var issues := ArtManifestValidator.validate(MANIFEST, true)
	var errors := _errors(issues)
	_expect_equal(errors.size(), 0, "MVP Graybox manifest passes instantiated scene validation")
	for entry in MANIFEST.entries:
		var instance := entry.runtime_scene.instantiate()
		instance.call("configure_from_manifest", entry)
		for anchor_name: String in entry.required_anchors:
			_expect(instance.find_child(anchor_name, true, false) != null, "%s owns anchor node %s" % [entry.asset_id, anchor_name])
		if entry.category == &"actor":
			var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
			_expect(player != null, "%s owns AnimationPlayer" % entry.asset_id)
			if player != null:
				for state_name: String in entry.required_states:
					_expect(player.has_animation(state_name), "%s owns animation %s" % [entry.asset_id, state_name])
		else:
			_expect(instance.has_method("art_lab_set_state"), "%s implements state interface" % entry.asset_id)
		instance.free()


func _test_strict_placeholder_gate() -> void:
	# 开发期允许 Graybox；严格发布模式必须逐项拒绝占位资产。
	var issues := ArtManifestValidator.validate(MANIFEST, false)
	var placeholder_errors := issues.filter(func(issue: Dictionary) -> bool:
		return issue.get("severity") == "error" and String(issue.get("message", "")).contains("禁止 Graybox")
	)
	_expect_equal(placeholder_errors.size(), MANIFEST.entries.size(), "strict validation promotes every placeholder to error")


func _test_declared_metadata_cannot_hide_missing_nodes() -> void:
	var entry := VisualAssetEntry.new()
	entry.asset_id = "broken_note"
	entry.category = &"note"
	entry.runtime_scene = _pack_scene(Node2D.new())
	entry.visual_bounds = Rect2(-32, -32, 64, 64)
	entry.anchors = {"hit_anchor": Vector2.ZERO}
	entry.required_anchors = PackedStringArray(["hit_anchor"])
	entry.state_names = PackedStringArray(["prepare"])
	entry.required_states = PackedStringArray(["prepare"])
	entry.placeholder = false
	var manifest := VisualAssetManifest.new()
	manifest.manifest_id = "broken_note_manifest"
	manifest.entries = [entry]
	var issues := ArtManifestValidator.validate(manifest, true)
	_expect(_contains_message(issues, "缺少实际锚点节点"), "validator inspects real anchor nodes instead of only metadata")
	_expect(_contains_message(issues, "未实现状态接口"), "validator invokes the real note state contract")
	_expect(_contains_message(issues, "未实现判定接口"), "validator invokes the real judgment contract")


func _test_actor_requires_actual_animations() -> void:
	var root := Node2D.new()
	var anchor := Marker2D.new()
	anchor.name = "body_center"
	root.add_child(anchor)
	# PackedScene 只打包归属于场景根节点的子节点，因此测试节点也必须设置 owner。
	anchor.owner = root
	var entry := VisualAssetEntry.new()
	entry.asset_id = "broken_actor"
	entry.category = &"actor"
	entry.runtime_scene = _pack_scene(root)
	entry.visual_bounds = Rect2(-32, -64, 64, 128)
	entry.anchors = {"body_center": Vector2.ZERO}
	entry.required_anchors = PackedStringArray(["body_center"])
	entry.state_names = PackedStringArray(["idle_loop"])
	entry.required_states = PackedStringArray(["idle_loop"])
	entry.placeholder = false
	var manifest := VisualAssetManifest.new()
	manifest.manifest_id = "broken_actor_manifest"
	manifest.entries = [entry]
	var issues := ArtManifestValidator.validate(manifest, true)
	_expect(_contains_message(issues, "缺少 AnimationPlayer"), "actor validation requires a real AnimationPlayer")


func _test_canvas_instantiates_runtime_scene() -> void:
	var canvas := MingheArtLabCanvas.new()
	canvas.size = Vector2(960, 540)
	var entry := MANIFEST.entry_by_id("note_su")
	_expect(canvas.set_manifest_entry(entry), "ArtLab canvas instantiates selected Manifest runtime_scene")
	_expect(canvas.get_preview_instance() != null, "ArtLab canvas exposes the live preview instance")
	if canvas.get_preview_instance() != null:
		_expect(canvas.get_preview_instance().scene_file_path == PLACEHOLDER_SCENE.resource_path, "preview is the entry runtime_scene, not a drawn proxy")
	_expect(canvas.apply_state(&"target_near"), "ArtLab calls selected asset state")
	canvas.judgment = GameplayTypes.JudgmentGrade.GOOD
	canvas.quality_level = 2
	canvas.background_pressure = 2
	canvas.free()


func _pack_scene(root: Node) -> PackedScene:
	var packed := PackedScene.new()
	var result := packed.pack(root)
	root.free()
	_expect(result == OK, "test fixture scene packs")
	return packed


func _errors(issues: Array[Dictionary]) -> Array:
	return issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")


func _contains_message(issues: Array[Dictionary], fragment: String) -> bool:
	for issue: Dictionary in issues:
		if String(issue.get("message", "")).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])
