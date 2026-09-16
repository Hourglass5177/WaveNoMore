class_name LevelShowPlayer
extends Node2D
## 正式游玩和工具预览共用，画布使用 1920×1080 设计坐标。
signal sampled(section: String, time_us: int)
var show := {}
var difficulty := ""
var assets := LevelAssetLibrary.new()
var objects := {}
var drivers := {}
var sounds := {}
var states := {}
var current_section := "song"
var current_us := 0
var playing := false
var playback_rate := 1.0
var boss_battle: BossBattleEngine
var boss_song_us := 0
var boss_offset_us := 0
var boss_preview_mode := ""
var boss_emissions := {}
var camera_position := Vector2.ZERO
var camera_zoom := 1.0
## 反馈仅叠加颜色/特效，不切走预定攻击动作；同刻同对象合并一次。
var feedbacks := {}
var effects := {}
var _audio_from_us := 0
var environment_controller: ParallaxController
var environment_camera_effect: Callable
var _environment_signature := ""
var _environment_context := ""
var _render_ids := PackedStringArray()
var _render_signature := ""

func configure(data: Dictionary, directory: String, packs: Array, difficulty_id: String) -> void:
	stop_audio()
	if is_instance_valid(environment_controller):
		for wrapper: Node2D in objects.values():
			environment_controller.release_object_occlusion(wrapper)
	for child in get_children(): remove_child(child); child.queue_free()
	objects.clear(); drivers.clear(); states.clear(); feedbacks.clear(); effects.clear()
	_render_signature=""
	show = data.duplicate(true); difficulty = difficulty_id
	set_meta("asset_context",JSON.stringify([directory,packs]))
	# 编译时排序一次，播放过程中直接使用稳定轨道顺序。
	for track: Dictionary in show.get("tracks", []): track.keys.sort_custom(func(a, b): return int(a.time_us) < int(b.time_us))
	assets.configure(directory, packs)
	prepare_parameters()
	for object_data: Dictionary in show.get("objects", []):_create_object(object_data)
	seek("song", 0)

## 资源替换只更新对应实例，其他对象和声音保持原实例。
func update_show(data: Dictionary, directory: String, packs: Array, difficulty_id: String) -> void:
	var context:=JSON.stringify([directory,packs])
	var changed_library: bool=context!=get_meta("asset_context","")
	if changed_library:assets.configure(directory,packs);set_meta("asset_context",context)
	var rebuild:=[]
	for entry: Dictionary in data.get("objects",[]):
		var old:=LevelFormat.find(show.get("objects",[]),entry.id)
		if changed_library or old.is_empty() or old.get("asset")!=entry.asset or old.get("type")!=entry.type or old.get("boss",{}).get("visual","")!=entry.get("boss",{}).get("visual",""):rebuild.append(entry.id)
	for id in objects.keys():
		if id in rebuild or LevelFormat.find(data.get("objects",[]),id).is_empty():
			var wrapper: Node2D=objects[id]
			if is_instance_valid(environment_controller):environment_controller.release_object_occlusion(wrapper)
			if wrapper.get_parent()!=null:wrapper.get_parent().remove_child(wrapper)
			wrapper.queue_free();objects.erase(id);drivers.erase(id);states.erase(id);feedbacks.erase(id)
	show=data.duplicate(true);difficulty=difficulty_id;prepare_parameters();_render_signature=""
	for entry: Dictionary in show.get("objects",[]):
		if not objects.has(entry.id):_create_object(entry)

