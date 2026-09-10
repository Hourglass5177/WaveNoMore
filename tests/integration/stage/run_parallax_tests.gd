extends SceneTree
## 视差模块、真实关卡接线与可选像素检查；不启动真人输入或震动。

var failures := 0
var checks := 0
var _viewport: SubViewport

class CombinedBackdrop extends GrayboxBackdrop:
	func _draw() -> void:
		draw_background(self)
		super._draw()


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func texture(color: Color, size := Vector2i(16, 16)) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func sprite(color: Color, parent: Node, size := Vector2i(16, 16)) -> Sprite2D:
	var result := Sprite2D.new()
	result.texture = texture(color, size)
	result.centered = false
	parent.add_child(result)
	return result


func frames() -> SpriteFrames:
	var result := SpriteFrames.new()
	result.set_animation_speed(&"default", 2.0)
	result.add_frame(&"default", texture(Color.RED), 1.0)
	result.add_frame(&"default", texture(Color.BLUE), 2.0)
	return result


func run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(128, 96)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	await test_registry()
	await test_repeat()
	await test_animation()
	await test_rendering()
	await test_empty_background_rendering()
	await test_loading()
	await test_stage()
	_viewport.queue_free()
	await process_frame
	print("PARALLAX TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_registry() -> void:
	var parent := Node2D.new()
	parent.position = Vector2(15, 24)
	parent.rotation = 0.3
	parent.scale = Vector2(1.2, 0.8)
	_viewport.add_child(parent)
	var controller := ParallaxController.new()
	_viewport.add_child(controller)
	var objects: Array[Node2D] = []
	for depth in [0, 1, 2, -1, -2]:
		var object := Node2D.new()
		parent.add_child(object)
		object.position = Vector2(30, 40)
		object.rotation = -0.2
		object.scale = Vector2(2, 3)
		var before := object.get_global_transform_with_canvas()
		check(controller.register_object(object, depth), "注册深度 %d" % depth)
		check(object.get_global_transform_with_canvas().is_equal_approx(before), "注册保留变换 %d" % depth)
		objects.append(object)
		controller.move_camera(Vector2(80, -40))
		var expected := before
		if depth != 0: expected.origin -= Vector2(80, -40) / float(depth)
		check(object.get_global_transform_with_canvas().is_equal_approx(expected), "位移和不缩放 %d" % depth)
		controller.set_camera_position(Vector2.ZERO)
	check(controller._layers.size() == 5, "五种深度各建一层")
	var same := Node2D.new()
	parent.add_child(same)
	controller.register_object(same, 1)
	check(controller._layers.size() == 5 and controller._layers[1].get_child_count() == 2, "同深度复用")
	controller.register_object(same, 1)
	check(controller._layers[1].get_child_count() == 2, "重复注册不增对象")
	controller.move_camera(Vector2(13, 24))
	var pose := same.get_global_transform_with_canvas()
	controller.register_object(same, -2)
	check(same.get_global_transform_with_canvas().is_equal_approx(pose), "更新深度不跳变")
	controller.unregister_object(same)
	check(same.get_parent() == parent and same.get_global_transform_with_canvas().is_equal_approx(pose), "注销恢复原父级并保持当前变换")
	same.free()
	var deleted: Node2D = objects.pop_back()
	deleted.free()
	await process_frame
	await process_frame
	check(not controller._layers.has(-2), "外部删除回收空层")
	var moved: Node2D = objects.pop_back()
	moved.reparent(parent)
	await process_frame
	await process_frame
	check(not controller._layers.has(-1), "外部重挂自动注销")
	controller.clear()
	check(controller._layers.is_empty() and controller._objects.is_empty(), "清理全部外部对象与层")
	for object in objects:
		check(object.get_parent() == parent, "清理归还对象")
	var orphan := Node2D.new()
	var doomed := Node2D.new()
	_viewport.add_child(doomed)
	doomed.add_child(orphan)
	controller.register_object(orphan, 8)
	doomed.free()
	controller.unregister_object(orphan)
	check(orphan.get_parent() == null and is_instance_valid(orphan), "原父级销毁时交回对象")
	orphan.free()
	controller.queue_free()
	parent.queue_free()
	await process_frame


func test_repeat() -> void:
	var controller := ParallaxController.new()
	_viewport.add_child(controller)
	var object := sprite(Color.RED, _viewport)
	object.rotation = 0.4
	object.scale = Vector2(2, 0.75)
	object.position = Vector2(37, 21)
	var basis := object.global_transform
	check(controller.register_object(object, 2, true), "旋转缩放精灵注册拼接")
	controller.set_camera_position(Vector2(1000003, -987654))
	var record = controller._objects[object.get_instance_id()]
	check(record.view.repeat.repeat_size == Vector2(16, 16), "拼接按素材矩形")
	check(record.view.repeat.repeat_times > 1, "小素材自动覆盖视口")
	check(object.global_transform.x.is_equal_approx(basis.x) and object.global_transform.y.is_equal_approx(basis.y), "无限对象保持基底变换")
	check(absf(record.view.repeat.position.x) <= 16.01 and absf(record.view.repeat.position.y) <= 16.01, "大幅位移保持有界重复位置")
	var pose := object.get_global_transform_with_canvas()
	controller.unregister_object(object)
	check(object.get_global_transform_with_canvas().is_equal_approx(pose), "无限注销保留可见代表位置")
	object.free()
	var atlas := sprite(Color.GREEN, _viewport, Vector2i(32, 48))
	atlas.hframes = 2
	atlas.vframes = 3
	check(controller.register_object(atlas, 1, true), "图集精灵注册")
	check(controller._objects[atlas.get_instance_id()].view.repeat.repeat_size == Vector2(16, 16), "图集按单帧尺寸")
	controller.unregister_object(atlas)
	atlas.region_enabled = true
	atlas.region_rect = Rect2(0, 0, 20, 30)
	atlas.hframes = 1
	atlas.vframes = 1
	check(controller.register_object(atlas, 1, true), "区域纹理注册")
	check(controller._objects[atlas.get_instance_id()].view.repeat.repeat_size == Vector2(20, 30), "区域纹理尺寸")
	var other := sprite(Color.BLUE, _viewport, Vector2i(11, 13))
	controller.register_object(other, 1, true)
	check(controller._layers[1].get_child_count() == 2 and controller._objects[other.get_instance_id()].view.repeat.repeat_size == Vector2(11, 13), "同层独立重复尺寸")
	var finite := Node2D.new()
	_viewport.add_child(finite)
	controller.register_object(finite, 1, false)
	check(controller._layers[1].get_child_count() == 3, "同层混合有限与无限对象")
	check(not controller.register_object(finite, 1, true), "普通 Node2D 不伪造无限拼接")
	controller.clear()
	atlas.free()
	other.free()
	finite.free()
	controller.queue_free()
	await process_frame


func test_animation() -> void:
	var controller := ParallaxController.new()
	_viewport.add_child(controller)
	var definition := StageBackgroundDefinition.new()
	var entry := StageBackgroundEntry.new()
	entry.sprite_frames = frames()
	entry.infinite = true
	definition.entries.append(entry)
	check(controller.configure(definition).is_empty(), "配置多帧动画")
	var object: AnimatedSprite2D = controller._animations[0]
	controller.set_song_time(-2.0)
	check(object.frame == 0, "负时间首帧")
	controller.set_song_time(0.5)
	check(object.frame == 1 and is_zero_approx(object.frame_progress), "不等时长帧边界")
	controller.set_song_time(1.0)
	check(object.frame == 1 and is_equal_approx(object.frame_progress, 0.5), "帧时长采样")
	controller.set_song_time(1.5)
	check(object.frame == 0, "循环边界首帧")
	entry.sprite_frames.set_animation_loop(&"default", false)
	controller.set_song_time(50.0)
	check(object.frame == 1 and object.frame_progress == 1.0, "非循环停末帧")
	controller.set_song_time(0.2)
	check(object.frame == 0, "向后定位恢复")
	var external := AnimatedSprite2D.new()
	external.sprite_frames = frames()
	_viewport.add_child(external)
	external.set_frame_and_progress(1, 0.25)
	controller.register_object(external, -1, true)
	controller.set_song_time(0.0)
	check(external.frame == 1 and external.frame_progress == 0.25, "外部动画不受歌曲采样控制")
	var pose := external.get_global_transform_with_canvas()
	controller.unregister_object(external)
	check(external.frame == 1 and external.get_global_transform_with_canvas().is_equal_approx(pose), "注销保留动画帧")
	external.free()
	controller.clear()
	await process_frame
	check(not is_instance_valid(object), "换关销毁配置动画")
	controller.queue_free()
	await process_frame


func pixels() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func all_color(image: Image, expected: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if not image.get_pixel(x, y).is_equal_approx(expected): return false
	return true


func test_rendering() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP pixels: headless")
		return
	var controller := ParallaxController.new()
	_viewport.add_child(controller)
	var far := sprite(Color.RED, _viewport)
	controller.register_object(far, 9999999, true)
	check(all_color(await pixels(), Color.RED), "重复小图覆盖全屏")
	for camera in [Vector2(17, 23), Vector2(-901, 503), Vector2(1234567, -987654)]:
		controller.set_camera_position(camera)
		check(all_color(await pixels(), Color.RED), "双轴任意方向无缺口 %s" % camera)
	var near := sprite(Color.GREEN, _viewport)
	controller.register_object(near, 0, true)
	check(all_color(await pixels(), Color.GREEN), "0 深度覆盖远背景")
	var actor := sprite(Color.BLUE, _viewport, Vector2i(128, 96))
	actor.z_index = 50
	check(all_color(await pixels(), Color.BLUE), "非负深度位于全部玩法之后")
	var front := sprite(Color.YELLOW, _viewport)
	controller.register_object(front, -1, true)
	check(all_color(await pixels(), Color.YELLOW), "负深度覆盖高 Z 玩法")
	var nearer := sprite(Color.MAGENTA, _viewport)
	controller.register_object(nearer, -999999, true)
	check(all_color(await pixels(), Color.MAGENTA), "极小负深度在最前，无 Z 限幅")
	var same := sprite(Color.CYAN, _viewport)
	controller.register_object(same, -999999, true)
	check(all_color(await pixels(), Color.CYAN), "同深度后注册覆盖先注册")
	controller.unregister_object(same)
	same.free()
	var hud := CanvasLayer.new()
	hud.layer = 10
	_viewport.add_child(hud)
	sprite(Color.WHITE, hud, Vector2i(128, 96))
	check(all_color(await pixels(), Color.WHITE), "HUD 仍在前景之上")
	hud.free()
	controller.clear()
	for object in [far, near, front, nearer, actor]: object.free()
	var animated := AnimatedSprite2D.new()
	animated.sprite_frames = frames()
	animated.centered = false
	_viewport.add_child(animated)
	controller.register_object(animated, -1, true)
	check(all_color(await pixels(), Color.RED), "动画拼接首帧一致")
	animated.frame = 1
	check(all_color(await pixels(), Color.BLUE), "动画拼接全部同步换帧")
	controller.set_camera_position(Vector2(-135.5, 287.25))
	_viewport.size = Vector2i(179, 113)
	check(all_color(await pixels(), Color.BLUE), "视口变化后重复覆盖")
	controller.clear()
	animated.free()
	var rotated := sprite(Color.RED, _viewport)
	rotated.rotation = 0.6
	rotated.scale = Vector2(2.0, 0.7)
	controller.register_object(rotated, 1, true)
	controller.move_camera(Vector2(180.25, -37.4))
	check(all_color(await pixels(), Color.RED), "旋转非等比素材拼接覆盖")
	controller.clear()
	rotated.free()
	controller.queue_free()
	_viewport.size = Vector2i(128, 96)
	await process_frame


func test_empty_background_rendering() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var reference := CombinedBackdrop.new()
	reference.scale = Vector2(128.0 / 1920.0, 96.0 / 1080.0)
	reference.set_song_progress(0.4)
	reference.set_failed(true)
	_viewport.add_child(reference)
	var original := (await pixels()).get_data()
	reference.free()
	var backdrop := GrayboxBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.scale = Vector2(128.0 / 1920.0, 96.0 / 1080.0)
	backdrop.set_song_progress(0.4)
	backdrop.set_failed(true)
	_viewport.add_child(backdrop)
	var layer := CanvasLayer.new()
	layer.layer = -2
	layer.transform = backdrop.transform
	_viewport.add_child(layer)
	var base = load("res://src/presentation/parallax/stage_background_base.gd").new()
	base.backdrop_path = NodePath("../../Backdrop")
	layer.add_child(base)
	check((await pixels()).get_data() == original, "空配置拆分底图与玩法后逐像素一致")
	layer.free()
	backdrop.free()
	await process_frame


func test_loading() -> void:
	var stage: StageDefinition = load("res://content/stages/s01/stage_definition.tres").duplicate(true)
	check(stage.resolve_dependencies_sync(), "同步完整依赖")
	stage.background = null
	stage.background_resource_path = ""
	check(stage.dependencies_resolved(), "未配置背景允许加载")
	stage.background_resource_path = "res://content/stages/s01/stage_background.tres"
	check(not stage.dependencies_resolved() and stage.dependency_paths().has("background"), "显式路径不可静默忽略")
	check(not stage.assign_dependency("background", Resource.new()), "拒绝错误资源类型")
	var loader = load("res://src/app/stage_loading_screen.gd").new()
	root.add_child(loader)
	loader._stage = stage
	loader._begin_dependency_requests()
	for attempt in 300:
		loader._poll_dependencies()
		if loader._phase in [&"done", &"failed"]: break
		await process_frame
	check(loader._phase == &"done" and stage.background != null, "正式异步加载流程赋值背景")
	stage.background = null
	stage.background_resource_path = "res://content/stages/s01/stage_definition.tres"
	loader._begin_dependency_requests()
	for attempt in 300:
		loader._poll_dependencies()
		if loader._phase in [&"done", &"failed"]: break
		await process_frame
	check(loader._phase == &"failed", "显式错误背景沿用加载失败流程")
	loader.queue_free()
	await process_frame


func test_stage() -> void:
	var stage: StageDefinition
	for number in range(1, 9):
		stage = load("res://content/stages/s%02d/stage_definition.tres" % number).duplicate(true)
		check(stage.resolve_dependencies_sync(), "s%02d 含背景依赖加载" % number)
		check(stage.background != null and stage.background.entries.is_empty(), "s%02d 空背景" % number)
	var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
	_viewport.add_child(scene)
	scene.stage_session.external_preview = true
	scene.stage_session.pause_on_focus_loss = false
	var entry := StageBackgroundEntry.new()
	entry.sprite_frames = frames()
	stage.background = StageBackgroundDefinition.new()
	stage.background.entries.append(entry)
	check(scene.load_stage(stage, false), "真实关卡装配背景")
	var controller: ParallaxController = scene.get_parallax_controller()
	var sample := ClockSample.new()
	sample.song_time_sec = 0.75
	scene.stage_session.visual_frame_ready.emit(sample)
	check(controller._animations[0].frame == 1, "正式帧末歌曲时间采样")
	sample.song_time_sec = 0.0
	scene.stage_session.visual_frame_ready.emit(sample)
	check(controller._animations[0].frame == 0, "定位首帧恢复")
	controller.move_camera(Vector2(75, 13))
	check(scene.stage_session.start(), "真实会话起播")
	check(scene.stage_session.request_pause(), "真实会话暂停")
	check(scene.stage_session.seek_song_time(0.75), "暂停中定位")
	check(controller._animations[0].frame == 1, "暂停定位恢复背景帧")
	var progress: float = controller._animations[0].frame_progress
	await create_timer(0.1).timeout
	check(controller._animations[0].frame == 1 and controller._animations[0].frame_progress == progress, "暂停不累计背景动画时间")
	controller.move_camera(Vector2(75, 13))
	check(scene.stage_session.seek_song_time(0.0) and controller.get_camera_position() == Vector2(75, 13), "定位不推算摄像头")
	check(scene.retry(), "真实关卡重试")
	check(controller.get_camera_position() == Vector2.ZERO and controller._animations[0].frame == 0, "重试重置相机与动画")
	check(scene.load_stage(stage, false) and controller._animations.size() == 1 and controller._objects.size() == 1, "重装不重复背景")
	scene.teardown()
	check(controller._objects.is_empty(), "关卡卸载清理")
	scene.queue_free()
	await process_frame
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new()
	root.add_child(preview)
	check(preview.load_preview(stage, _viewport), "内嵌预览装配同一背景")
	controller = preview.stage_root.get_parallax_controller()
	await preview.seek_preview(roundi((preview.offset_sec + 0.75) * 1000000.0))
	check(controller._animations[0].frame == 1, "预览定位采样背景")
	preview.set_suspended(true)
	preview.advance(preview.offset_sec + 2.0, true)
	await process_frame
	check(controller._animations[0].frame == 1, "后台预览冻结背景")
	preview.set_suspended(false)
	await preview.seek_preview(roundi(preview.offset_sec * 1000000.0))
	check(controller._animations[0].frame == 0, "预览恢复后回拖首帧")
	preview.clear_preview()
	preview.queue_free()
	await process_frame
