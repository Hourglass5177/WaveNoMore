extends SceneTree
## 混合图片、文字、动画、声音、镜头、BOSS 与环境的长工程测量。
var workspace
var failures:=0
func _initialize() -> void:run.call_deferred()
func settle(count:=4) -> void:
	for i in count:await process_frame
func check(ok: bool, caption: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+caption)
func run() -> void:
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false
	workspace.recovery_path="user://level-tests/mixed-workflow.json";root.add_child(workspace);await settle()
	workspace._open_path("res://examples/level-studio/渡口演出/level.json");await settle(12)
	var data: Dictionary=workspace.document.data.duplicate(true)
	var animation:=LevelProjectIO.open_project("res://examples/level-studio/动画与遮挡/level.json")
	var animated: Dictionary=animation.level.show.objects.filter(func(o):return o.type=="animated_sprite" and not o.asset.is_empty())[0]
	var actor: Dictionary=data.show.objects.filter(func(o):return o.type=="actor")[0]
	for index in 80:
		var kind: String=["text","sprite","animated_sprite","audio","actor"][index%5]
		var object_data:=LevelFormat.object(kind)
		object_data.fields.position=[80+(index%10)*180,80+(index/10)*110]
		if kind=="sprite":object_data.asset="assets/cover.svg"
		elif kind=="actor":object_data.asset=actor.asset
		elif kind=="animated_sprite":object_data.asset="res://examples/level-studio/动画与遮挡/"+str(animated.asset);object_data.animation=animated.animation
		data.show.objects.append(object_data)
		var track:=LevelFormat.track(object_data.id,"opacity","song")
		for key in 120:track.keys.append(LevelFormat.key(key*2500000,0.5 if key%2 else 1.0))
		data.show.tracks.append(track)
		if kind in ["audio","animated_sprite","actor"]:
			var clip_track:=LevelFormat.track(object_data.id,"audio" if kind=="audio" else "action","song","audio" if kind=="audio" else "action")
			var clip:=LevelFormat.clip(0,"assets/reply.wav" if kind=="audio" else "",300000000)
			clip.action=animated.animation if kind=="animated_sprite" else "idle";clip.loop=true;clip_track.clips=[clip];data.show.tracks.append(clip_track)
	var camera:=LevelFormat.object("camera");camera.fields.position=[960,540];data.show.objects.append(camera)
	var camera_track:=LevelFormat.track(camera.id,"position","song");camera_track.keys=[LevelFormat.key(0,[960,540]),LevelFormat.key(300000000,[1100,620])];data.show.tracks.append(camera_track)
	data.show.scene_cues=[{"id":"mixed_environment","name":"测试环境衔接","section":"song","difficulties":[],"time_us":6000000,"asset":"res://tests/fixtures/environment/b.tres","effect":"fade","blend_px":128.0,"static_fade_us":500000,"layers":{}}]
	workspace.document.reset(data,workspace.document.directory);await settle(12)
	var id: String=data.show.objects.filter(func(o):return o.type=="text")[0].id
	workspace.select_objects(PackedStringArray([id]));workspace.seek(2000000);await settle(8)
	var samples:={"浏览":[],"外观编辑":[],"选择":[]}
	for operation: String in samples:
		for index in 20:
			var begin:=Time.get_ticks_usec()
			if operation=="浏览":
				var event:=InputEventPanGesture.new();event.position=workspace.timeline.global_position+Vector2(400,100);event.delta=Vector2(0.1,0.2);root.push_input(event,true)
			elif operation=="外观编辑":workspace.set_property("color","ffeeddff" if index%2 else "ffffffff")
			else:workspace.select_objects(PackedStringArray([data.show.objects.filter(func(o):return o.type=="text")[index%2].id]))
			await process_frame;samples[operation].append(float(Time.get_ticks_usec()-begin)/1000)
	var result:={"renderer":DisplayServer.get_name(),"objects":data.show.objects.size(),"tracks":data.show.tracks.size(),"duration_sec":300,"measurements":{}}
	for operation in samples:
		samples[operation].sort();result.measurements[operation]={"p95_ms":samples[operation][18],"max_ms":samples[operation].back()}
		check(samples[operation][18]<100,operation+" P95 小于 100 ms")
	# 同素材两对象的 BOSS 局部预览必须换实例身份，帧时间与速率分离。
	var other: Dictionary=data.show.objects.filter(func(o):return o.type=="actor" and o.id!=actor.id)[0]
	workspace.select_objects(PackedStringArray([actor.id]));workspace.open_boss_binding();await settle()
	var panel: LevelBossPanel=workspace.boss_panel
	panel.open(actor.id);panel._slider.value=0.3;panel._change("rate",2.0)
	check(is_equal_approx(panel._slider.value,0.3),"修改动作速率不改变素材时间")
	panel.open(other.id);check(panel._preview.objects.has(other.id) and not panel._preview.objects.has(actor.id),"同素材切换对象刷新局部预览身份")
	var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/reliability/mixed-performance.json").simplify_path()
	LevelProjectIO.write_json(output,result);print("LEVEL MIXED ",JSON.stringify(result)," failures=",failures)
	workspace.queue_free();await settle();quit(failures)
