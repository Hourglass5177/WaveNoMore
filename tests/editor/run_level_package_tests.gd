extends SceneTree
var failures:=0
var checks:=0
var PACKAGE:=ProjectSettings.globalize_path("res://").path_join("../Levels/渡口演出.level.zip").simplify_path()
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _run() -> void:
	var inspected:=LevelPackageReader.finish(LevelPackageReader.read(PACKAGE,"",true,ChartSceneLibrary.shared().scene_ids()),true)
	check(inspected.errors.is_empty(),"独立关卡包检查全部难度与素材")
	if not inspected.errors.is_empty():printerr(inspected.errors);quit(1);return
	check(inspected.metadata.charts.size()==2 and inspected.metadata.song_id=="editor_example_ferry","关卡独立身份与多难度目录")
	check(inspected.metadata.get("cover_image") is Image,"封面可用于本地目录")
	var stage_result:=LevelPackageReader.finish(LevelPackageReader.read(PACKAGE,"hard",false,ChartSceneLibrary.shared().scene_ids()),false)
	check(stage_result.stage!=null and stage_result.errors.is_empty(),"正式加载共用关卡装配器")
	var stage:StageDefinition=stage_result.stage
	check(stage.chart.difficulty_id=="hard" and stage.stage_id=="editor_example_ferry:example_hard","不同关卡与难度成绩键独立")
	var library:=LocalChartLibrary.new();library.directory="user://level-package-tests/"+LevelFormat.id("library")
	check(library.import_checked(PACKAGE,inspected.metadata).is_empty(),"关卡包加入本地目录")
	var context:=library.context("editor_example_ferry","example_hard")
	check(context.level and context.level_id=="editor_example_ferry","目录保留正式关卡游玩上下文")
	check(FileAccess.file_exists(library.directory.path_join(library.data.songs.editor_example_ferry.cover_path)),"封面独立存入目录")
	var loaded:=LevelProjectLoader.load_stage("res://examples/level-studio/渡口演出/level.json","normal")
	var opened:=LevelProjectIO.open_project("res://examples/level-studio/渡口演出/level.json")
	var incomplete:Dictionary=opened.level.duplicate(true)
	incomplete.show.objects.append(LevelFormat.object("actor","missing:actor"))
	check(LevelProjectLoader.make_stage(incomplete,opened.directory,"normal",{},false).stage!=null,"缺失素材的草稿仍可预览基础玩法")
	check(LevelProjectLoader.make_stage(incomplete,opened.directory,"normal").stage==null,"正式装入仍定位缺失素材")
	var player:=LevelShowPlayer.new();root.add_child(player)
	player.configure(loaded.stage.stage_show.level_data,loaded.stage.stage_show.asset_directory,loaded.stage.stage_show.asset_packs,"normal")
	var compiled:=LevelBossCompiler.compile(loaded.stage,TempoMap.from_chart(loaded.stage.chart),player)
	check(not compiled.emissions.is_empty(),"从真实谱面稳定 ID 编排发射")
	var first:Dictionary=compiled.emissions[compiled.emissions.keys()[0]]
	var anchor:=player.anchor_at("ferryman","life","song",first.release_us,{"id":"pose","action":"attack","local_us":300000,"loop":false,"weight":1.0})
	check(anchor.is_equal_approx(Vector2(800,405)),"原生 AnimationPlayer 出手帧驱动动态锚点")
	player.show.tracks.append_array(compiled.tracks)
	player.seek("song",first.release_us+100000)
	check(not player.effects.is_empty(),"任意定位重建当前发射特效")
	player.seek("song",0);check(player.effects.is_empty(),"回拖清除未来特效")
	player.queue_free();await process_frame
	print("LEVEL PACKAGE TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
