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
var camera_position := Vector2.ZERO
var camera_zoom := 1.0
## 反馈仅叠加颜色/特效，不切走预定攻击动作；同刻同对象合并一次。
var feedbacks := {}
var effects := {}
var _audio_from_us := 0

func configure(data: Dictionary, directory: String, packs: Array, difficulty_id: String) -> void:
	stop_audio()
	for child in get_children(): remove_child(child); child.queue_free()
	objects.clear(); drivers.clear(); states.clear(); feedbacks.clear(); effects.clear()
	show = data.duplicate(true); difficulty = difficulty_id
	# 编译时排序一次，播放过程中直接使用稳定轨道顺序。
	for track: Dictionary in show.get("tracks", []): track.keys.sort_custom(func(a, b): return int(a.time_us) < int(b.time_us))
	assets.configure(directory, packs)
	prepare_parameters()
	for object_data: Dictionary in show.get("objects", []):
		var wrapper := Node2D.new(); wrapper.name = str(object_data.id); add_child(wrapper)
		objects[object_data.id] = wrapper
		var content: Node
		match str(object_data.type):
			"text":
				var label := RichTextLabel.new(); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				label.scroll_active = false; label.bbcode_enabled = false; content = label
			"sprite", "image":
				var sprite := Sprite2D.new(); sprite.texture = assets.resolve(str(object_data.asset)) as Texture2D; content = sprite
			"actor", "environment": content = assets.instantiate(str(object_data.asset))
		if content != null:
			content.name = "Content"; wrapper.add_child(content)
			var driver := LevelAnimationDriver.new(); driver.configure(content); drivers[object_data.id] = driver
	seek("song", 0)

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

func advance(section: String, time_us: int, audible := true) -> void:
	_audio_from_us = current_us if section == current_section and time_us >= current_us else time_us
	if section != current_section or time_us < current_us: stop_audio()
	_sample(section, time_us, not audible)

func _sample(section: String, time_us: int, silent: bool) -> void:
	current_section = section; current_us = time_us; states.clear()
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
		wrapper.transform = canvas_transform(object_data, section, time_us)
		var appearance := LevelShowSampler.local_appearance(show, object_data, section, time_us, difficulty)
		wrapper.visible = appearance.visible; wrapper.modulate = appearance.color
		# 平铺渲染节点仍继承父组的显示区间和颜色。
		var parent := str(object_data.get("parent_id", ""))
		while not parent.is_empty():
			var ancestor := LevelFormat.find(show.objects, parent)
			var inherited := LevelShowSampler.local_appearance(show, ancestor, section, time_us, difficulty)
			wrapper.visible = wrapper.visible and inherited.visible
			wrapper.modulate *= inherited.color
			parent = str(ancestor.get("parent_id", ""))
		if feedbacks.has(object_data.id):
			var feedback: Dictionary = feedbacks[object_data.id]
			var age := time_us - int(feedback.time_us)
			if age >= 0 and age < 220000:
				wrapper.modulate = wrapper.modulate.lerp(Color("f9f3d8") if feedback.hit else Color("ad5069"), (1.0 - float(age) / 220000.0) * 0.7)
			else: feedbacks.erase(object_data.id)
		wrapper.z_index = 1000 if object_data.layer == "hud" else clampi(int(object_data.get("depth", 0)), -999, 999)
		var object_clips: Array = clips.filter(func(clip): return clip.object_id == object_data.id and clip.type == "action")
		if drivers.has(object_data.id): drivers[object_data.id].sample(object_clips, time_us)
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
	_sample_audio(clips, silent)
	_sample_effects(clips, time_us)
	sampled.emit(section, time_us)

func canvas_transform(object_data: Dictionary, section: String, time_us: int) -> Transform2D:
	var result := LevelShowSampler.object_transform(show, object_data.id, section, time_us, difficulty)
	var top := object_data
	while not str(top.get("parent_id", "")).is_empty(): top = LevelFormat.find(show.objects, top.parent_id)
	if top.get("layer", "world") == "hud": return result
	var position := Vector2.ZERO; var zoom := 1.0
	for camera: Dictionary in show.objects:
		if camera.type != "camera": continue
		var state := LevelShowSampler.object_state(show, camera, section, time_us, difficulty)
		var seconds := float(time_us) / 1000000.0
		position = LevelFormat.vec(state.position) - Vector2(960, 540) + Vector2(sin(seconds * 73.1), sin(seconds * 91.7)) * float(state.get("shake", 0.0))
		zoom = float(state.get("zoom", 1.0))
	result.origin -= position * (1.0 + float(object_data.get("depth", 0)) * 0.05)
	result.origin = Vector2(960, 540) + (result.origin - Vector2(960, 540)) * zoom
	result.x *= zoom; result.y *= zoom
	return result

func _sample_audio(clips: Array, silent: bool) -> void:
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
				if clip.get("transient",false) and not (int(clip.start_us)>=_audio_from_us and int(clip.start_us)<=current_us):continue
				player = AudioStreamPlayer.new(); player.stream = stream; add_child(player); sounds[clip.id] = player
			player.pitch_scale = playback_rate * float(clip.rate)
			player.volume_db = float(states.get(clip.object_id, {}).get("volume_db", 0.0)) + float(clip.gain_db) + linear_to_db(maxf(float(clip.weight), 0.00001))
			if not player.playing or absf(player.get_playback_position() - seconds) > 0.1: player.play(seconds)
	for key: String in sounds.keys():
		if not active.has(key): sounds[key].stop(); sounds[key].queue_free(); sounds.erase(key)

func anchor_at(object_id: String, anchor_name: String, section: String, time_us: int, action_clip: Dictionary = {}) -> Vector2:
	var object_data := LevelFormat.find(show.get("objects", []), object_id)
	if object_data.is_empty(): return Vector2.ZERO
	var local := assets.anchor(str(object_data.asset), anchor_name)
	if assets.entries.has(object_data.asset) and objects.has(object_id):
		var definition: Variant = assets.entries[object_data.asset].anchors.get(anchor_name)
		if definition is String or definition is NodePath:
			var content: Node = objects[object_id].get_node("Content")
			var node := content.get_node_or_null(NodePath(str(definition))) as Node2D
			if node != null:
				var active := LevelShowSampler.active_clips(show, section, time_us, difficulty).filter(func(clip): return clip.object_id == object_id and clip.type == "action")
				if not action_clip.is_empty(): active.append(action_clip)
				if drivers.has(object_id): drivers[object_id].sample(active, time_us)
				local = objects[object_id].to_local(node.global_position)
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
