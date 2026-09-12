extends SceneTree
## 在实际 Compatibility 渲染下对照低、中、高发波频率与高频点按。
const OUTPUT := "res://build/lingjun/rhythm-frames/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1500, 650)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var background := ColorRect.new()
	background.size = canvas.size
	background.color = Color("242330")
	canvas.add_child(background)
	var presentations: Array = []
	var actors: Array[SpineSprite] = []
	var frequencies := [1.0, 3.0, 7.0]
	var counters: Array[Label] = []
	var strikes := [0, 0, 0]
	var last_hits := [-INF, -INF, -INF]
	for i in 3:
		var label := Label.new()
		label.text = "发波 %d Hz" % frequencies[i]
		label.position = Vector2(25 + i * 500, 16)
		label.add_theme_font_size_override("font_size", 25)
		canvas.add_child(label)
		var actor := load("res://scenes/presentation/actors/lingjun_actor.tscn").instantiate() as SpineSprite
		canvas.add_child(actor)
		actor.position = Vector2(170 + i * 500, 570)
		actor.scale = Vector2.ONE * 0.42
		actors.append(actor)
		var presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
		presentation._life_actor = actor
		presentation._preview_time_driven = true
		presentation._reset_preview_actors()
		presentations.append(presentation)
		var counter := Label.new()
		counter.position = Vector2(25 + i * 500, 595)
		counter.add_theme_font_size_override("font_size", 21)
		canvas.add_child(counter)
		counters.append(counter)
	var caption := Label.new()
	caption.position = Vector2(25, 54)
	caption.add_theme_font_size_override("font_size", 22)
	canvas.add_child(caption)
	for frame in 330:
		var time := float(frame) / 30.0
		var held := frame < 2 or (frame >= 45 and frame < 180) or (frame >= 204 and frame < 279 and frame % 3 == 0)
		var action := "轻按下击" if frame < 45 else ("持续按住" if frame < 180 else ("收招" if frame < 204 or frame >= 279 else "每秒点按 10 次"))
		caption.text = "%s   %.2f s" % [action, time]
		for i in 3:
			presentations[i]._update_actor_snapshot({"time_us": roundi(time * 1000000.0), "life_held": held, "death_held": false, "life_frequency_hz": frequencies[i]})
			var last: float = actors[i].get_meta("_attack_last_hit_sec", -INF)
			if last > last_hits[i] + 0.0001:
				strikes[i] += 1
				last_hits[i] = last
			counters[i].text = "敲击 %d 次" % strikes[i]
		await process_frame
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(OUTPUT + "%04d.png" % frame)
	for presentation in presentations: presentation.free()
	canvas.queue_free()
	await process_frame
	print("Lingjun rhythm: 330 rendered frames; strikes ", strikes)
	quit()
