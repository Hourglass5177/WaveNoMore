extends SceneTree

## 直接以 --main-pack <导出 EXE> 运行，检查导出后的 UID 解析和真实背景像素。
## 参数依次为输出目录、可选 song.json；无谱面参数时使用内置 s08。
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1920, 1080)
	var options := OS.get_cmdline_user_args()
	var output := options[0] if not options.is_empty() else ProjectSettings.globalize_path("res://builds/background-fix")
	DirAccess.make_dir_recursive_absolute(output)
	# 合并后的四套背景共用裁切 shader；直接检查资源引用，覆盖重命名和新增背景。
	for path in ["res://content/backgrounds/s00_grave_background.tres", "res://content/backgrounds/s00_grave_background2.tres", "res://content/backgrounds/s02_grave2_background.tres", "res://content/backgrounds/s03_grave3_background.tres"]:
		audit_background(load(path))
	var stage: StageDefinition
	if options.size() > 1:
		var loaded := ChartProjectLoader.load_stage(options[1], "normal")
		check(loaded.errors.is_empty(), "谱面加载")
		if not loaded.errors.is_empty(): quit(1); return
		stage = loaded.stage
	else:
		stage = root.get_node("ContentCatalog").get_stage("s08").duplicate(true)
		for slot in stage.dependency_paths():
			stage.assign_dependency(slot, load(stage.dependency_paths()[slot]))
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview: Node
	# StageRoot 依赖自动加载输入服务，须等服务就绪后动态加载，不能在脚本入口预编译。
	var stage_root: Node
	var includes_studio := ProjectSettings.get_global_class_list().any(func(item): return item.class == "StudioPreviewInputs")
	if includes_studio:
		preview = load("res://src/tools/chart_studio/preview_session.gd").new()
		root.add_child(preview)
		preview.sound_enabled = false
		check(preview.load_preview(stage, viewport), "写谱器正式预览装配")
		if preview.stage_root == null: quit(1); return
		stage_root = preview.stage_root
		await preview.seek_preview(0)
	else:
		# 本体包不包含工具脚本，使用同一个 StageRoot 验证正式运行的背景装配。
		stage_root = load("res://scenes/stage/stage_root.tscn").instantiate()
		stage_root.initial_stage = null
		stage_root.auto_start_initial_stage = false
		viewport.add_child(stage_root)
		check(stage_root.load_stage(stage, false), "游戏正式场景装配")
	for size in [Vector2i(1920, 1080), Vector2i(960, 540)]:
		viewport.size = size
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var frame := viewport.get_texture().get_image()
		frame.save_png(output.path_join("preview-%d.png" % size.x))
		# 白底故障覆盖大半幅画面。分别检查两侧，避免一侧正常掩盖另一侧丢失。
		for half in 2:
			var white := 0
			var samples := 0
			for y in range(half * size.y / 2 + 8, (half + 1) * size.y / 2 - 8, 8):
				for x in range(8, size.x - 8, 8):
					var color := frame.get_pixel(x, y)
					if minf(color.r, minf(color.g, color.b)) > 0.94: white += 1
					samples += 1
			var ratio := float(white) / samples
			check(ratio < 0.05, "%d px 半屏 %d 白底占比 %.3f" % [size.x, half, ratio])
	if preview != null: preview.queue_free()
	viewport.queue_free()
	await process_frame
	print("BACKGROUND SHADER TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func audit_background(background: StageBackgroundDefinition) -> void:
	for layer in background.layers:
		for sublayer in layer.sublayers:
			for entry in sublayer.entries:
				if entry.material == null or entry.texture == null: continue
				var texture_path: String = entry.texture.resource_path
				if not texture_path.ends_with("-live.png") and not texture_path.ends_with("-death.png"): continue
				var side := "live" if texture_path.ends_with("-live.png") else "death"
				var expected := "res://shaders/materials/screen_half_material_split_%s.gdshader" % side
				check(entry.material.shader.resource_path == expected, texture_path.get_file() + " shader 引用 " + entry.material.shader.resource_path)
