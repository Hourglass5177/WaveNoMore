extends SceneTree
## 5 分钟 / 10000 关键帧的输入与帧耗时基准，结果是本机测量而非跨设备保证。
var workspace
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate(); workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/dense-recovery.json";root.add_child(workspace)
	for frame in 4:await process_frame
	var data:=LevelFormat.new_level()
	for index in 100:
		var object_data:=LevelFormat.object("text"); object_data.fields.text="对象 %d"%index;object_data.fields.position=[(index%10)*180+60,(index/10)*95+40];data.show.objects.append(object_data)
		var track:=LevelFormat.track(object_data.id,"opacity","song")
		for key_index in 100: track.keys.append(LevelFormat.key(key_index*3000000,0.3+0.7*(key_index%2)))
		data.show.tracks.append(track)
	workspace.document.reset(data)
	for frame in 8:await process_frame
	var samples := [];var frames := [];var before:=Time.get_ticks_usec()
	for index in 60:
		var start:=Time.get_ticks_usec()
		var pan:=InputEventPanGesture.new();pan.position=workspace.timeline.global_position+Vector2(400,100);pan.delta=Vector2(0.2,0.1);root.push_input(pan,true)
		await process_frame
		samples.append(float(Time.get_ticks_usec()-start)/1000);frames.append(float(Time.get_ticks_usec()-before)/1000);before=Time.get_ticks_usec()
	samples.sort();frames.sort()
	var result:={"objects":100,"keys":10000,"duration_sec":300,"input_to_frame_p95_ms":samples[56],"frame_p95_ms":frames[56],"frame_max_ms":frames.back(),"renderer":DisplayServer.get_name()}
	print("LEVEL DENSE UI: ",JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ux").simplify_path());LevelProjectIO.write_json(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ux/dense-ui.json").simplify_path(),result)
	workspace.queue_free();await process_frame;quit(0 if samples[56]<100 else 1)
