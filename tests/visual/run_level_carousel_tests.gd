extends SceneTree
## 原生 UI 轮播的独立运行、交互与图形回归；截图写入 builds/level-carousel。
var failures := 0
var checks := 0
var events: Array = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _settle(ui: Control) -> void:
	for frame in 120:
		ui._process(1.0 / 120.0)
	_check(not ui._moving, "轮播须在限定时间内到位")
	for card: Control in ui._cards:
		_check(is_zero_approx(card.rotation) and is_equal_approx((card.position + card.pivot_offset).y, 540.0), "卡片不能旋转或上下移动")
		var material: ShaderMaterial = card.get_node("MonsterIcon").material
		var background_material: ShaderMaterial = card.get_node("Background").material
		_check(is_equal_approx(float(background_material.get_shader_parameter("k")), 1.0 if card == ui._cards[ui.current_index()] else 0.0), "到位时仅正前方卡片背景 k 为 1")
		_check(is_equal_approx(float(material.get_shader_parameter("image_transparency")), 1.0 if card == ui._cards[ui.current_index()] else 0.0), "到位时仅正前方卡片显示原图")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/level-carousel")
	var save = root.get_node("SaveService")
	var previous_results: Dictionary = save.data.get("stage_results",{}).duplicate(true)
	save.data["stage_results"] = {}
	var ui = load("res://scenes/ui/modals/level_choosing.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	var flame_card = ui._cards[0]
	flame_card.set_process(false)
	flame_card._effect_frame = 0
	flame_card._effect_elapsed = 0.0
	var frame_duration: float = flame_card._effect_frames.get_frame_duration(flame_card._effect_animation,0)/flame_card._effect_frames.get_animation_speed(flame_card._effect_animation)
	flame_card._process(frame_duration*3.4)
	_check(flame_card._effect_frame==3 and is_equal_approx(flame_card._effect_elapsed,frame_duration*0.4),"火框长帧补齐且保留余量")
	flame_card._process(frame_duration*0.7)
	_check(flame_card._effect_frame==4 and is_equal_approx(flame_card._effect_elapsed,frame_duration*0.1),"火框后续相位连续")
	_check(ui._cards[0].get_node("Score").text=="000000","无记录分数默认六位零")
	_check(ui._cards[0].get_node("Rating").text.is_empty(),"不以示例关卡名称冒充评级")
	_check(is_equal_approx(ui._cards[0].get_node("MonsterIcon").scale.x,1.40) and is_equal_approx(ui._cards[1].get_node("MonsterIcon").scale.x,1.0),"只放大蝙蝠")
	_check(not ui._cards[0].clip_contents,"翅膀可超出卡片边界")
	_check(ui._cards[0].get_node("Score").material != ui._cards[1].get_node("Score").material,"分数渐变范围逐卡片独立")
	await _capture_catalog("score-default")
	save.data.stage_results["tutorial2"]={"best_score":165467}
	ui.set_catalog(ui.catalog)
	_check(ui._cards[0].get_node("Score").text=="165467","显示关联关卡最高分")
	await _capture_catalog("score-record")
	save.data.stage_results=previous_results
	ui.selection_changed.connect(func(index: int, id: String): events.append([index, id]))
	_check(ui._cards.size() == ui.catalog.cards.size(), "卡片数量来自 catalog")
	_check(is_equal_approx(ui.horizontal_radius, 480.0), "默认 catalog 半径缩小为 480")
	var configured_catalog: Resource = ui.catalog.duplicate()
	configured_catalog.horizontal_radius = 420.0
	ui.set_catalog(configured_catalog)
	_check(is_equal_approx(ui.horizontal_radius, 420.0), "轮转半径从 catalog 读取")
	if ui._cards.size() > 1:
		var heading: TextureRect = ui.get_node("Design/Heading/HeadingText")
		var original_texture := heading.texture
		ui.step(1)
		_check(is_equal_approx(ui._heading_transparency, 1.0), "换页触发不能立即清零标题透明度")
		ui._process(0.02)
		_check(ui._heading_transparency > 0.0 and ui._heading_transparency < 1.0 and heading.texture == original_texture, "移动初期旧标题平滑淡出")
		ui.step(-1)
		_settle(ui)
		_check(heading.texture == original_texture and is_equal_approx(ui._heading_transparency, 1.0), "反向停稳后标题恢复且完成淡入")
	ui.set_catalog(load("res://content/level_cards/default_level_card_catalog.tres"))
	events.clear()
	_check(ui._cards[0].position + ui._cards[0].pivot_offset == Vector2(960, 540), "默认卡片位于中心")
	if ui._cards.size() > 1:
		var first: ShaderMaterial = ui._cards[0].get_node("MonsterIcon").material
		var second: ShaderMaterial = ui._cards[1].get_node("MonsterIcon").material
		_check(first != second and first.shader == second.shader, "独立材质共享 shader")
		var first_background: ShaderMaterial = ui._cards[0].get_node("Background").material
		var second_background: ShaderMaterial = ui._cards[1].get_node("Background").material
		_check(first_background != second_background and first_background.shader == second_background.shader, "背景独立材质共享 shader")
		ui._progress = 0.5
		ui._layout_cards()
		_check(is_equal_approx(float(first_background.get_shader_parameter("k")), 0.5) and is_equal_approx(float(second_background.get_shader_parameter("k")), 0.5), "半卡位背景 k 平滑混合")
		_check(is_equal_approx(float(first.get_shader_parameter("image_transparency")), 0.5) and is_equal_approx(float(second.get_shader_parameter("image_transparency")), 0.5), "半卡位切换平滑混合")
		ui._progress = 0.0
		ui._layout_cards()
	for index in 16:
		ui.get_node("Design/Right").pressed.emit()
		_settle(ui)
	_check(events.back()[0] == posmod(16, ui._levels.size()), "右移超过两圈后索引正确")
	for index in 16:
		ui.get_node("Design/Left").pressed.emit()
		_settle(ui)
	_check(events.back() == [0, "card_01"], "反向跨首尾回到起点")
	ui.step(1)
	ui._process(0.07)
	var progress: float = ui._progress
	var velocity: float = ui._velocity
	ui.step(1)
	ui.step(-1)
	_check(ui._progress == progress and ui._velocity == velocity, "输入不重置进度或速度")
	_settle(ui)
	_check(events.back() == [1, "card_02"], "快速连点目标正确")
	ui.step(1)
	ui._process(0.05)
	ui.step(-1)
	ui.step(-1)
	_settle(ui)
	_check(events.back() == [0, "card_01"], "运动中反向目标正确")
	var levels: Array[Dictionary] = []
	ui.set_levels(levels)
	_check(ui.get_node("Design/Empty").visible and ui.get_node("Design/Left").disabled, "空列表提示和按钮状态")
	levels.append({"id": "one", "title": "单张关卡"})
	ui.set_levels(levels)
	ui.step(1)
	_check(not ui._moving and ui._cards.size() == 1 and ui.get_node("Design/Right").disabled, "单张不启动轮播")
	levels.append({"id": "two", "title": "第二关"})
	ui.set_levels(levels)
	ui.step(-1)
	_settle(ui)
	_check(events.back() == [1, "two"], "两张卡片可循环")
	for index in range(2, 7):
		levels.append({"id": str(index), "title": "示例关卡 %02d" % (index + 1)})
	ui.set_levels(levels)
	ui.step(1)
	ui._process(0.04)
	ui.set_levels(levels, -1)
	_check(not ui._moving and ui._target == 6, "替换列表取消动画并归一化初始索引")
	ui.set_levels(levels)
	DirAccess.make_dir_recursive_absolute("res://builds/level-carousel")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1000, 800)]:
		root.content_scale_size = Vector2i.ZERO
		root.content_scale_factor = 1.0
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = dimensions
		await process_frame
		await process_frame
		var card: Control = ui._cards[0]
		var center := card.get_global_transform() * card.pivot_offset
		var expected_center: Vector2 = Vector2(dimensions)*0.5 + ui.get_node("Design/Cards").position*ui.get_node("Design").scale
		_check(center.distance_to(expected_center) < 1.0, "窗口变化后卡片保留原稿向下 69 px 的构图")
		var backdrop: Control = ui.get_node("Design/TextureRect")
		_check(backdrop.get_global_rect().get_center().distance_to(Vector2(dimensions)*0.5)<1.0,"背景与设计画布一起缩放居中")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			_check(img.save_png("res://builds/level-carousel/%dx%d.png" % [dimensions.x, dimensions.y]) == OK, "保存图形检查截图")
	ui.step(1)
	ui.set_process(false)
	ui._process(0.035)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/level-carousel/moving.png")
	ui.queue_free()
	await process_frame
	print("Level carousel: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _capture_catalog(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/level-carousel/"+name+".png")
