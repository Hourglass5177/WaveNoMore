extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var directory:=ProjectSettings.globalize_path("res://../Levels/output/保底关卡/level_3")
	var result:=LevelProjectLoader.load_stage(directory.path_join("level.json"),"normal")
	if result.stage==null:printerr(result.errors);quit(1);return
	var stage: StageDefinition=result.stage
	var player:=LevelShowPlayer.new();root.add_child(player)
	player.configure(stage.stage_show.level_data,directory,[],"normal")
	var compiled: CompiledChart=ChartCompiler.compile(stage.chart,stage.rule_set).compiled
	var boss:=LevelBossCompiler.compile(stage,compiled.tempo_map,player)
	var battle:=BossBattleEngine.new();battle.configure(boss.battles,compiled,stage.rule_set);battle.simulate(200000000,true)
	var state: Dictionary=battle.states.fallback_boss_3
	var phase_sec:=float(state.phase_us)/1000000+stage.song.first_beat_offset_sec
	print("牲：关联=",boss.emissions.size(),"，最大血量=",state.maximum,"，全 Perfect 转阶段=",phase_sec,"秒，结束=",phase_sec+3)
	var ok: bool=boss.emissions.size()==36 and absf(phase_sec-92.214946)<.002
	player.queue_free();await process_frame;quit(0 if ok else 1)

