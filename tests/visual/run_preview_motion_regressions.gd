extends SceneTree
var failures := 0
func _initialize(): run.call_deferred()
func run():
	var loaded := ChartProjectLoader.load_stage(ProjectSettings.globalize_path('res://../Charts/charts/test/song.json'))
	var sessions := []; var viewports := []
	for path in ['res://src/tools/chart_studio/preview_session.gd','res://tests/visual/preview_motion_reference.gd']:
		var view := SubViewport.new(); view.size = Vector2i(1920,1080); root.add_child(view); viewports.append(view)
		var session = load(path).new(); root.add_child(session); session.sound_enabled = false
		session.load_preview(loaded.stage,view); sessions.append(session)
		await session.seek_preview(0)
	for frame in 2400:
		var at := float(frame+1)/60.0
		for session in sessions: session.advance(at + session.offset_sec,false)
		if frame % 30 == 0: compare(sessions)
	for at in [1.5,5.0,10.0,18.75,24.0,35.0]:
		for session in sessions: await session.seek_preview(roundi((at+session.offset_sec)*1000000))
		compare(sessions)
	for session in sessions: session.free()
	for viewport in viewports: viewport.free()
	print('PREVIEW MOTION: ',failures,' differences'); quit(failures)
func compare(sessions: Array):
	var a: Dictionary = sessions[0].stage_root.presentation._note_visual_host._active
	var b: Dictionary = sessions[1].stage_root.presentation._note_visual_host._active
	for id in a:
		if not b.has(id): failures += 1; continue
		var node: Node2D = a[id].node; var other: Node2D = b[id].node
		if not node.transform.is_equal_approx(other.transform): failures += 1; print('POSE ',id)
		if node is GrayboxHoldVisual:
			if node._path_spine.size() != other._path_spine.size(): failures += 1; continue
			for i in node._path_spine.size():
				if not node._path_spine[i].is_equal_approx(other._path_spine[i]): failures += 1; print('SPINE ',id); break
