extends SceneTree
## 直接调用正式摇杆绘制，放大两倍记录方向演示；不截取、重绘或替换产品图标。
class Glyph extends GrayboxFieldVisual:
	func _draw() -> void:
		_draw_rotation_cue()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "res://builds/controller-review/gesture-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var canvas := SubViewport.new()
	canvas.size = Vector2i(640, 400)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("211c29")
	bg.size = Vector2(640, 400)
	canvas.add_child(bg)
	var glyphs: Array[Glyph] = []
	for i in 4:
		var glyph := Glyph.new()
		canvas.add_child(glyph)
		glyph.set_process(false)
		glyph.prepare({"affinity": GameplayTypes.Affinity.ZHU if i < 2 else GameplayTypes.Affinity.XUAN, "start_value": 0.2, "end_value": 0.7, "duration_us": 12_000_000, "traversal_count": 1})
		glyph.set_slider_state({"required_rotation_sign": 1 if i % 2 == 0 else -1, "current_traversal_index": 0})
		glyph.set_preview_presentation(1, 0, 1.0)
		glyph.scale = Vector2(2, 2)
		var target := Vector2(160 + (i % 2) * 320, 110 + (i / 2) * 200)
		glyph.position = target - Vector2(glyph._stick_cue_pose()["center"]) * 2.0
		glyphs.append(glyph)
		var label := Label.new()
		label.text = ("右摇杆" if i < 2 else "左摇杆") + (" · 顺时针" if i % 2 == 0 else " · 逆时针")
		label.add_theme_font_override("font", load("res://assets/fonts/huiwen.otf"))
		label.add_theme_font_size_override("font_size", 20)
		label.position = Vector2(target.x - 120, target.y - 88)
		label.size.x = 240
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		canvas.add_child(label)
	for frame in 96:
		for glyph in glyphs:
			glyph.set_region_progress((float(frame) / 30.0) / 12.0)
		await process_frame
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(out + "/%03d.png" % frame)
	print("STICK GESTURE: 96 frames captured at 30 FPS, 2x display")
	quit()
