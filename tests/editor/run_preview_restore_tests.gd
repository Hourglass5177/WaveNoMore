extends SceneTree
## 同一谱面比较旧逐步恢复与新恢复；用户项目只读。
var failures := 0
func _initialize() -> void: run.call_deferred()
func capture(preview) -> Dictionary:
	var capture_tool = load("res://tests/editor/measure_preview_seek.gd").new()
	var result: Dictionary = capture_tool.capture(preview)
	capture_tool.free()
	var actors := []
	var poses := []
	for actor in [preview.stage_root.presentation._life_actor, preview.stage_root.presentation._death_actor]:
		var tracks := []
		if is_instance_valid(actor) and actor.is_class("SpineSprite"):
			var state = actor.get_animation_state()
			for i in state.get_num_tracks():
				var track = state.get_track(i)
				if track != null: tracks.append([track.get_animation().get_name(), snappedf(track.get_track_time(),0.00001), track.get_time_scale()])
		actors.append(tracks)
		var pose := []
		if is_instance_valid(actor) and actor.is_class("SpineSprite"):
			for bone in actor.get_skeleton().get_bones():
				pose.append([bone.local_to_world(Vector2.ZERO),bone.local_to_world(Vector2.RIGHT),bone.local_to_world(Vector2.DOWN)])
		poses.append(pose)
	result.actors = actors
	result.poses = poses
	return result
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var actual := "--second" in args
	var doc := StudioDocument.new()
	var error := StudioProjectIO.open_project(ProjectSettings.globalize_path("res://../Charts/charts/第二关/song.json") if actual else "res://tests/editor/fixtures/tuning/song.json", doc)
	if not error.is_empty(): push_error(error); quit(1); return
	var expected := {}
	var measurements := {}
	if "--reuse-baseline" in args:
		var baseline := FileAccess.open("res://builds/preview-restore-baseline.bin", FileAccess.READ)
		expected = baseline.get_var()
	for mode in (["fast"] if "--reuse-baseline" in args else ["slow", "fast"]):
		var view := SubViewport.new(); view.size=Vector2i(640,360); root.add_child(view)
		var preview = load("res://tests/editor/slow_preview_session.gd" if mode == "slow" else "res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
		if not preview.load_preview(ChartProjectLoader.make_stage(doc.song,doc.chart()),view): quit(2); return
		measurements[mode]={}
		for target in ([60.0,120.0,191.050997503153,190.5,191.050997503153] if actual else [4.2,6.2,9.6,6.2]):
			if mode == "fast" and "--no-cache" in args: preview.motion_cache.clear()
			var start := Time.get_ticks_usec()
			await preview.seek_preview(roundi(target*1000000.0))
			measurements[mode][str(target)] = (Time.get_ticks_usec()-start)/1000.0
			print("RESTORE ",mode," target=",target," ms=",measurements[mode][str(target)])
			var state := capture(preview)
			if mode == "slow": expected[target]=state
			else:
				for key in state:
					if not equivalent(state[key], expected[target][key], 0.01 if key == "poses" else 0.001):
						failures+=1;print("DIFF ",target," ",key)
						if key == "poses":
							var maximum := 0.0
							for side in state.poses.size():
								for bone in state.poses[side].size():
									for axis in 3: maximum=maxf(maximum,state.poses[side][bone][axis].distance_to(expected[target].poses[side][bone][axis]))
							print("POSE MAX PIXELS=",maximum)
						if key in ["actors","visuals"]: print("EXPECTED ",expected[target][key]," ACTUAL ",state[key]) if key == "actors" else print("visual difference: ",describe_visual_difference(expected[target][key],state[key]))
		if mode == "slow" and actual:
			var baseline := FileAccess.open("res://builds/preview-restore-baseline.bin", FileAccess.WRITE)
			baseline.store_var(expected)
		if mode == "fast": print("CACHE bytes=",preview.motion_cache.bytes," hits=",preview.motion_cache.hits)
		preview.queue_free();view.queue_free();await process_frame
	StudioProjectIO.write_json("res://builds/preview-restore-actual.json" if actual else "res://builds/preview-restore-fixture.json", {"failures":failures,"measurements":measurements})
	print("RESTORE FAILURES=",failures," measurements=",JSON.stringify(measurements))
	quit(1 if failures else 0)


func equivalent(a: Variant, b: Variant, vector_tolerance := 0.001) -> bool:
	if typeof(a) != typeof(b): return false
	if a is float: return absf(a-b) <= 0.0001
	# Spine 使用单精度：合并时间步造成的舍入允许 0.01 个设计像素，不放宽判定/时间比较。
	if a is Vector2: return a.distance_to(b) <= vector_tolerance
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key],vector_tolerance): return false
		return true
	if a is Array or a is PackedVector2Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i],vector_tolerance): return false
		return true
	return a == b

func describe_visual_difference(a: Dictionary,b: Dictionary) -> Dictionary:
	var result := {}
	for id in a:
		if not b.has(id): result[id]="missing"; continue
		for key in a[id]:
			if equivalent(a[id][key],b[id][key]): continue
			if key == "spine":
				var maximum := 0.0
				for i in mini(a[id][key].size(),b[id][key].size()): maximum=maxf(maximum,a[id][key][i].distance_to(b[id][key][i]))
				result[str(id)+"/spine"]=[a[id][key].size(),b[id][key].size(),maximum]
			else: result[str(id)+"/"+str(key)]=[a[id][key],b[id][key]]
	return result
