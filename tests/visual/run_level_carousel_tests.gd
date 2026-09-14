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

func _run() -> void:
	var ui = load("res://scenes/ui/modals/level_choosing.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.selection_changed.connect(func(index: int, id: String): events.append([index, id]))
	_check(ui._cards.size() == ui.catalog.cards.size(), "卡片数量来自 catalog")
	_check(ui._cards[0].position + ui._cards[0].pivot_offset == Vector2(960, 540), "默认卡片位于中心")
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
		root.size = dimensions
		await process_frame
		await process_frame
		var card: Control = ui._cards[0]
		var center := card.get_global_transform() * card.pivot_offset
		_check(center.distance_to(Vector2(dimensions) * 0.5) < 1.0, "窗口变化后卡片仍在屏幕中心")
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