func _create_object(object_data: Dictionary) -> void:
	var wrapper := Node2D.new(); wrapper.name = str(object_data.id); add_child(wrapper)
	objects[object_data.id] = wrapper
	var content: Node
	match str(object_data.type):
		"text":
			var label := RichTextLabel.new(); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.scroll_active = false; label.bbcode_enabled = false; content = label
		"sprite", "image":
			var resource:=assets.resolve(str(object_data.asset))
			if resource is SpriteFrames:
				var animated:=AnimatedSprite2D.new();animated.sprite_frames=resource;animated.animation=str(object_data.get("animation","")) if resource.has_animation(str(object_data.get("animation",""))) else assets.default_animation(str(object_data.asset));content=animated
			else:
				var sprite := Sprite2D.new(); sprite.texture = resource as Texture2D; content = sprite
		"animated_sprite":
			var frames := assets.resolve(str(object_data.asset)) as SpriteFrames
			if frames != null:
				var sprite := AnimatedSprite2D.new(); sprite.sprite_frames=frames
				var action := str(object_data.get("animation",""))
				sprite.animation=action if frames.has_animation(action) else assets.default_animation(str(object_data.asset)); content=sprite
		"actor", "environment": content = assets.instantiate(str(object_data.asset))
	var boss_visual := str(object_data.get("boss",{}).get("visual",""))
	if boss_visual in ["bat","snake","goat","goat_eye"]:
		if content != null: content.free()
		content = load("res://src/presentation/actors/level_boss_visual.gd").new()
		for key in ["glow_strength","effect_scale","fragment_multiplier"]:content.set(key,float(assets.boss_defaults.get(key,1.0)))
		content.setup(boss_visual)
	if content != null:
		content.name = "Content"; wrapper.add_child(content)
		var driver := LevelAnimationDriver.new(); driver.configure(content); drivers[object_data.id] = driver

func prepare_parameters() -> void:
	for object_data:Dictionary in show.get("objects",[]):
		if not assets.entries.has(object_data.asset):continue
		object_data.color_properties=[]
		for parameter:String in assets.entries[object_data.asset].exposed_parameters:
			var spec:Dictionary=assets.entries[object_data.asset].exposed_parameters[parameter]
			var value:Variant=spec.get("default",0.0)
			if value is Vector2:value=[value.x,value.y]
			if value is Color:value=value.to_html()
			if spec.get("type","")=="color":object_data.color_properties.append(parameter)
			if not object_data.fields.has(parameter):object_data.fields[parameter]=value

func stop_audio() -> void:
	for player: AudioStreamPlayer in sounds.values(): player.stop(); player.queue_free()
	sounds.clear()

func seek(section: String, time_us: int) -> void:
	_audio_from_us = time_us
	stop_audio(); feedbacks.clear()
	for effect: Dictionary in effects.values(): effect.node.queue_free()
	effects.clear(); _sample(section, time_us, true)

func advance(section: String, time_us: int, audible := true, song_time_sec := NAN) -> void:
	_audio_from_us = current_us if section == current_section and time_us >= current_us else time_us
	if section != current_section or time_us < current_us: stop_audio()
	_sample(section, time_us, not audible, false, song_time_sec)

func refresh_visuals(section: String, time_us: int) -> void:
	_sample(section,time_us,true,true)

