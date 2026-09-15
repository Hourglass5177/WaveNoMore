extends Node2D
## 仅通过验收素材包加载，正式发行包不包含探针。
static var claimed:=false
func _ready() -> void:
	if claimed or not OS.get_cmdline_user_args().has("--boss-delivery-check"):return
	claimed=true
	var runner:=Node2D.new();runner.set_script(get_script());get_tree().root.add_child.call_deferred(runner);runner.run.call_deferred()
func run() -> void:
	var tree:=get_tree()
	for frame in 20:await tree.process_frame
	var workspace=tree.current_scene
	var errors: Array=[]
	var player=workspace.surface.player
	var object_id: String=workspace.document.entries("objects")[0].id
	if workspace.surface.emissions.size()!=16:errors.append("音符自动关联数量")
	player.seek("song",1500000)
	var spine=player.drivers[object_id].spines[0]
	if spine.get_animation_state().get_track(0).get_animation().get_name()!="feixing":errors.append("静息动作")
	for track: Dictionary in player.show.tracks:
		if not track.has("binding_id"):continue
		var clip: Dictionary=track.clips[0]
		player.seek("song",int(clip.start_us)+100000)
		if spine.get_animation_state().get_track(0).get_animation().get_name()!=clip.action:errors.append("攻击动作")
		break
	workspace.select_objects(PackedStringArray([object_id]));workspace.open_boss_binding()
	workspace.preview.suspended=false
	await workspace.preview.seek_preview(119000000)
	player.seek("song",119000000)
	for frame in 5:await tree.process_frame
	var output: String=workspace.document.directory
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(output.path_join("交付版界面.png"))
	# 再打开第二个交付工程，检查另一个内置完整表现的发行资源。
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--second-level="):continue
		workspace._open_path(arg.trim_prefix("--second-level="))
		for frame in 20:await tree.process_frame
		player=workspace.surface.player
		if workspace.surface.emissions.size()!=36:errors.append("第二关关联数量")
		var snake=player.objects["fallback_boss_2"].get_node("Content")
		if snake.skeleton.get_skeleton()==null:errors.append("蛇骨骼未加载")
		workspace.preview.suspended=false
		await workspace.preview.seek_preview(139000000)
		player.seek("song",139000000)
		for frame in 5:await tree.process_frame
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(output.path_join("火-交付版.png"))
	workspace._trial_executable=OS.get_executable_path().get_base_dir().path_join("game/minghe.exe")
	workspace.playtest()
	var begin:=Time.get_ticks_msec()
	while workspace._trial_stage!="ready" and Time.get_ticks_msec()-begin<20000:await tree.create_timer(.1).timeout
	if workspace._trial_stage!="ready":errors.append("配套游戏未 ready："+workspace._trial_stage)
	if workspace._trial_pid>0:OS.kill(workspace._trial_pid)
	var file:=FileAccess.open(output.path_join("delivery-result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"errors":errors,"engine":Engine.get_version_info().string}));file.close()
	tree.quit(0 if errors.is_empty() else 1)
