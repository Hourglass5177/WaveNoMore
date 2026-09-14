extends SceneTree
## 让一侧 Hold 头 MISS，比较逐帧正常播放与定位的失败尾部，不改用户谱面。
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	run.call_deferred()
func run() -> void:
	var doc:=StudioDocument.new();StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json",doc)
	var view:=SubViewport.new();view.size=Vector2i(640,360);root.add_child(view)
	var preview=load("res://src/tools/chart_studio/preview_session.gd").new();root.add_child(preview)
	preview.load_preview(ChartProjectLoader.make_stage(doc.song,doc.chart()),view)
	preview._inputs=preview._inputs.filter(func(sample:SemanticInputSample):return sample.kind != GameplayTypes.SemanticInputKind.LIFE_A_PRESSED)
	var helper=load("res://tests/editor/run_preview_restore_tests.gd").new()
	var expected:={}
	var targets:=[4.5,6.2,8.8,9.6,11.0]
	await preview.seek_preview(0)
	var frame:=0
	for target in targets:
		while frame < roundi(target*120.0):
			frame+=1;preview.advance(float(frame)/120.0,false)
		expected[target]=helper.capture(preview)
	var failures:=0
	for target in targets:
		preview.motion_cache.clear()
		await preview.seek_preview(roundi(target*1000000.0))
		var state:Dictionary=helper.capture(preview)
		for key in state:
			if not helper.equivalent(state[key],expected[target][key],0.01 if key=="poses" else 0.001):
				failures+=1;print("FAIL ",target," ",key)
	print("PREVIEW FAILURE TESTS: ",failures)
	helper.free();preview.queue_free();view.queue_free();await process_frame;quit(1 if failures else 0)