func _sample(section: String, time_us: int, silent: bool, preserve_audio := false, song_time_sec := NAN) -> void:
	if boss_battle != null and not boss_preview_mode.is_empty(): boss_battle.simulate(time_us-boss_offset_us if section=="song" else boss_song_us,boss_preview_mode=="perfect")
	_sync_render_order()
	current_section = section; current_us = time_us; states.clear();queue_redraw()
	var clips := LevelShowSampler.active_clips(show, section, time_us, difficulty)
	camera_position = Vector2.ZERO; camera_zoom = 1.0
	for object_data: Dictionary in show.get("objects", []):
		var state := LevelShowSampler.object_state(show, object_data, section, time_us, difficulty)
		states[object_data.id] = state
		if object_data.type == "camera":
			var shake := float(state.get("shake", 0.0))
			var seconds := float(time_us) / 1000000.0
			camera_position = LevelFormat.vec(state.position) - Vector2(960, 540) + Vector2(sin(seconds * 73.1), sin(seconds * 91.7)) * shake
			camera_zoom = float(state.get("zoom", 1.0))
	for object_data: Dictionary in show.get("objects", []):
		var wrapper: Node2D = objects[object_data.id]
		var state: Dictionary = states[object_data.id]
		wrapper.transform = canvas_transform(object_data, section, time_us, true)
		var appearance := LevelShowSampler.local_appearance(show, object_data, section, time_us, difficulty, state)
		wrapper.visible = appearance.visible; wrapper.modulate = appearance.color
		# 平铺渲染节点仍继承父组的显示区间和颜色。
		var parent := str(object_data.get("parent_id", ""))
		while not parent.is_empty():
			var ancestor := LevelFormat.find(show.objects, parent)
			var inherited := LevelShowSampler.local_appearance(show, ancestor, section, time_us, difficulty, states.get(parent,{}))
			wrapper.visible = wrapper.visible and inherited.visible
			wrapper.modulate *= inherited.color
			parent = str(ancestor.get("parent_id", ""))
		if feedbacks.has(object_data.id):
			var feedback: Dictionary = feedbacks[object_data.id]
			var age := time_us - int(feedback.time_us)
			if age >= 0 and age < 220000:
				wrapper.modulate = wrapper.modulate.lerp(Color("f9f3d8") if feedback.hit else Color("ad5069"), (1.0 - float(age) / 220000.0) * 0.7)
			else: feedbacks.erase(object_data.id)
		wrapper.z_index = 1000 if _root_layer(object_data) == "hud" else clampi(int(object_data.get("depth", 0)), -999, 999)
		var occlusion := _effective_occlusion(object_data)
		# BOSS 始终位于玩法音符所在的深度零 Canvas 之前，内部骨骼层也不能越过。
		if not object_data.get("boss", {}).is_empty() or (boss_battle != null and boss_battle.states.has(object_data.id)):
			occlusion = [0, "back"]
		if is_instance_valid(environment_controller) and not occlusion.is_empty() and object_data.layer != "hud":
			environment_controller.set_object_occlusion(wrapper, int(occlusion[0]), str(occlusion[1]),object_render_order(object_data))
			wrapper.z_index=0
		elif is_instance_valid(environment_controller):environment_controller.release_object_occlusion(wrapper)
		var object_clips: Array = clips.filter(func(clip): return clip.object_id == object_data.id and clip.type == "action")
		var automatic: Array=object_clips.filter(func(clip):return clip.get("boss_control",false))
		if not automatic.is_empty():
			automatic.sort_custom(func(a,b):return int(a.start_us)<int(b.start_us))
			object_clips=[automatic.back()]
		# 静息属于 BOSS 的常态，不依赖是否已配置可结算音符。
		var boss_settings: Dictionary=object_data.get("boss",{})
		if automatic.is_empty() and not boss_settings.is_empty():
			var idle:=str(boss_settings.get("actions",{}).get("idle",assets.default_animation(object_data.asset)))
			if not idle.is_empty():object_clips=[{"id":"boss_idle","action":idle,"local_us":maxi(0,time_us),"loop":true,"weight":1.0}]
		if boss_battle != null and boss_battle.states.has(object_data.id):
			var battle: Dictionary = boss_battle.states[object_data.id]
			var at := time_us - boss_offset_us if section == "song" else boss_song_us
			if not battle.hits.is_empty():
				var age:=at-int(battle.hits.back())
				if age>=0 and age<180000:wrapper.modulate=wrapper.modulate.lerp(Color.WHITE,0.45*(1.0-float(age)/180000))
			var pose := _boss_pose(battle, at)
			if not pose.is_empty(): object_clips = [pose]
			if battle.finish_us >= 0:
				var duration := int(battle.config.death_duration_us) if battle.hp == 0 else 600000
				var age := at - int(battle.finish_us)
				if battle.hp > 0 or str(battle.config.actions.death).is_empty(): wrapper.modulate.a *= 1.0-clampf(float(age)/duration,0,1)
				wrapper.visible = wrapper.visible and age < duration
		if drivers.has(object_data.id):
			var animation:=str(object_data.get("animation",""))
			for sprite: AnimatedSprite2D in drivers[object_data.id].sprites:
				if sprite.sprite_frames!=null and sprite.sprite_frames.has_animation(animation):sprite.set_meta("level_default_animation",animation)
			var root: Node = drivers[object_data.id].root
			if root.has_method("sample_show"):
				root.sample_show(show.tracks,object_data.id,boss_battle.states.get(object_data.id,{}) if boss_battle != null else {},time_us-boss_offset_us if section=="song" else boss_song_us,boss_offset_us)
			else:
				if object_clips.is_empty() and boss_battle != null and boss_battle.states.has(object_data.id):
					var idle: String = boss_battle.states[object_data.id].config.actions.idle
					if not idle.is_empty():object_clips=[{"id":"boss_idle","action":idle,"local_us":maxi(0,time_us),"loop":true,"weight":1.0}]
				drivers[object_data.id].sample(object_clips, time_us)
		var content := wrapper.get_node_or_null("Content")
		if content is RichTextLabel:
			content.size = LevelFormat.vec(state.get("size", [560, 100])); content.position = -content.size * 0.5
			content.text = str(state.get("text", "")); content.visible_ratio = float(state.get("visible_ratio", 1.0))
			content.horizontal_alignment = int(state.get("alignment", 1))
			content.add_theme_font_size_override("normal_font_size", int(state.get("font_size", 36)))
			var font := assets.resolve(str(state.get("font", ""))) as Font
			if font != null: content.add_theme_font_override("normal_font", font)
		if content != null and assets.entries.has(object_data.asset):
			for parameter: String in assets.entries[object_data.asset].exposed_parameters:
				var declaration: Dictionary = assets.entries[object_data.asset].exposed_parameters[parameter]
				var target := content.get_node_or_null(NodePath(str(declaration.get("node_path", "."))))
				if target != null:
					var property:=NodePath(str(declaration.property))
					var value:Variant=state.get(parameter,declaration.get("default"))
					var current:Variant=target.get_indexed(property)
					if current is Vector2:value=LevelFormat.vec(value)
					elif current is Color and value is String:value=Color(value)
					target.set_indexed(property,value)
	_sample_audio(clips, silent and not preserve_audio, preserve_audio)
	_sample_effects(clips, time_us)
	_sample_environment(song_time_sec)
	sampled.emit(section, time_us)

