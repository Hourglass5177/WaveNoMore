extends SceneTree
## 可重复生成的制作示例；几何素材用于验证接入，不代表正式美术方案。
const ROOT := "res://examples/level-studio/渡口演出"
const ASSETS := "res://level_assets/editor_example"

func _initialize() -> void: _build.call_deferred()

func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ASSETS)
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("assets"))
	var actor := Node2D.new(); actor.name = "Ferryman"
	var body := Polygon2D.new(); body.name = "Mask"
	body.polygon = PackedVector2Array([Vector2(-110,-60),Vector2(-70,-125),Vector2(0,-90),Vector2(70,-125),Vector2(110,-60),Vector2(70,80),Vector2(0,135),Vector2(-70,80)])
	body.color = Color("607f84"); actor.add_child(body)
	var eye := Line2D.new(); eye.name = "Eyes"; eye.width = 9; eye.default_color = Color("ead6a5")
	eye.points = PackedVector2Array([Vector2(-64,-25),Vector2(-35,-8),Vector2(0,-30),Vector2(35,-8),Vector2(64,-25)]); actor.add_child(eye)
	for pair in [["Life",Vector2(-100,0)],["Death",Vector2(100,0)]]:
		var marker := Marker2D.new(); marker.name = pair[0]; marker.position = pair[1]; actor.add_child(marker)
	var idle := Animation.new(); idle.length = 2.0; idle.loop_mode = Animation.LOOP_LINEAR
	_add_track(idle,"Mask:position",[0.0,1.0,2.0],[Vector2.ZERO,Vector2(0,-12),Vector2.ZERO])
	var attack := Animation.new(); attack.length = 1.0
	_add_track(attack,"Mask:scale",[0.0,0.3,0.45,1.0],[Vector2.ONE,Vector2(0.85,1.15),Vector2(1.15,0.85),Vector2.ONE])
	_add_track(attack,"Life:position",[0.0,0.3,0.6,1.0],[Vector2(-100,0),Vector2(-160,-35),Vector2(-120,0),Vector2(-100,0)])
	_add_track(attack,"Death:position",[0.0,0.3,0.6,1.0],[Vector2(100,0),Vector2(160,35),Vector2(120,0),Vector2(100,0)])
	_animator(actor,{"idle":idle,"attack":attack})
	_save_scene(actor,ASSETS.path_join("ferryman.tscn"))
	var burst := Node2D.new(); burst.name = "Burst"
	var ring := Line2D.new(); ring.name = "Ring"; ring.width = 5; ring.default_color = Color("d7c498")
	for index in 49: ring.add_point(Vector2.from_angle(float(index)/48.0*TAU)*40)
	burst.add_child(ring)
	var flash := Animation.new(); flash.length = 0.4
	_add_track(flash,"Ring:scale",[0.0,0.4],[Vector2(0.2,0.2),Vector2(2.0,2.0)])
	_add_track(flash,"Ring:modulate",[0.0,0.4],[Color.WHITE,Color(1,1,1,0)])
	_animator(burst,{"burst":flash});_save_scene(burst,ASSETS.path_join("burst.tscn"))
	var manifest := VisualAssetManifest.new(); manifest.manifest_id = "渡口演出示例"
	var actor_entry := VisualAssetEntry.new(); actor_entry.asset_id = "example:ferryman";actor_entry.category=&"actor"
	actor_entry.display_name="渡口面具 · 几何占位";actor_entry.runtime_scene=load(ASSETS.path_join("ferryman.tscn"))
	actor_entry.thumbnail=load(ASSETS.path_join("thumbnail.svg"))
	actor_entry.state_names=PackedStringArray(["idle","attack"]);actor_entry.anchors={"life":"Life","death":"Death"};actor_entry.action_markers={"attack":{"release_sec":0.3}}
	actor_entry.visual_bounds=Rect2(-170,-140,340,280);manifest.entries.append(actor_entry)
	var effect_entry := VisualAssetEntry.new();effect_entry.asset_id="example:burst";effect_entry.category=&"effect";effect_entry.display_name="发射相纹"
	effect_entry.runtime_scene=load(ASSETS.path_join("burst.tscn"));effect_entry.state_names=PackedStringArray(["burst"]);manifest.entries.append(effect_entry)
	var manifest_path := ASSETS.path_join("manifest.tres")
	ResourceSaver.save(manifest,manifest_path)
	var error := LevelAssetPackWriter.write(manifest_path,ROOT.path_join("packs/example.pck"))
	if not error.is_empty():printerr(error);quit(1);return
	var song := StudioDocument.new();song.new_project();song.song.song_id="editor_example_song";song.song.title="渡口 · 测试拍";song.song.artist="编辑器示例"
	song.song.set_meta("json_source",{"audio":"click.wav","charts":[]})
	var wav := AudioStreamWAV.new();wav.mix_rate=22050;wav.format=AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray();bytes.resize(22050*24*2)
	for index in 22050*24:
		var seconds := float(index)/22050.0;var beat := fposmod(seconds,0.5)
		var sample := sin(beat*TAU*660.0)*exp(-beat*70)*0.13
		bytes.encode_s16(index*2,roundi(sample*32767))
	wav.data=bytes;song.song.audio_stream=wav
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("song"));wav.save_to_wav(ROOT.path_join("song/click.wav"))
	for difficulty in ["normal","hard"]:
		if difficulty=="hard":song.add_difficulty("hard")
		var chart := song.chart();chart.chart_id="example_"+difficulty;chart.end_tick=23040
		chart.set_meta("json_source",{"difficulty_name":"普通" if difficulty=="normal" else "困难","mapper":"示例谱","presentation":{"scene_id":"s08","use_scene_show":false}})
		var step := 1920 if difficulty=="normal" else 960
		for tick in range(5760,17281,step):
			var note:=NoteEvent.new();note.event_id=difficulty+"_"+str(tick);note.tick=tick;note.boss=true
			note.affinity=GameplayTypes.Affinity.ZHU if (tick/step)%2==0 else GameplayTypes.Affinity.XUAN
			if tick==17280:note.kind=GameplayTypes.NoteKind.HOLD;note.duration_ticks=480
			chart.note_events.append(note)
		var marker:=SectionMarker.new();marker.event_id="phase2";marker.tick=11520;marker.label="夜渡";chart.sections.append(marker)
		for side in 2:
			var hold:=NoteEvent.new();hold.event_id=difficulty+"_hold_"+str(side);hold.tick=19200;hold.duration_ticks=3840;hold.kind=GameplayTypes.NoteKind.HOLD;hold.affinity=side;hold.boss=true;chart.note_events.append(hold)
		var path:=TuningPathEvent.new();path.event_id=difficulty+"_tuning";path.tick=20160;path.affinity=0;path.hold_id=difficulty+"_hold_0";path.support_hold_id=difficulty+"_hold_1"
		for index in 3:
			var point:=TuningPathPoint.new();point.event_id="point_"+str(index);point.offset_ticks=index*960;point.angle_deg=-90.642246+(60 if index==1 else 0);path.points.append(point)
		chart.tuning_paths.append(path)
		var ghost:=GhostEvent.new();ghost.event_id=difficulty+"_ghost";ghost.tick=21120;ghost.boss=true;ghost.tuning_ids=PackedStringArray([path.event_id]);chart.ghost_events.append(ghost)
	error=StudioProjectIO.save_project(song,ROOT.path_join("song"))
	if not error.is_empty():printerr(error);quit(1);return
	var level:=LevelFormat.new_level();level.level_id="editor_example_ferry";level.title="渡口演出示例";level.author="编辑器示例";level.description="两种难度共用场景；曲前引导、BOSS 弹射、换景与曲后演出。"
	level.scene_id="s08";level.intro_us=2000000;level.outro_us=2000000;level.unlocked_by_default=true
	level.packs=[{"path":"packs/example.pck","manifest":manifest_path,"name":manifest.manifest_id}]
	var boss:=LevelFormat.object("actor","example:ferryman");boss.id="ferryman";boss.name="渡口面具";boss.fields.position=[960,440];boss.depth=40
	level.show.objects.append(boss)
	var idle_track:=LevelFormat.track(boss.id,"action","song","action");var idle_clip:=LevelFormat.clip(0,"",24000000);idle_clip.action="idle";idle_clip.loop=true;idle_clip.name="待机循环";idle_track.clips=[idle_clip];level.show.tracks.append(idle_track)
	var move:=LevelFormat.track(boss.id,"position");move.keys=[LevelFormat.key(0,[960,440]),LevelFormat.key(12000000,[960,440]),LevelFormat.key(16000000,[1040,480]),LevelFormat.key(24000000,[960,440])];move.keys[1].interpolation="ease";level.show.tracks.append(move)
	for chart in song.charts:
		var note_ids:=[]
		for note in ChartEditEvents.all(chart):if (note is NoteEvent or note is GhostEvent) and note.boss:note_ids.append(note.event_id)
		level.show.bindings.append({"id":"attack_"+chart.difficulty_id,"object_id":boss.id,"difficulty":chart.difficulty_id,"note_ids":note_ids,"action":"attack","release_sec":0.3,"return_us":600000,"rate":1.0,"action_duration_us":1000000,"life_anchor":"life","death_anchor":"death","effect":"example:burst","hit_effect":"example:burst"})
	var caption:=LevelFormat.object("text");caption.id="caption";caption.name="引导字幕";caption.fields.position=[960,140];caption.fields.text="渡口";caption.fields.font_size=44;level.show.objects.append(caption)
	for section in LevelFormat.SECTIONS:
		var words:=LevelFormat.track(caption.id,"text",section)
		words.keys=[LevelFormat.key(0,"渡口 · 请聆听钟声" if section=="intro" else ("渡口 · 测试拍" if section=="song" else "一曲既终，余响未息"))]
		level.show.tracks.append(words)
		if section!="song":
			var fade:=LevelFormat.track(caption.id,"opacity",section);fade.keys=[LevelFormat.key(0,0.0),LevelFormat.key(350000,1.0),LevelFormat.key(1650000,1.0),LevelFormat.key(2000000,0.0)];level.show.tracks.append(fade)
	var night:=LevelFormat.object("image","assets/night.svg");night.id="night";night.name="夜渡色幕";night.depth=-20;night.layer="world";night.fields.opacity=0.25;level.show.objects.append(night)
	_write_text(ROOT.path_join("assets/night.svg"),'<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="#123754"/></svg>')
	var night_track:=LevelFormat.track(night.id,"visibility","song","visibility");var night_clip:=LevelFormat.clip(12000000,"",12000000);night_clip.name="夜渡 · 淡入";night_clip.fade_in_us=2000000;night_track.clips=[night_clip];level.show.tracks.append(night_track)
	_write_text(ROOT.path_join("assets/cover.svg"),'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="#142c38"/><path d="M240 100 L320 65 L400 100 L375 240 L320 285 L265 240 Z" fill="#607f84"/><path d="M270 145 L300 165 L320 150 L340 165 L370 145" fill="none" stroke="#ead6a5" stroke-width="8"/></svg>')
	level.cover="assets/cover.svg"
	var reply:=AudioStreamWAV.new();reply.format=wav.format;reply.mix_rate=wav.mix_rate;reply.data=wav.data.slice(0,22050*2*2);reply.save_to_wav(ROOT.path_join("assets/reply.wav"))
	var voice:=LevelFormat.object("audio","assets/reply.wav");voice.id="reply";voice.name="收尾余响";voice.fields.volume_db=-12;level.show.objects.append(voice)
	var audio_track:=LevelFormat.track(voice.id,"audio","outro","audio");var audio_clip:=LevelFormat.clip(0,"assets/reply.wav",2000000);audio_clip.name="余响";audio_clip.fade_in_us=150000;audio_clip.fade_out_us=650000;audio_track.clips=[audio_clip];level.show.tracks.append(audio_track)
	error=LevelProjectIO.save(level,ROOT)
	if error.is_empty():error=LevelProjectIO.export_zip(level,ROOT,ProjectSettings.globalize_path("res://").path_join("../Levels/渡口演出.level.zip").simplify_path())
	if not error.is_empty():printerr(error);quit(1);return
	print("LEVEL EXAMPLE READY: "+ROOT);quit()

func _add_track(animation:Animation,path:String,times:Array,values:Array) -> void:
	var index:=animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(index,NodePath(path))
	for key in times.size():animation.track_insert_key(index,times[key],values[key])

func _animator(node:Node,animations:Dictionary) -> void:
	var player:=AnimationPlayer.new();player.name="AnimationPlayer";node.add_child(player)
	var library:=AnimationLibrary.new()
	for name in animations:library.add_animation(name,animations[name])
	player.add_animation_library("",library)

func _save_scene(node:Node,path:String) -> void:
	_owners(node,node)
	var packed:=PackedScene.new();packed.pack(node);ResourceSaver.save(packed,path);node.free()

func _owners(node:Node,owner:Node) -> void:
	for child in node.get_children():child.owner=owner;_owners(child,owner)

func _write_text(path:String,content:String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(content)
