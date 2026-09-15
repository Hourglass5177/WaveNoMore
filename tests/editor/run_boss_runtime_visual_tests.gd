extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr(label)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for frame in 4:await process_frame
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/boss-runtime")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.size_2d_override=Vector2i(1920,1080);viewport.size_2d_override_stretch=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var player:=LevelShowPlayer.new();viewport.add_child(player)
	var object:=LevelFormat.object("actor","");object.id="goat";object.boss={"visual":"goat"}
	var binding:={"id":"binding","object_id":"goat","difficulty":"normal","note_ids":["a","b"],"action":"animation"}
	player.configure({"objects":[object],"tracks":[],"bindings":[binding]},"res://",[],"normal")
	var stage:=StageDefinition.new();stage.song=SongDefinition.new();stage.chart=SongChart.new();stage.chart.difficulty_id="normal";stage.rule_set=GameplayRuleSet.new()
	for pair in [["a",2880],["b",5760]]:
		var note:=NoteEvent.new();note.event_id=pair[0];note.tick=pair[1];note.boss=true;stage.chart.note_events.append(note)
	var compiled:=CompiledChart.new();compiled.tempo_map=TempoMap.from_chart(stage.chart)
	for note in stage.chart.note_events:compiled.notes.append({"id":note.event_id,"unit_kind":&"tap","start_us":compiled.tempo_map.tick_to_us(note.tick),"end_us":compiled.tempo_map.tick_to_us(note.tick)})
	var show:=LevelBossCompiler.compile(stage,compiled.tempo_map,player)
	player.show.tracks.append_array(show.tracks)
	player.boss_battle=BossBattleEngine.new();player.boss_battle.configure(show.battles,compiled,stage.rule_set);player.boss_preview_mode="perfect"
	player.seek("song",0);await settle()
	var initial:=viewport.get_texture().get_image();initial.save_png(output.path_join("idle.png"))
	player.seek("song",3500000);await settle()
	var phase:=viewport.get_texture().get_image();phase.save_png(output.path_join("phase.png"))
	check(initial.get_data()!=phase.get_data(),"转阶段必须改变实际像素")
	var content=player.objects.goat.get_node("Content")
	check(content.mode=="phase_break","半血进入揭眼")
	player.seek("song",7000000);await settle()
	check(content.form=="goat_eye" and content.mode=="death","最后一波后真眼死亡")
	viewport.get_texture().get_image().save_png(output.path_join("death.png"))
	player.seek("song",10500000);await settle();viewport.get_texture().get_image().save_png(output.path_join("fragments.png"))
	player.seek("song",15000000);await settle();check(not player.objects.goat.visible,"死亡播完隐藏主体")
	player.seek("song",0);await settle();check(viewport.get_texture().get_image().get_data()==initial.get_data(),"回拖恢复相同画面")
	player.boss_preview_mode="miss";player.seek("song",7000000);await settle();check(player.boss_battle.states.goat.hp>0,"未击败模拟不能假装击杀")
	viewport.queue_free();await settle();print("BOSS RUNTIME VISUAL failures=",failures);quit(failures)