func _effective_occlusion(object_data: Dictionary) -> Array:
	return effective_occlusion(show,object_data)

static func effective_occlusion(data: Dictionary, object_data: Dictionary) -> Array:
	var current := object_data
	var top:=object_data
	while not str(top.get("parent_id","")).is_empty():top=LevelFormat.find(data.objects,top.parent_id)
	if top.get("layer","")=="hud":return []
	while not current.is_empty():
		if current.get("layer","")=="hud":return []
		var order := str(current.get("occlusion_order", "none"))
		var inherited: bool=bool(current.get("occlusion_inherit",order=="none"))
		if not inherited and order in ["front", "back"]:
			return [int(current.get("occlusion_depth", 0)), order]
		if not inherited:return []
		var parent_id := str(current.get("parent_id", ""))
		if parent_id.is_empty(): break
		current = LevelFormat.find(data.objects, parent_id)
	return []

func object_render_order(object_data: Dictionary) -> int:
	return _render_ids.find(str(object_data.id))

func _sync_render_order() -> void:
	var signature := JSON.stringify(show.get("objects",[]).map(func(item):return [item.id,item.parent_id,item.layer,item.depth,item.get("occlusion_depth",0),item.get("occlusion_order","none"),item.get("occlusion_inherit")]))
	if signature==_render_signature:return
	_render_signature=signature
	var sorted: Array = show.get("objects",[]).duplicate()
	sorted.sort_custom(func(a,b):
		var ka:=_render_key(a);var kb:=_render_key(b)
		for index in ka.size():
			if ka[index]!=kb[index]:return ka[index]<kb[index]
		return show.objects.find(a)<show.objects.find(b))
	_render_ids=PackedStringArray(sorted.map(func(item):return str(item.id)))

func _render_key(object_data: Dictionary) -> Array:
	var relation:=_effective_occlusion(object_data)
	if relation.is_empty():return [0,0,0,1000 if _root_layer(object_data)=="hud" else int(object_data.depth)]
	return [-1 if int(relation[0])>=0 else 1,-int(relation[0]),0 if relation[1]=="back" else 2,int(object_data.depth)]

