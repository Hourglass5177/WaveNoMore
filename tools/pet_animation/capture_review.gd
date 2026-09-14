extends SceneTree
## 审看动图直接采样正式 Spine 混合；背景对照使用现有写谱器预览装配。
const ACTOR := preload("res://src/presentation/pets/animated_pet_visual.gd")
const OUT := "res://build/pet-animation/"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("审看采样需要 Compatibility 图形渲染。")
		quit(1)
		return
	if "--stage" in OS.get_cmdline_user_args(): await _stage()
	elif "--ui" in OS.get_cmdline_user_args(): await _ui()
	elif "--baseline" in OS.get_cmdline_user_args(): await _baseline()
	else: await _movie()
	quit()

func _actor(parent: Node, id: String, at: Vector2, factor: float) -> Node2D:
	var actor = ACTOR.new()
	parent.add_child(actor)
	actor.setup(id)
	actor.position = at
	actor.scale = Vector2.ONE * factor
	return actor

func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func _save(viewport: SubViewport, path: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	viewport.get_texture().get_image().save_png(OUT + path)

func _movie() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "demo")
	var viewport := _viewport(Vector2i(840,960))
	var backdrop := ColorRect.new()
	backdrop.size = viewport.size
	backdrop.color = Color("a9a39e")
	viewport.add_child(backdrop)
	var actors: Array[Node2D] = []
	var ids := ["bat","snake","sheep"]
	for row in 3:
		for column in 3:
			var actor = _actor(viewport,ids[row],Vector2(140+280*column,175+320*row),2.1875)
			if column==1: actor.trigger(1.0)
			if column==2: actor.die(1.0)
			actors.append(actor)
			var label := Label.new()
			label.position = Vector2(16+280*column,8+320*row)
			label.text = str(actor.config.name) + " · " + ["常态","技能","死亡"][column]
			label.add_theme_color_override("font_color",Color("292531"))
			label.add_theme_font_size_override("font_size",19)
			viewport.add_child(label)
	for frame in 144:
		for actor in actors: actor.sample(float(frame)/30.0)
		await _save(viewport,"demo/%04d.png" % frame)
	viewport.queue_free()
	await process_frame
	print("Native mixed animation demo captured")

func _stage() -> void:
	var viewport := _viewport(Vector2i(1920,1080))
	var definition: StageDefinition = root.get_node("ContentCatalog").get_stage("s08").duplicate(true)
	for slot in definition.dependency_paths():
		definition.assign_dependency(slot,load(definition.dependency_paths()[slot]))
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new()
	root.add_child(preview)
	preview.sound_enabled = false
	if not preview.load_preview(definition,viewport):
		push_error("正式背景预览装配失败")
		quit(1)
		return
	await preview.seek_preview(0)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	viewport.add_child(overlay)
	var actors: Array[Node2D] = []
	for row in 2:
		for column in 3:
			var point := Vector2(260+240*column,350)
			if row==1: point = Vector2(1920,1080)-point
			var actor = _actor(overlay,["bat","snake","sheep"][column],point,1.0)
			actor.rotation = PI if row==1 else 0.0
			actors.append(actor)
	for size in [80,120]:
		for actor in actors: actor.scale = Vector2.ONE*float(size)/80.0
		for clip: String in ["idle","trigger","death"]:
			for actor in actors: actor.sample_clip(clip,.23 if clip=="trigger" else 1.2)
			await _save(viewport,"stage-%d-%s.png" % [size,clip])
	for actor in actors: actor.sample_clip("death",1.75)
	await _save(viewport,"stage-ashes.png")
	viewport.size = Vector2i(1280,720)
	overlay.scale = Vector2.ONE*(1280.0/1920.0)
	for actor in actors:
		actor.scale=Vector2.ONE
		actor.sample_clip("idle",.65)
	for i in 4: await process_frame
	await _save(viewport,"stage-1280.png")
	preview.clear_preview()
	preview.queue_free()
	viewport.queue_free()
	await process_frame
	print("Formal background: 80 px / 120 px, both worlds captured")

func _ui() -> void:
	var viewport := _viewport(Vector2i(1920,1080))
	var review = load("res://scenes/tools/pet_animation/review.tscn").instantiate()
	viewport.add_child(review)
	review.playing = false
	review._update_play_button()
	review.clock = .35
	for size in [Vector2i(1920,1080),Vector2i(1280,720)]:
		viewport.size = size
		for i in 4: await process_frame
		await _save(viewport,"review-%d.png" % size.x)
	viewport.queue_free()
	await process_frame
	print("Review UI captured at 1920 / 1280")

func _baseline() -> void:
	var viewport := _viewport(Vector2i(840,900))
	var backdrop := ColorRect.new()
	backdrop.size = viewport.size
	backdrop.color = Color("a9a39e")
	viewport.add_child(backdrop)
	for row in 3:
		var id: String = ["bat","snake","sheep"][row]
		var actor = _actor(viewport,id,Vector2(630,160+300*row),2.5)
		actor.sample_clip("idle",0)
		var original := Sprite2D.new()
		original.texture = load(ACTOR.FOLDER+id+"/original.png")
		original.position = Vector2(210,160+300*row)
		var anchor: Array = actor.config.source_anchor
		original.offset = original.texture.get_size()*.5-Vector2(anchor[0],anchor[1])
		original.scale = Vector2.ONE*float(actor.config.unit_scale)*2.5
		viewport.add_child(original)
		for column in 2:
			var label := Label.new()
			label.position = Vector2(16+420*column,8+300*row)
			label.text = str(actor.config.name)+" · "+["原画","骨骼基准"][column]
			label.add_theme_color_override("font_color",Color("292531"))
			label.add_theme_font_size_override("font_size",19)
			viewport.add_child(label)
	await _save(viewport,"source-comparison.png")
	viewport.queue_free()
	await process_frame
	print("Original art / rig baseline captured")
