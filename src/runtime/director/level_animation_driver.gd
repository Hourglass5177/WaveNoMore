class_name LevelAnimationDriver
extends RefCounted
## 动作仅由演出时钟推进；素材内部状态机可实现 level_reset / level_advance 接口。
var root: Node
var players: Array[AnimationPlayer] = []
var sprites: Array[AnimatedSprite2D] = []
var spines: Array[Node] = []
var base_values: Array[Dictionary] = []
var previous := {}

func configure(node: Node) -> void:
	root = node; players.clear(); sprites.clear(); spines.clear(); base_values.clear(); previous.clear()
	root.process_mode = Node.PROCESS_MODE_DISABLED
	_collect(node)
	for player in players:
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.stop()
		var origin := player.get_node(player.root_node)
		var seen := {}
		for name in player.get_animation_list():
			var animation := player.get_animation(name)
			for index in animation.get_track_count():
				if animation.track_get_type(index) not in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER]: continue
				var path := animation.track_get_path(index)
				if seen.has(path): continue
				seen[path] = true
				var target := origin.get_node_or_null(NodePath(path.get_concatenated_names()))
				if target == null: continue
				var property := NodePath(path.get_concatenated_subnames())
				base_values.append({"target": target, "property": property, "value": target.get_indexed(property)})
	for sprite in sprites: sprite.pause()
	for spine in spines: spine.call("set_update_mode", SpineConstant.UpdateMode_Manual)

func _collect(node: Node) -> void:
	if node is CanvasItem and node.material!=null:node.material=node.material.duplicate()
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D: node.stop()
	if node is AnimationPlayer: players.append(node)
	if node is AnimatedSprite2D: sprites.append(node)
	if node.is_class("SpineSprite"): spines.append(node)
	for child in node.get_children(): _collect(child)

func sample(clips: Array, time_us: int) -> void:
	for entry in base_values: entry.target.set_indexed(entry.property, entry.value)
	for player in players:
		if clips.is_empty() and player.has_animation("RESET"):
			player.play("RESET"); player.seek(0.0, true, true); player.pause()
		for clip: Dictionary in clips:
			var action := str(clip.action)
			if not player.has_animation(action): continue
			var animation := player.get_animation(action)
			var local_sec := float(clip.local_us) / 1000000.0
			local_sec = fposmod(local_sec, animation.length) if clip.loop and animation.length > 0.0 else minf(local_sec, animation.length)
			var before := []
			for entry in base_values: before.append(entry.target.get_indexed(entry.property))
			player.play(action); player.seek(local_sec, true, true); player.pause()
			# 交叠片段依轨道顺序混合属性；seek 的 update_only 禁止方法和音频补播。
			for index in base_values.size():
				var entry: Dictionary = base_values[index]
				var value: Variant = entry.target.get_indexed(entry.property)
				if value is float or value is Vector2 or value is Vector3 or value is Color:
					entry.target.set_indexed(entry.property, lerp(before[index], value, float(clip.weight)))
	var active: Dictionary = clips.back() if not clips.is_empty() else {}
	for sprite in sprites:
		var action := str(active.get("action", "default"))
		if not sprite.sprite_frames.has_animation(action): continue
		var frames := sprite.sprite_frames
		var speed := frames.get_animation_speed(action)
		if speed <= 0.0: continue
		var total := 0.0
		for index in frames.get_frame_count(action): total += frames.get_frame_duration(action, index) / speed
		var seconds := float(active.get("local_us", 0)) / 1000000.0
		seconds = fposmod(seconds, total) if active.get("loop", false) and total > 0 else minf(seconds, total)
		sprite.animation = action; sprite.pause()
		for index in frames.get_frame_count(action):
			var duration := frames.get_frame_duration(action, index) / speed
			if seconds < duration or index == frames.get_frame_count(action) - 1:
				sprite.set_frame_and_progress(index, clampf(seconds / duration, 0, 1)); break
			seconds -= duration
	# 有状态素材固定以 60Hz 推进，避免可变帧长累计出不同的骨骼物理结果。
	# 正常播放续算整数步；回拖、换动作时从起点恢复，同一目标帧结果一致。
	var key := str(active.get("id", ""))
	var seconds := float(active.get("local_us", 0)) / 1000000.0
	var steps := maxi(0, floori(seconds * 60.0 + 0.000001))
	var restart := key != str(previous.get("id", "")) or steps < int(previous.get("steps", 0)) or previous.is_empty()
	var delta_steps := steps if restart else steps - int(previous.get("steps", 0))
	if root.has_method("level_reset") and root.has_method("level_advance"):
		if restart: root.call("level_reset", str(active.get("action", "")), active.get("loop", false))
		for step in delta_steps: root.call("level_advance", 1.0 / 60.0, true)
	for spine in spines:
		if not restart and delta_steps == 0: continue
		if restart:
			spine.get_animation_state().clear_tracks()
			spine.get_skeleton().set_to_setup_pose(); spine.get_skeleton().set_time(0.0)
			spine.get_skeleton().update_world_transform(SpineConstant.Physics_Reset)
			if not active.is_empty(): spine.get_animation_state().set_animation(str(active.action), bool(active.loop), 0)
		for step in delta_steps: spine.update_skeleton(1.0 / 60.0)
		spine.update_skeleton(0.0)
	previous = {"id": key, "steps": steps, "time_us": time_us}