func _exit_tree() -> void:
	if is_instance_valid(environment_controller):
		for wrapper in objects.values():
			if is_instance_valid(wrapper):environment_controller.release_object_occlusion(wrapper)

func canvas_transform(object_data: Dictionary, section: String, time_us: int, sampled := false) -> Transform2D:
	var result := LevelShowSampler.object_transform(show, object_data.id, section, time_us, difficulty, 0, states if sampled else {})
	var top := object_data
	while not str(top.get("parent_id", "")).is_empty(): top = LevelFormat.find(show.objects, top.parent_id)
	if top.get("layer", "world") == "hud": return result
	var position := camera_position if sampled else Vector2.ZERO; var zoom := camera_zoom if sampled else 1.0
	for camera: Dictionary in ([] if sampled else show.objects):
		if camera.type != "camera": continue
		var state := LevelShowSampler.object_state(show, camera, section, time_us, difficulty)
		var seconds := float(time_us) / 1000000.0
		position = LevelFormat.vec(state.position) - Vector2(960, 540) + Vector2(sin(seconds * 73.1), sin(seconds * 91.7)) * float(state.get("shake", 0.0))
		zoom = float(state.get("zoom", 1.0))
	result.origin -= position * (1.0 + float(object_data.get("depth", 0)) * 0.05)
	result.origin = Vector2(960, 540) + (result.origin - Vector2(960, 540)) * zoom
	result.x *= zoom; result.y *= zoom
	return result

func _sample_audio(clips: Array, silent: bool, preserve_audio := false) -> void:
	var active := {}
	if playing and not silent:
		for clip: Dictionary in clips:
			if clip.type != "audio": continue
			active[clip.id] = true
			var stream := assets.resolve(str(clip.asset)) as AudioStream
			if stream == null: continue
			var seconds := float(clip.local_us) / 1000000.0
			if clip.loop and stream.get_length() > 0.0: seconds = fposmod(seconds, stream.get_length())
			if seconds >= stream.get_length(): continue
			var player: AudioStreamPlayer = sounds.get(clip.id)
			if player == null:
				if preserve_audio and clip.get("transient",false):continue
				if clip.get("transient",false) and not (int(clip.start_us)>=_audio_from_us and int(clip.start_us)<=current_us):continue
				player = AudioStreamPlayer.new(); player.stream = stream; add_child(player); sounds[clip.id] = player
			if player.stream!=stream:player.stop();player.stream=stream
			player.pitch_scale = playback_rate * float(clip.rate)
			player.volume_db = float(states.get(clip.object_id, {}).get("volume_db", 0.0)) + float(clip.gain_db) + linear_to_db(maxf(float(clip.weight), 0.00001))
			if not player.playing or absf(player.get_playback_position() - seconds) > 0.1: player.play(seconds)
	for key: String in sounds.keys():
		if not active.has(key): sounds[key].stop(); sounds[key].queue_free(); sounds.erase(key)

