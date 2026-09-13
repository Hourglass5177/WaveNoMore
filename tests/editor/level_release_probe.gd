extends Node2D
## 只装入验收用外部素材包，通过正式入口检查 Release EXE；不会随程序导出。
static var claimed:=false
var checks:=0
var failures:Array[String]=[]
var report_path:=""

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--qa-report"):return
	if claimed:return
	claimed=true
	# 预览会立即重建素材节点，验收协程由独立根节点持有。
	var runner:=Node2D.new();runner.set_script(get_script())
	get_tree().root.add_child.call_deferred(runner)
	runner._run.call_deferred()

func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: "+label)

func _run() -> void:
	var tree:=get_tree()
	for index in 3:await tree.process_frame
	var arguments:=OS.get_cmdline_user_args()
	for index in range(arguments.size()-1):
		if arguments[index]=="--qa-report":report_path=arguments[index+1]
	var app=tree.current_scene
	if OS.has_feature("minghe_level_editor"):
		await _tool(app)
	else:
		await _game(app)
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	app.queue_free()
	for index in 5:await tree.process_frame
	print("LEVEL RELEASE CHECKS: %d, failures: %d"%[checks,failures.size()])
	tree.quit(0 if failures.is_empty() else 1)

func _tool(workspace) -> void:
	var tree:=get_tree()
	for frame in 20:await tree.process_frame
	check(workspace.song_document.charts.size()==2,"实际工具 EXE 装入多难度工程")
	check(is_instance_valid(workspace.preview.stage_root),"实际工具使用正式玩法预览")
	check(workspace.show_player().drivers.has("ferryman"),"外部 PCK 原生动画装入")
	var thumbnail=workspace.show_player().assets.entries["example:ferryman"].thumbnail
	check(thumbnail!=null and thumbnail.get_width()==160,"PCK 内导入纹理依赖装入")
	workspace.select_objects(PackedStringArray(["ferryman"]));workspace.seek(3400000)
	for frame in 15:await tree.process_frame
	check(workspace.preview.stage_root.chart_scheduler.boss_emissions.size()>0,"BOSS 提前发射安装成功")
	check(workspace._save_as_to(report_path.get_base_dir().path_join("saved-example")),"实际工具另存完整工程")
	check(FileAccess.file_exists(report_path.get_base_dir().path_join("saved-example/song/song.json")),"另存包含源歌曲副本")
	for window_size in [Vector2i(1024,720),Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
		tree.root.size=window_size
		for frame in 3:await tree.process_frame
		workspace._reset_layout()
		for frame in 3:await tree.process_frame
		check(workspace.surface.size.x>=320 and workspace.timeline.size.y>=120,"窗口布局 "+str(window_size))
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png(report_path.get_base_dir().path_join("qa-%dx%d.png"%[window_size.x,window_size.y]))
	var player=workspace.show_player()
	player.seek("song",450000)
	check(player.objects["animation_0"].get_node("Content").frame==1,"实际工具按片段时间采样普通动画")
	workspace.select_objects(PackedStringArray(["animation_0"]))
	workspace.clear_object_asset_reference()
	for frame in 5:await tree.process_frame
	check(workspace.show_player().objects["animation_0"].get_node_or_null("Content")==null,"实际工具清除引用显示空对象")
	workspace.document.undo()
	for frame in 5:await tree.process_frame
	check(workspace.show_player().objects["animation_0"].get_node_or_null("Content")!=null,"实际工具撤销恢复动画引用")
	var picker=load("res://scenes/tools/level_studio/animation_import.tscn").instantiate();picker.directory=report_path.get_base_dir();workspace.add_child(picker)
	workspace._popup(picker,Vector2i(1000,680))
	for frame in 5:await tree.process_frame
	check(picker.get_node("%Sources").get_child_count()==4,"实际导入窗口保留三种来源与文件夹入口")
	picker.hide();picker.queue_free()
	# 通过实际发布的编辑器发起配套游戏，检查加载握手与返回编辑。
	workspace._trial_executable=OS.get_executable_path().get_base_dir().path_join("game/minghe.exe")
	workspace.set_object_field("name","未保存的发布验收快照")
	var cursor: int=workspace.document.cursor
	workspace.playtest()
	var pid: int=workspace._trial_pid
	var started:=Time.get_ticks_msec()
	while pid>0 and workspace._trial_stage!="ready" and Time.get_ticks_msec()-started<15000:await tree.create_timer(0.1).timeout
	check(workspace._trial_stage=="ready","发布编辑器发起配套游戏并收到 ready")
	check(workspace.document.cursor==cursor and workspace.document.dirty,"实际试玩不改变保存状态或历史")
	workspace._set_background(false);workspace.set_object_field("name","试玩打开时继续编辑")
	check(workspace.document.find("objects","animation_0").name=="试玩打开时继续编辑","试玩打开时恢复编辑能力")
	if pid>0:OS.kill(pid)
	await tree.create_timer(0.7).timeout
	check(workspace._trial_pid<0,"关闭配套游戏后释放试玩状态")
	workspace.audio.set_playing(false);workspace.preview.set_suspended(true)
	check(workspace.preview.stage_root.process_mode==Node.PROCESS_MODE_DISABLED,"试玩暂停后台玩法进程")

func _game(app) -> void:
	var tree:=get_tree()
	for frame in 60:await tree.process_frame
	var stage=app._current_screen
	check(stage!=null and stage.has_method("start_level"),"实际游戏 EXE 经正式试玩入口进入关卡")
	if stage==null or not stage.has_method("start_level"):return
	check(stage.stage_session.stage_definition.chart.difficulty_id=="hard","实际游戏装入指定难度")
	check(stage.level_show_player.drivers.has("animation_0"),"实际游戏加载外部普通动画描述")
	check(stage.level_show_player.drivers.has("ferryman"),"实际游戏加载外部 BOSS 动画")
	check(stage.level_show_player.assets.entries["example:ferryman"].thumbnail.get_width()==160,"实际游戏加载 PCK 纹理依赖")
	check(stage.chart_scheduler.boss_emissions.size()>0,"正式调度器包含 BOSS 提前发射")
	check(app._run_context.origin=="trial","试玩成绩不写正式存档")
	await tree.create_timer(6.5).timeout
	check(stage.stage_session.run_id==1,"倒计时和片头后只启动一轮歌曲")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(report_path.get_base_dir().path_join("qa-game.png"))
	stage.teardown()
