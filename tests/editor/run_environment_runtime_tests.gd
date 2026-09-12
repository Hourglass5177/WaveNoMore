extends SceneTree
## 同一首真实谱面挂入换景前后，运行装配、BOSS 与判定仍使用原来的数据。
var failures:=0
var output:=ProjectSettings.globalize_path("res://../Levels/output/environment/runtime")
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
	if not value:failures+=1;printerr("FAIL ",label)
func settle() -> void:
	for index in 3:await process_frame
func run() -> void:
	var opened:=LevelProjectIO.open_project("res://examples/level-studio/渡口演出/level.json")
	var level:Dictionary=opened.level.duplicate(true)
	# 另存所需依赖全在测试目录，不改示例工程。
	for relative in LevelProjectIO.dependencies(level,opened.directory):
		if relative in ["level.json","show.json"]:continue
		var destination:=output.path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		check(DirAccess.copy_absolute(opened.directory.path_join(relative),destination)==OK,"复制示例依赖")
	check(LevelAssetPackWriter.write("res://tests/fixtures/environment/manifest.tres",output.path_join("environment.pck")).is_empty(),"创建背景资源包")
	level.packs.append({"path":"environment.pck","manifest":"res://tests/fixtures/environment/manifest.tres"})
	level.initial_background="environment_test_a";level.intro_us=2000000;level.outro_us=2000000
	level.show.scene_cues=[LevelFormat.scene_cue(1500000,"environment_test_b","intro"),LevelFormat.scene_cue(300000,"environment_test_c","song")]
	for difficulty in ["normal","hard"]:
		var original:=LevelProjectLoader.make_stage(opened.level,opened.directory,difficulty)
		var prepared:=LevelProjectLoader.make_stage(level,output,difficulty)
		check(prepared.errors.is_empty() and prepared.stage!=null,"双难度正式装配环境素材")
		if prepared.stage==null:continue
		var stage:StageDefinition=prepared.stage
		var before:CompiledChart=ChartCompiler.compile(original.stage.chart,stage.rule_set).compiled
		var after:CompiledChart=ChartCompiler.compile(stage.chart,stage.rule_set).compiled
		var replay:=ReplayData.new();replay.inputs=StudioPreviewInputs.build(before,stage.rule_set)
		check(before.content_hash==after.content_hash and ReplayRunner.run(before,stage.rule_set,replay).digest==ReplayRunner.run(after,stage.rule_set,replay).digest,"换景保持音符编译与 Replay 判定")
		var stage_root=load("res://scenes/stage/stage_root.tscn").instantiate()
		stage_root.initial_stage=null;stage_root.auto_start_initial_stage=false;root.add_child(stage_root);await settle()
		check(stage_root.load_stage(stage,false),"StageRoot 正式运行装配")
		stage_root.set_process(false);stage_root.level_show_external=true
		var player:LevelShowPlayer=stage_root.level_show_player
		var controller:ParallaxController=stage_root.get_parallax_controller()
		check(controller.environment!=null and controller.environment.transitions.size()==2,"运行层共用分层安排")
		var registered:=controller._objects.keys()
		var actors:=player.objects.duplicate()
		var boss:=LevelBossCompiler.compile(stage,after.tempo_map,player)
		check(not boss.emissions.is_empty(),"环境存在时保留 BOSS 编排")
		player.seek("song",3500000)
		var state:=controller.environment.displacement(controller.environment.lanes[0],3500000)
		player.seek("intro",500000);player.advance("song",3500000,false)
		check(controller.environment.displacement(controller.environment.lanes[0],3500000).is_equal_approx(state),"跨区段往返定位相同")
		check(controller._objects.keys()==registered and player.objects==actors,"换景保留注册对象及角色实例")
		# 歌曲时间必须包含首拍偏移，不拿判定时钟直接排列环境。
		var sample:=ClockSample.new();sample.visual_time_sec=1.0
		stage_root.level_show_external=false;stage_root._update_level_show(sample)
		check(player.current_us==roundi((1.0+stage.song.first_beat_offset_sec)*1000000),"首拍偏移统一换算歌曲时间")
		stage_root.queue_free();await settle()
	check(LevelProjectIO.save(level,output).is_empty(),"保存环境项目")
	var package:=output.path_join("environment.level.zip")
	check(LevelProjectIO.export_zip(level,output,package).is_empty(),"环境关卡 ZIP 包含资源包")
	var packaged:=LevelPackageReader.finish(LevelPackageReader.read(package,"normal",false,ChartSceneLibrary.shared().scene_ids()),false)
	check(packaged.errors.is_empty() and packaged.stage!=null,"运行入口重新装入含背景的 ZIP")
	var library:=LevelAssetLibrary.new();library.configure(output,level.packs)
	level.show.scene_cues[0].asset="missing_environment"
	check(library.validate_level(level).any(func(issue):return issue.get("scene_cue_id","")==level.show.scene_cues[0].id),"缺失环境定位到请求")
	print("ENVIRONMENT RUNTIME failures=",failures);quit(1 if failures else 0)