func anchor_at(object_id: String, anchor_name: String, section: String, time_us: int, action_clip: Dictionary = {}) -> Vector2:
	var object_data := LevelFormat.find(show.get("objects", []), object_id)
	if object_data.is_empty(): return Vector2.ZERO
	var local := assets.anchor(str(object_data.asset), anchor_name)
	if objects.has(object_id):
		var content: Node = objects[object_id].get_node_or_null("Content")
		if content != null and content.has_method("sample_show"):
			content.sample_show(show.tracks,object_id,boss_battle.states.get(object_id,{}) if boss_battle != null else {},time_us-boss_offset_us,boss_offset_us)
			local=content.emission_anchor(anchor_name)
	if assets.entries.has(object_data.asset) and objects.has(object_id):
		var definition: Variant = assets.entries[object_data.asset].anchors.get(anchor_name)
		if definition is String or definition is NodePath:
			var content: Node = objects[object_id].get_node("Content")
			var node := content.get_node_or_null(NodePath(str(definition))) as Node2D
			if node != null:
				var active := LevelShowSampler.active_clips(show, section, time_us, difficulty).filter(func(clip): return clip.object_id == object_id and clip.type == "action")
				if not action_clip.is_empty(): active.append(action_clip)
				if boss_battle != null and boss_battle.states.has(object_id):
					var pose:=_boss_pose(boss_battle.states[object_id],time_us-boss_offset_us)
					if not pose.is_empty():active=[pose]
				if drivers.has(object_id): drivers[object_id].sample(active, time_us)
				local = objects[object_id].to_local(node.global_position)
	# 查询历史出手帧后恢复当前姿态，不能让路径辅助线把画面停在出手帧。
	if drivers.has(object_id):
		var root: Node=drivers[object_id].root
		var battle: Dictionary=boss_battle.states.get(object_id,{}) if boss_battle != null else {}
		var now:=current_us-boss_offset_us if current_section=="song" else boss_song_us
		if root.has_method("sample_show"):root.sample_show(show.tracks,object_id,battle,now,boss_offset_us)
		else:
			var active:=LevelShowSampler.active_clips(show,current_section,current_us,difficulty).filter(func(clip):return clip.object_id==object_id and clip.type=="action")
			var pose:=_boss_pose(battle,now) if not battle.is_empty() else {}
			if not pose.is_empty():active=[pose]
			drivers[object_id].sample(active,current_us)
	return canvas_transform(object_data, section, time_us) * local

func feedback(object_id: String, hit: bool, at_us: int, effect_asset := "") -> void:
	if feedbacks.has(object_id) and int(feedbacks[object_id].time_us) == at_us: return
	feedbacks[object_id] = {"time_us": at_us, "hit": hit}
	if not effect_asset.is_empty():
		_start_effect("feedback_" + object_id + str(at_us), object_id, effect_asset, at_us, 400000, true)

func _start_effect(id: String, object_id: String, asset: String, at_us: int, duration: int, reaction := false) -> void:
	var resource := assets.resolve(asset)
	var content: Node
	if resource is PackedScene: content = resource.instantiate()
	elif resource is Texture2D:
		var sprite := Sprite2D.new(); sprite.texture = resource; content = sprite
	if content == null: return
	var wrapper := Node2D.new(); add_child(wrapper); wrapper.add_child(content)
	var object_data := LevelFormat.find(show.objects, object_id)
	if not object_data.is_empty(): wrapper.transform = canvas_transform(object_data, current_section, at_us)
	var driver := LevelAnimationDriver.new(); driver.configure(content)
	var names := assets.actions(asset)
	effects[id] = {"node":wrapper,"driver":driver,"start_us":at_us,"duration_us":duration,"reaction":reaction,"action":names[0] if not names.is_empty() else "default"}

func _sample_effects(clips: Array, time_us: int) -> void:
	var active := {}
	for clip: Dictionary in clips:
		if clip.type != "effect": continue
		active[clip.id] = true
		if not effects.has(clip.id): _start_effect(clip.id, clip.object_id, clip.asset, clip.start_us, clip.duration_us)
	for id: String in effects.keys():
		var effect: Dictionary = effects[id]
		var age := time_us - int(effect.start_us)
		if age < 0 or age >= int(effect.duration_us) or (not effect.reaction and not active.has(id)):
			effect.node.queue_free(); effects.erase(id); continue
		effect.driver.sample([{"id":id,"action":effect.action,"local_us":age,"loop":false,"weight":1.0}], time_us)
