extends SceneTree
## 使用正式选关实例采样呼吸周期；冻结其他动效便于比较字样。
var frames: Array[Image] = []
func _init() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	var page = load("res://scenes/screens/stage_select_screen.tscn").instantiate()
	root.add_child(page)
	await create_timer(0.4).timeout
	for kind in ["fc","ap"]:
		var data: Array[Dictionary] = page._levels.duplicate(true)
		data[0]["full_combo"] = true
		data[0]["all_perfect"] = kind == "ap"
		page.set_levels(data,0)
		await process_frame
		page.process_mode = Node.PROCESS_MODE_DISABLED
		var mark = page._cards[0].get_node("Rating")
		var folder: String = "res://builds/clear-mark/"+kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		for i in 48:
			mark.elapsed = i*0.1
			mark._sample()
			await RenderingServer.frame_post_draw
			frames.append(root.get_texture().get_image())
		for i in frames.size(): frames[i].save_png(folder+"/%03d.png"%i)
		frames.clear()
		page.process_mode = Node.PROCESS_MODE_INHERIT
	# 同一场景、同一静止帧重现旧的 -8 px 分数偏移，单独比较对齐修正。
	page.process_mode = Node.PROCESS_MODE_DISABLED
	var score = page._cards[0].get_node("Score")
	for value in [0,165467]:
		score.set_score(value)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/clear-mark/alignment-after-%d.png" % value)
		var origin: Vector2 = score.position
		score.position.x -= 8.0
		score.material.set_shader_parameter("optical_shift",0.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/clear-mark/alignment-before-%d.png" % value)
		score.position = origin
		score.refresh_style()
	page.queue_free()
	var result = load("res://scenes/screens/result_screen.tscn").instantiate()
	root.add_child(result)
	for kind in ["fc","ap"]:
		result.present(null,{"cleared":true,"full_combo":true,"all_perfect":kind=="ap","score":165467})
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/clear-mark/result-"+kind+".png")
	quit()

