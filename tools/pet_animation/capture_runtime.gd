extends "res://tests/integration/pets/run_pet_runtime_tests.gd"
## 正式场景采样：使用领域输入与伤害入口，图像由 Compatibility 实际绘制。
const OUT := "res://build/pet-runtime/"

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("此采样需要图形渲染")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	# 模拟正式窗口的 1920×1080 画布缩放；仅改变纹理尺寸会裁掉右下世界。
	vp.size_2d_override = Vector2i(1920, 1080)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	# 独立审看存档，不覆盖玩家的装备及解锁。
	var save = root.get_node("SaveService")
	save.configure_storage_paths("user://pet_capture.json", "user://pet_capture.tmp", "user://pet_capture.bak")
	save.data = save.default_data()
	for id in ["nu_tu_fu", "yi_huo_she", "gui_jin_yang"]: save.debug_grant_pet(id, false)
	save.equip_pet("yi_huo_she")
	var menu = load("res://scenes/ui/modals/pet_select_modal.tscn").instantiate()
	vp.add_child(menu)
	for i in 4: await process_frame
	RenderingServer.force_draw()
	vp.get_texture().get_image().save_png(OUT + "selection.png")
	menu.queue_free()
	await process_frame
	for id in ["nu_tu_fu", "yi_huo_she", "gui_jin_yang"]:
		var requested := OS.get_cmdline_user_args()
		if Array(requested).any(func(arg: String): return arg.begins_with("--pet=")) and not ("--pet=" + id) in requested: continue
		DirAccess.make_dir_recursive_absolute(OUT + id)
		var scene = make_stage(id, vp)
		var coordinator = scene.gameplay_coordinator
		var domain: GameplaySimulation = coordinator.simulation
		domain.rules.stray_input_damages = true
		var inputs: Array[SemanticInputSample] = []
		if id == "gui_jin_yang":
			inputs = [SemanticInputSample.create(500000, 0, K.LIFE_A_PRESSED), SemanticInputSample.create(520000, 1, K.LIFE_A_RELEASED), SemanticInputSample.create(700000, 2, K.DEATH_A_PRESSED), SemanticInputSample.create(720000, 3, K.DEATH_A_RELEASED)]
		else:
			inputs = [SemanticInputSample.create(1000000, 0, K.LIFE_A_PRESSED), SemanticInputSample.create(1040000, 1, K.DEATH_A_PRESSED), SemanticInputSample.create(1510000, 2, K.LIFE_A_RELEASED), SemanticInputSample.create(1510000, 3, K.DEATH_A_RELEASED)]
		var cursor := 0
		for frame in (0 if "--layout" in requested else 174):
			var time_us := roundi(float(frame) / 30.0 * 1000000)
			while cursor < inputs.size() and inputs[cursor].timestamp_us <= time_us:
				var input := inputs[cursor]
				scene.stage_session.advance_preview(input.timestamp_us, false)
				coordinator.accept_input(input)
				cursor += 1
			if frame == 90:
				# 模拟致命机制伤害，经现有协调层同时驱动主角与随从死亡。
				domain._apply_damage(DamageRecord.create("capture_fatal", "capture_fatal", time_us, 200, A.SU))
			scene.stage_session.advance_preview(time_us)
			await process_frame
			RenderingServer.force_draw()
			vp.get_texture().get_image().save_png(OUT + "%s/%04d.png" % [id, frame])
		# 同一关内装配缩到 1280，检查锚点与翻转随画布等比变化。
		scene.stage_session.reset_preview()
		scene.stage_session.advance_preview(400000)
		vp.size = Vector2i(1280,720)
		for i in 4: await process_frame
		RenderingServer.force_draw()
		vp.get_texture().get_image().save_png(OUT + "%s-1280.png" % id)
		# 小窗口也检查完整释放姿态，避免只验证静息布局而漏掉光晕边距。
		scene._queue_pet_trigger(500000,A.SU)
		scene.stage_session.publish_preview_state(1050000)
		await process_frame
		RenderingServer.force_draw()
		vp.get_texture().get_image().save_png(OUT + "%s-1280-trigger.png" % id)
		scene.queue_free(); await process_frame
		vp.size = Vector2i(1920,1080)
	vp.queue_free(); await process_frame
	print("PET RUNTIME CAPTURE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
