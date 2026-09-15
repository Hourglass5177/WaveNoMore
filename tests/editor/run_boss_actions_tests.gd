extends SceneTree
class Assets extends LevelAssetLibrary:
	func actions(_asset: String) -> PackedStringArray: return ["idle", "attack", "attack_start", "attack_loop", "attack_end"]
	func default_animation(_asset: String) -> String: return "idle"
	func action_duration(_asset: String, _action: String) -> float: return 1.0
	func has_release_marker(_asset: String, _action: String) -> bool: return false
	func release_time(_asset: String, _action: String) -> float: return 0.0
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr(label)
func _initialize() -> void:
	var assets := Assets.new()
	var spec := LevelBossActions.resolve(assets, {"asset":"test"}, {"action":"idle"})
	check(spec.segmented and spec.action == "attack_start", "旧常态绑定必须自动识别攻击")
	var events: Array = []
	for time in [2000000,2500000,3000000]: events.append({"object_id":"boss","binding_id":"binding","asset":"test","release_us":time,"spec":spec})
	var tracks := LevelBossActions.tracks(events, assets, 100000)
	check(tracks.size()==3, "密集发射应合并成蓄势循环收招")
	check(tracks[1].clips[0].start_us==2100000, "首拍偏移只换算一次")
	var custom := LevelBossActions.resolve(assets, {"asset":"test"}, {"action":"attack","action_mode":"custom","release_sec":0.3})
	check(not custom.segmented and is_equal_approx(custom.release,0.3), "显式覆盖保留出手标记")
	print("BOSS ACTIONS failures=",failures); quit(failures)
