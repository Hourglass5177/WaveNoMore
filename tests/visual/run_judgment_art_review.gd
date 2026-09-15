extends SceneTree
## 采样正式 HUD 材质，同时检查连续判定替换、等高、透明度与独立实例。
var failures := 0
const OUT := "res://builds/judgment-review"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		printerr(text)

func _run() -> void:
	var planning := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	check(planning.errors.is_empty(),"策划表完整可读取："+str(planning.errors))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := TextureRect.new()
	background.texture = load("res://assets/image/background/background-fire-deathbk.png")
	background.size = Vector2(1920,1080)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	viewport.add_child(background)
	var huds: Array = []
	for grade in 4:
		var hud = load("res://scenes/ui/hud/stage_hud.tscn").instantiate()
		viewport.add_child(hud)
		huds.append(hud)
		for child in hud.get_node("Root").get_children(): child.hide()
		hud._judgment_label.show()
		hud.judgment_textures.offset = Vector2(-540+grade*360,0)
		var record := JudgmentRecord.new()
		record.grade = grade
		hud._on_judgment_recorded(record)
		hud._judgment_tween.kill()
		hud._judgment_label.scale = Vector2.ONE*hud.judgment_textures.scale
		var glyph: Vector2 = hud._judgment_material.get_shader_parameter("glyph_size")
		check(is_equal_approx(glyph.y*hud.judgment_textures.scale,160.0),"四级可见字形等高")
		check(is_equal_approx(hud._judgment_label.modulate.a,0.7),"不透明度为 70%")
		if grade > 0: check(hud._judgment_material != huds[0]._judgment_material,"HUD 材质独立")
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"/grades-ingame.png")
	background.hide()
	viewport.transparent_bg = true
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(OUT+"/grades-transparent.png")
	var maximum := 0.0
	# 四张图没有叠放，最终画布的透明度也不能超过 70%。
	var bytes := image.get_data()
	for index in range(3,bytes.size(),4): maximum = maxf(maximum,float(bytes[index])/255.0)
	check(maximum <= 0.705 and maximum >= 0.69,"最终像素透明度上限")
	var record := JudgmentRecord.new()
	record.grade = GameplayTypes.JudgmentGrade.MISS
	huds[0]._on_judgment_recorded(record)
	await create_timer(0.7).timeout
	check(huds[0]._judgment_label.modulate.a < 0.001,"连续判定切换后字形和光效完全淡出")
	viewport.queue_free()
	print("JUDGMENT ART: ",failures," failures")
	quit(1 if failures else 0)
