extends SceneTree
## 用真实 Spine 资源验证单招、重按混合与定位重演。
var failures := 0
var checks := 0
var presentation
var life: SpineSprite
var death: SpineSprite

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	var scene := load("res://scenes/presentation/actors/lingjun_actor.tscn") as PackedScene
	var slot := Node2D.new()
	root.add_child(slot)
	life = presentation._instance_if_present(scene, slot)
	death = presentation._instance_if_present(scene, slot)
	presentation._life_actor = life
	presentation._death_actor = death
	# 正式场景会将角色移到视差层，输入仍应命中原实例。
	life.reparent(root)
	death.reparent(root)
	presentation._preview_time_driven = true
	_reset()
	var initial := _pose(life)
	_input(0.0, true, false)
	var track := life.get_animation_state().get_track(0)
	_check(is_equal_approx(track.get_track_time(), 0.46), "首次从右侧举槌位置开始，不播放完整前摇")
	_check(death.get_animation_state().get_track(0).get_animation().get_name() == "idle", "双方独立输入，另一侧继续静息")
	_check(_matches_source(0.573333333, 1.2), "下击仍使用原第二招")
	_check(_matches_source(1.54, 0.44), "上挑仍使用原第一招")
	_input(0.10, true, false)
	_check(is_equal_approx(float(life.get_meta("_attack_last_hit_sec")), 0.09), "首击保留约 90ms 的下砸轨迹")
	var before := _pose(life)
	_input(0.10, false, false)
	track = life.get_animation_state().get_track(0)
	_check(_same_pose(before, _pose(life)) and is_equal_approx(track.get_mix_duration(), 0.1), "松开用短混合进入单招收尾，不跳姿势")
	_check(not track.get_loop() and is_equal_approx(track.get_animation_end(), 1.1), "轻按只收完下击")
	_input(1.2, false, false)
	_check(_is_idle(life) and _same_pose(_pose(life), _pose(death)), "轻按回到同相位静息，无多余上挑")
	_reset()
	_input(0.0, true, true)
	_input(0.54, true, true)
	var bridge := _pose(life)
	_check(not _same_pose(bridge, initial), "长按两招之间不回站姿停住")
	_input(0.57, true, true)
	_check(not _same_pose(bridge, _pose(life)), "衔接段持续运动")
	_input(1.0, true, true)
	before = _pose(life)
	_input(1.0, false, true)
	track = life.get_animation_state().get_track(0)
	_check(is_equal_approx(track.get_animation_end(), 2.2), "上挑期间松开只收完上挑")
	_check(_same_pose(before, _pose(life)) and death.get_animation_state().get_track(0).get_loop(), "单侧松开连续，另一侧继续循环")
	_input(2.0, false, false)
	_check(_is_idle(life), "上挑收招恢复静息")
	_reset()
	_input(0.0, true, false)
	_input(0.1, false, false)
	_input(0.2, true, false)
	track = life.get_animation_state().get_track(0)
	_check(track.get_track_time() > 0.46 and float(life.get_meta("_attack_last_start_sec")) == 0.0, "上限内快速重按不重启当前动作")
	_input(0.60, false, false)
	before = _pose(life)
	_input(0.61, true, false)
	track = life.get_animation_state().get_track(0)
	_check(is_equal_approx(track.get_track_time(), 0.46) and is_equal_approx(track.get_mix_duration(), 0.025), "上限外重按从下击起点平滑出招")
	_check(_same_pose(before, _pose(life)), "允许的重按保持瞬间姿势连续")
	_input(0.65, true, false)
	_check(track.get_mixing_from() == null and track.get_track_time() < 0.55, "重按混合在下砸前结束，不能盖掉向下动作")
	var paused := _pose(life)
	await process_frame
	await process_frame
	_check(_same_pose(paused, _pose(life)), "暂停冻结混合及裙摆")
	_reset()
	_input(0.0, true, true, 1.0, 7.0)
	_check(is_equal_approx(life.get_animation_state().get_track(0).get_time_scale(), 0.7), "1 Hz 对应 0.7 倍敲击速度")
	_check(is_equal_approx(death.get_animation_state().get_track(0).get_time_scale(), 1.6), "7 Hz 对应 1.6 倍，双侧分别变速")
	_input(0.2, true, true, 3.0, 100.0)
	track = life.get_animation_state().get_track(0)
	_check(is_equal_approx(track.get_track_time(), 0.6) and is_equal_approx(track.get_time_scale(), 1.0), "改频保留已有相位，并从边界使用新速度")
	_check(is_equal_approx(death.get_animation_state().get_track(0).get_time_scale(), 1.65), "极高发波频率仍受最高倍率限制")
	presentation.attack_max_strikes_per_sec = 1.0
	_input(0.21, true, true, 100.0, 100.0)
	_check(life.get_animation_state().get_track(0).get_time_scale() <= 1.0, "长按也遵守总敲击频率上限")
	presentation.attack_max_strikes_per_sec = 2.0
	_check(_spam_is_bounded(), "高频点按不突破每秒 2 次上限，也不积压动作")
	_reset()
	_input(0.0, true, false)
	_input(1.05, true, false)
	_input(1.06, false, false)
	_input(1.07, true, false)
	_check(float(life.get_meta("_attack_last_start_sec")) == 0.0, "长按刚敲击后连按也不能绕过总频率上限")
	_check(_same_pose(_replay(false), _replay(true)), "快速点按回拖与小步重演一致")
	_check(_same_pose(_held_replay(false), _held_replay(true)), "连续长按跨循环定位一致")
	_check(_same_pose(_frequency_replay(false), _frequency_replay(true)), "改频边界的大步与小步重演一致")
	_check(_same_pose(_coalesced_replay(false), _coalesced_replay(true)), "限速内重按后一直按住，大步定位仍在准确时刻续招")
	_check(_loop_seam_is_continuous(), "长按循环首尾骨骼与裙摆相位连续")
	_reset()
	_check(_is_idle(life) and not life.has_meta("_attack_last_hit_sec"), "重试恢复静息并清除限速状态")
	_check(_same_pose(_pose(life), initial), "重试恢复站姿及裙摆")
	presentation.free()
	life.free()
	death.free()
	slot.free()
	print("Lingjun attack: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _input(seconds: float, life_held: bool, death_held: bool, life_hz: float = 3.0, death_hz: float = 3.0) -> void:
	presentation._update_actor_snapshot({"time_us": roundi(seconds * 1000000.0), "life_held": life_held, "death_held": death_held, "life_frequency_hz": life_hz, "death_frequency_hz": death_hz})

func _reset() -> void:
	presentation._reset_preview_actors()

func _replay(small_steps: bool) -> Array:
	_reset()
	var previous := 0.0
	var held := false
	for event: Array in [[0.0, true], [0.45, false], [0.48, true], [0.52, true]]:
		if small_steps:
			var sample := previous + 0.005
			while sample < float(event[0]) - 0.000001:
				_input(sample, held, false)
				sample += 0.005
		_input(event[0], event[1], false)
		previous = event[0]
		held = event[1]
	return _pose(life)

func _pose(actor: SpineSprite) -> Array:
	var values := []
	for bone in actor.get_skeleton().get_bones(): values.append(bone.get_global_transform())
	return values


func _held_replay(small_steps: bool) -> Array:
	_reset()
	_input(0.0, true, false)
	if small_steps:
		for step in range(1, 549): _input(float(step) * 0.005, true, false)
	else:
		_input(2.74, true, false)
	return _pose(life)


func _matches_source(seconds: float, source_seconds: float) -> bool:
	# 验证换序后仍使用原挥击，而不是把一招反放或只改了动作标签。
	var original := SpineSprite.new()
	original.skeleton_data_res = load("res://assets/character/lingjun/lingjun.tres")
	root.add_child(original)
	original.transform = life.transform
	original.set_update_mode(SpineConstant.UpdateMode_Manual)
	var source_track := original.get_animation_state().set_animation("attack", false, 0)
	source_track.set_track_time(source_seconds)
	original.update_skeleton(0.0)
	var current := SpineSprite.new()
	current.skeleton_data_res = life.skeleton_data_res
	root.add_child(current)
	current.transform = life.transform
	current.set_update_mode(SpineConstant.UpdateMode_Manual)
	current.get_animation_state().set_animation("attack", false, 0).set_track_time(seconds)
	current.update_skeleton(0.0)
	var expected := _pose(original)
	var same := _same_pose(_pose(current).slice(0, expected.size()), expected)
	original.free()
	current.free()
	return same

func _same_pose(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for index in a.size():
		var aa: Transform2D = a[index]
		var bb: Transform2D = b[index]
		if aa.origin.distance_to(bb.origin) > 0.02 or aa.x.distance_to(bb.x) > 0.0002 or aa.y.distance_to(bb.y) > 0.0002: return false
	return true

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)


func _spam_is_bounded() -> bool:
	_reset()
	var hits: Array[float] = []
	for step in 1001:
		_input(step * 0.01, step % 2 == 0, false, 100.0)
		var hit: float = life.get_meta("_attack_last_hit_sec", -INF)
		if is_finite(hit) and (hits.is_empty() or hit > hits.back() + 0.0001): hits.append(hit)
	_input(10.01, false, false)
	_input(12.0, false, false)
	if not _is_idle(life) or hits.size() > 21 or hits.size() < 2: return false
	for i in range(1, hits.size()):
		if hits[i] - hits[i - 1] < 0.5 - 0.0001: return false
	return true

func _is_idle(actor: SpineSprite) -> bool:
	return actor.get_animation_state().get_track(0).get_animation().get_name() == "idle"


func _frequency_replay(small_steps: bool) -> Array:
	_reset()
	_input(0.0, true, false, 1.0)
	var previous := 0.0
	var hz := 1.0
	for event: Array in [[0.3, 3.0], [0.8, 7.0], [1.7, 1.0], [2.73, 1.0]]:
		if small_steps:
			var time := previous + 0.005
			while time < event[0] - 0.00001:
				_input(time, true, false, hz)
				time += 0.005
		_input(event[0], true, false, event[1])
		hz = event[1]
		previous = event[0]
	return _pose(life)


func _coalesced_replay(small_steps: bool) -> Array:
	_reset()
	_input(0.0, true, false)
	_input(0.1, false, false)
	_input(0.2, true, false)
	if small_steps:
		for step in range(41, 541): _input(step * 0.005, true, false)
	else: _input(2.7, true, false)
	return _pose(life)


func _loop_seam_is_continuous() -> bool:
	_reset()
	_input(0.0, true, false)
	var track := life.get_animation_state().get_track(0)
	track.set_loop(false)
	track.set_track_time(0.0)
	life.update_skeleton(0.0)
	var first := _pose(life)
	track.set_track_time(2.2)
	life.update_skeleton(0.0)
	return _same_pose(first, _pose(life))