## 只在环境、镜头安排或区段长度改变时重编排；普通选中和播放不走这里。
func configure_environment(controller: ParallaxController, level: Dictionary, initial: StageBackgroundDefinition, durations: Vector3i, base_velocity := Vector2.ZERO) -> void:
	var cues: Array = show.get("scene_cues", [])
	var asset := str(level.get("initial_background", ""))
	var cameras: Array = show.get("objects", []).filter(func(item): return item.type == "camera")
	var camera_ids: Array = cameras.map(func(item): return item.id)
	var tracks: Array = show.get("tracks", []).filter(func(track): return track.object_id in camera_ids)
	var context:=JSON.stringify([cameras,tracks,difficulty,durations,base_velocity])
	var signature := JSON.stringify([cues, asset, cameras, tracks, difficulty, durations, base_velocity, initial.get_instance_id() if initial != null else 0])
	if environment_controller == controller and signature == _environment_signature: return
	environment_controller = controller; _environment_signature = signature
	if cues.is_empty() and asset.is_empty():
		controller.set_environment(null); return
	if not asset.is_empty(): initial = assets.background(asset)
	var sequence := StageEnvironmentSequence.new()
	var snapshot := {"objects": cameras.duplicate(true), "tracks": tracks.duplicate(true)}
	var current_difficulty := difficulty
	var camera_at := Callable()
	if not cameras.is_empty():
		camera_at = func(at_us: int) -> Vector2:
			var at_section := "intro" if at_us < 0 else ("outro" if at_us >= durations.y else "song")
			var local_us := at_us + durations.x if at_us < 0 else (at_us - durations.y if at_section == "outro" else at_us)
			var offset := Vector2.ZERO
			for object_data: Dictionary in snapshot.objects:
				var state := LevelShowSampler.object_state(snapshot, object_data, at_section, local_us, current_difficulty)
				offset = LevelFormat.vec(state.get("position", [960,540])) - Vector2(960,540)
			return base_velocity * float(at_us + durations.x) / 1000000.0 + offset
	sequence.build(initial, cues, assets.background, difficulty, durations, camera_at, base_velocity,controller.environment if context==_environment_context else null)
	_environment_context=context
	controller.set_environment(sequence)

func _sample_environment(song_time_sec := NAN) -> void:
	if not is_instance_valid(environment_controller) or environment_controller.environment == null: return
	var sequence := environment_controller.environment
	var at_us := sequence.absolute_time(current_section, current_us)
	var steady := sequence.camera_at(at_us)
	# 震动只移动已排好的空间内容，不改变请求排队与完成时间。
	var shake := Vector2.ZERO
	var camera_effect:=Vector2.ZERO
	if environment_camera_effect.is_valid():camera_effect=environment_camera_effect.call(at_us)
	for object_data: Dictionary in show.get("objects", []):
		if object_data.type == "camera":
			var state := LevelShowSampler.object_state(show, object_data, current_section, current_us, difficulty)
			var seconds := float(current_us) / 1000000.0
			shake = Vector2(sin(seconds * 73.1), sin(seconds * 91.7)) * float(state.get("shake", 0.0))
	environment_controller.set_camera_position(steady + shake + camera_effect)
	environment_controller.sample_environment(at_us, steady + shake + camera_effect, song_time_sec)

func _root_layer(object_data: Dictionary) -> String:
	var top:=object_data
	while not str(top.get("parent_id","")).is_empty():top=LevelFormat.find(show.objects,top.parent_id)
	return str(top.get("layer","world"))

func _boss_pose(state: Dictionary, at: int) -> Dictionary:
	var action := ""
	var start := 0
	if state.finish_us >= 0 and at >= int(state.finish_us) and state.hp == 0:
		action = str(state.config.actions.death); start = state.finish_us
	elif state.phase_us >= 0 and at >= int(state.phase_us) and at < int(state.phase_us)+int(state.config.phase_duration_us):
		action = str(state.config.actions.phase_break); start = state.phase_us
	if action.is_empty(): return {}
	return {"id":"boss_state_"+str(state.config.id)+action,"action":action,"local_us":maxi(0,at-start),"loop":false,"weight":1.0}

func _draw() -> void:
	if current_section != "song":return
	var at:=current_us-boss_offset_us
	for path: Dictionary in boss_emissions.values():
		if not path.get("ghost",false) or at<int(path.release_us) or at>=int(path.entry_us):continue
		var sample:=BossEmissionPath.sample(path,at-int(path.release_us))
		var tint:=Color("efb87e") if path.side=="life" else Color("a8cde5")
		var remaining:=float(int(path.entry_us)-at)/1000000
		tint.a=clampf(remaining/0.2,0,1)
		draw_circle(sample.position,10,tint,false,2,true)
		draw_line(sample.position-sample.velocity.normalized()*26,sample.position,tint,3,true)
