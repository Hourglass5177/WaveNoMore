extends SceneTree
## 实际渲染下采样原始与游戏资源；输出仅放在忽略的 build 目录。

const OUTPUT := "res://build/lingjun/"
const ORIGINAL := "res://assets/character/lingjun/lingjun.tres"
const GAMEPLAY := "res://assets/character/lingjun/lingjun_gameplay.tres"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await _capture_samples()
	await _capture_twins(Vector2i(1920, 1080))
	await _capture_twins(Vector2i(1280, 720))
	if "--movie" in OS.get_cmdline_user_args(): await _capture_movie()
	print("Lingjun visual samples saved")
	quit()


func _capture_samples() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1800, 1320)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.size = canvas.size
	bg.color = Color("242330")
	canvas.add_child(bg)
	var times := [0.0, 0.433333333, 0.5, 1.0, 1.1, 1.433333333, 1.5, 2.1]
	var source_times := [0.0, 1.1, 1.166666667, 1.6]
	for i in 12:
		var origin := Vector2((i % 4) * 450, (i / 4) * 440)
		var original := i < 4
		var seconds: float = source_times[i] if original else times[i - 4]
		var label := Label.new()
		label.position = origin + Vector2(12, 8)
		label.text = "%s %.3f s" % ["Original down" if original else ("Down" if i < 8 else "Up"), seconds]
		label.add_theme_font_size_override("font_size", 24)
		canvas.add_child(label)
		var actor := SpineSprite.new()
		actor.skeleton_data_res = load(ORIGINAL if original else GAMEPLAY)
		actor.position = origin + Vector2(130, 420)
		actor.scale = Vector2(0.36, 0.36)
		canvas.add_child(actor)
		actor.set_update_mode(SpineConstant.UpdateMode_Manual)
		var track := actor.get_animation_state().set_animation("attack", false, 0)
		track.set_track_time(seconds)
		actor.update_skeleton(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUTPUT + "attack-two-moves.png")
	canvas.queue_free()
	await process_frame


func _capture_twins(size: Vector2i) -> void:
	var canvas := SubViewport.new()
	canvas.size = size
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var scale_factor := float(size.x) / 1920.0
	var bg := ColorRect.new()
	bg.size = size
	bg.color = Color("242330")
	canvas.add_child(bg)
	for side in 2:
		var actor := SpineSprite.new()
		actor.skeleton_data_res = load(GAMEPLAY)
		actor.position = (Vector2(480, 505) if side == 0 else Vector2(1440, 575)) * scale_factor
		actor.scale = Vector2.ONE * 0.48 * scale_factor
		actor.rotation = 0.0 if side == 0 else PI
		canvas.add_child(actor)
		actor.set_update_mode(SpineConstant.UpdateMode_Manual)
		var track := actor.get_animation_state().set_animation("attack", false, 0)
		track.set_track_time(0.5)
		actor.update_skeleton(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUTPUT + "twins-%d.png" % size.x)
	canvas.queue_free()
	await process_frame


func _capture_movie() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT + "frames")
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1200, 640)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.size = canvas.size
	bg.color = Color("242330")
	canvas.add_child(bg)
	var actors: Array[SpineSprite] = []
	for index in 2:
		var label := Label.new()
		label.position = Vector2(30 + index * 600, 20)
		label.text = "原始动画" if index == 0 else "下击 → 上挑"
		label.add_theme_font_size_override("font_size", 25)
		canvas.add_child(label)
		var actor := SpineSprite.new() if index == 0 else load("res://scenes/presentation/actors/lingjun_actor.tscn").instantiate() as SpineSprite
		actor.skeleton_data_res = load(ORIGINAL if index == 0 else GAMEPLAY)
		actor.position = Vector2(200 + index * 600, 590)
		actor.scale = Vector2.ONE * 0.46
		canvas.add_child(actor)
		actor.set_update_mode(SpineConstant.UpdateMode_Manual)
		actors.append(actor)
	var caption := Label.new()
	caption.position = Vector2(30, 602)
	caption.add_theme_font_size_override("font_size", 21)
	canvas.add_child(caption)
	var presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	presentation._life_actor = actors[1]
	presentation._preview_time_driven = true
	presentation._reset_preview_actors()
	var held := false
	var inputs := {0: true, 4: false, 42: true, 180: false, 222: true, 230: false, 232: true, 244: false}
	for frame in 276:
		if frame > 0: actors[0].update_skeleton(1.0 / 30.0)
		if inputs.has(frame):
			held = inputs[frame]
			# 左侧复现修复前的输入语义，右侧使用当前正式表现入口。
			var state := actors[0].get_animation_state()
			var track := state.get_track(0) if state.get_num_tracks() else null
			if held:
				if track != null and not track.is_complete(): track.set_loop(true)
				else: state.set_animation("attack", true, 0)
			elif track != null:
				track.set_track_time(fposmod(track.get_track_time(), track.get_animation().get_duration()))
				track.set_loop(false)
			actors[0].update_skeleton(0.0)
		presentation._update_actor_snapshot({"time_us": roundi(float(frame) / 30.0 * 1000000.0), "life_held": held, "death_held": false})
		caption.text = "%s   %.2f s" % ["按住" if held else "松开", float(frame) / 30.0]
		await process_frame
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % frame)
	presentation.free()
	canvas.queue_free()
	await process_frame
