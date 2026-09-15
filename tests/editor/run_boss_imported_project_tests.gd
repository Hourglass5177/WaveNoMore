extends SceneTree
## 附件工程回归：测试目录只放在 Levels/output，不携带用户歌曲入库。
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr(label)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for frame in 5:await process_frame
func run() -> void:
	var directory:=ProjectSettings.globalize_path("res://../Levels/output/boss-user-repro/tutorial_1")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--boss-project="):directory=argument.trim_prefix("--boss-project=")
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;root.add_child(workspace);await settle()
	workspace._open_path(directory.path_join("level.json"));await settle()
	var player: LevelShowPlayer=workspace.surface.player
	var object: Dictionary=workspace.document.entries("objects")[0]
	check(workspace.document.entries("bindings").is_empty(),"打开不修改用户绑定数据")
	check(workspace.surface.emissions.size()==16,"单一已映射 BOSS 自动关联附件的 16 个音符")
	var driver: LevelAnimationDriver=player.drivers[object.id]
	var spine=driver.spines[0]
	player.seek("song",1000000)
	check(spine.get_animation_state().get_track(0).get_animation().get_name()=="feixing","没有手放片段时保持映射静息")
	var before: float=spine.get_animation_state().get_track(0).get_track_time()
	player.seek("song",1500000)
	check(spine.get_animation_state().get_track(0).get_track_time()>before,"静息随演出时钟推进")
	var count:=0
	for track: Dictionary in player.show.tracks:
		if not track.has("binding_id"):continue
		for clip: Dictionary in track.clips:
			if clip.action not in ["attack_start","attack_loop","attack_end"]:continue
			player.seek("song",int(clip.start_us)+mini(100000,int(clip.duration_us)/2))
			check(spine.get_animation_state().get_track(0).get_animation().get_name()==clip.action,"自动攻击真正进入骨骼轨道："+str(clip.action))
			count+=1
			if count==3:break
		if count==3:break
	check(count==3,"生成蓄势、持续、收招三段")
	workspace.select_objects(PackedStringArray([object.id]));workspace.open_boss_binding();await settle()
	check(workspace.boss_panel.data.note_ids.size()==16,"面板显示自动关联音符，能创建显式覆盖")
	check(workspace.document.entries("bindings").is_empty(),"查看自动关联不写盘")
	var duplicated: Dictionary=workspace.document.data.show.duplicate(true)
	var second: Dictionary=object.duplicate(true);second.id="other_boss";duplicated.objects.append(second)
	check(LevelBossCompiler.effective_bindings(workspace.song_document.chart(),duplicated,workspace.difficulty()).is_empty(),"多个 BOSS 不猜测音符归属")
	workspace.boss_panel._preview_role="attack_start";workspace.boss_panel._slider.value=0.2;workspace.boss_panel._sample_action();await settle()
	var local_spine=workspace.boss_panel._preview.drivers[object.id].spines[0]
	check(local_spine.get_animation_state().get_track(0).get_animation().get_name()=="attack_start","局部攻击预览不被静息覆盖")
	workspace.preview.suspended=false
	await workspace.preview.seek_preview(119000000)
	player.seek("song",119000000);await settle()
	root.get_texture().get_image().save_png(directory.path_join("boss-fixed-editor.png"))
	workspace.queue_free();await settle();print("BOSS IMPORTED PROJECT failures=",failures);quit(failures)
