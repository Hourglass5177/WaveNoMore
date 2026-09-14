extends SceneTree
## 正式准备入口 + 第二关只读测量；--dense 使用内存合成谱，不保存用户工程。
var preview
var frame_max_ms := 0.0
var last_frame_us := 0
func _initialize() -> void: run.call_deferred()
func frame_sample() -> void:
	var now := Time.get_ticks_usec()
	if last_frame_us != 0: frame_max_ms = maxf(frame_max_ms, (now-last_frame_us)/1000.0)
	last_frame_us = now
func run() -> void:
	var dense := "--dense" in OS.get_cmdline_user_args()
	var result := {"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"rendering":DisplayServer.get_name(),"max_fps":Engine.max_fps,"seeks":[]}
	var doc := StudioDocument.new()
	var start := Time.get_ticks_usec()
	if dense: make_dense(doc)
	else:
		var error := StudioProjectIO.open_project(ProjectSettings.globalize_path("res://../Charts/charts/第二关/song.json"),doc)
		if not error.is_empty(): push_error(error);quit(1);return
	result.read_ms = (Time.get_ticks_usec()-start)/1000.0
	result.note_events = doc.chart().note_events.size();result.tuning = doc.chart().tuning_paths.size();result.ghost = doc.chart().ghost_events.size()
	start = Time.get_ticks_usec()
	var prepared := ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	result.prepare_ms = (Time.get_ticks_usec()-start)/1000.0
	if prepared.stage == null: push_error(str(prepared.report));quit(2);return
	var view := SubViewport.new();view.size=Vector2i(960,540);root.add_child(view)
	preview=load("res://src/tools/chart_studio/preview_session.gd").new();root.add_child(preview)
	start=Time.get_ticks_usec()
	if not preview.load_preview(prepared.stage,view,prepared.compiled): quit(3);return
	result.load_ms=(Time.get_ticks_usec()-start)/1000.0
	print("PREPARE ",JSON.stringify(result))
	process_frame.connect(frame_sample)
	GameplayFrameProfile.enabled=true
	for target in ([4.2,150.0,299.0,298.5,299.0] if dense else [191.050997503153,60.0,120.0,191.050997503153,190.5,191.050997503153]):
		GameplayFrameProfile.clear();frame_max_ms=0;last_frame_us=0
		start=Time.get_ticks_usec()
		await preview.seek_preview(roundi(target*1000000.0))
		var sample := {"target":target,"total_ms":(Time.get_ticks_usec()-start)/1000.0,"profile_ms":GameplayFrameProfile.totals.duplicate(),"calls":GameplayFrameProfile.calls.duplicate(),"cache_bytes":preview.motion_cache.bytes,"cache_hits":preview.motion_cache.hits,"max_frame_ms":frame_max_ms}
		result.seeks.append(sample);print("SEEK ",JSON.stringify(sample))
	if not dense:
		# 修改后走正式准备入口，检查复用装配的实际耗时。
		var note: NoteEvent=doc.chart().note_events[-1];note.tick+=1
		start=Time.get_ticks_usec();prepared=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
		if prepared.stage != null:
			preview.load_preview(prepared.stage,view,prepared.compiled)
			await preview.seek_preview(191050998)
			result.edit_refresh_ms=(Time.get_ticks_usec()-start)/1000.0
	var output := "res://builds/preview-restore-dense.json" if dense else "res://builds/preview-restore-second.json"
	StudioProjectIO.write_json(output,result)
	preview.queue_free();view.queue_free();await process_frame;quit()

func make_dense(doc: StudioDocument) -> void:
	doc.new_project();doc.chart().end_tick=288000
	for i in 10:
		for side in 2:
			var hold:=NoteEvent.new();hold.event_id="hold%d_%d"%[i,side];hold.affinity=side;hold.kind=GameplayTypes.NoteKind.HOLD
			hold.tick=i*2880+480;hold.duration_ticks=1920;doc.chart().note_events.append(hold)
	for i in 9980:
		var note:=NoteEvent.new();note.event_id="tap%d"%i;note.affinity=i%2;note.tick=28800+roundi(i*259100.0/9980);doc.chart().note_events.append(note)
	for i in 10:
		var path:=ChartEditEvents.new_path(doc.chart(),i%2,i*2880+600,i*2880+2200)
		var middle:=TuningPathPoint.new();middle.event_id="middle%d"%i;middle.offset_ticks=700;middle.angle_deg=path.points[-1].angle_deg
		path.points[-1].angle_deg=path.points[0].angle_deg;path.points.insert(1,middle);doc.chart().tuning_paths.append(path)
		var ghost:=GhostEvent.new();ghost.event_id="ghost%d"%i;ghost.tick=i*2880+1800;ghost.count=2;ghost.tuning_ids=PackedStringArray([path.event_id]);doc.chart().ghost_events.append(ghost)
