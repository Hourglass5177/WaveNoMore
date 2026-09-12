extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)


func _run() -> void:
	var theme := StageVisualTheme.new()
	check(theme.zhu_tap_glow_enabled and theme.xuan_tap_glow_enabled, "Tap glow defaults enabled")
	check(theme.zhu_hold_glow_enabled and theme.xuan_hold_glow_enabled, "Hold glow defaults enabled")

	var host := NoteVisualHost.new()
	host.visual_theme = theme
	var tap_shader := load("res://shaders/materials/tap_eye.gdshader") as Shader
	var first_tap := GrayboxNoteVisual.new()
	first_tap.tap_material = ShaderMaterial.new()
	first_tap.tap_material.shader = tap_shader
	first_tap.material = first_tap.tap_material
	var second_tap := GrayboxNoteVisual.new()
	second_tap.tap_material = first_tap.tap_material.duplicate(false)
	second_tap.material = second_tap.tap_material
	host._apply_edge_glow(first_tap, {"affinity": GameplayTypes.Affinity.ZHU, "unit_kind": &"tap"})
	host._apply_edge_glow(second_tap, {"affinity": GameplayTypes.Affinity.XUAN, "unit_kind": &"tap"})
	check(first_tap.material != second_tap.material, "Tap glow materials remain per-instance")
	check(first_tap.tap_material.get_shader_parameter(&"glow_color") == theme.zhu_tap_glow_color, "Zhu Tap receives theme glow")
	check(second_tap.tap_material.get_shader_parameter(&"glow_color") == theme.xuan_tap_glow_color, "Xuan Tap receives theme glow")

	var hold := GrayboxHoldVisual.new()
	host._apply_edge_glow(hold, {"affinity": GameplayTypes.Affinity.ZHU, "unit_kind": &"hold"})
	check(hold._edge_head_glow != null and hold._edge_body_glow != null, "Hold creates head and body edge passes")
	check(hold._edge_head_glow.material != hold._edge_body_glow.material, "Hold edge passes have independent materials")
	var head_material := hold._edge_head_glow.material as ShaderMaterial
	check(head_material.get_shader_parameter(&"glow_color") == theme.zhu_hold_glow_color, "Zhu Hold receives theme glow")
	hold._edge_body_glow.body(PackedVector2Array([Vector2.ZERO, Vector2(-80.0, 0.0)]), PackedFloat32Array([20.0, 0.0]))
	hold.prepare({"event_id": "pooled_hold", "unit_kind": &"hold", "start_us": 0, "end_us": 1_000_000})
	check(hold._edge_head_glow.mesh == null and hold._edge_body_glow.mesh == null, "Pooled Hold clears previous edge geometry")
	theme.xuan_hold_glow_enabled = false
	host._apply_edge_glow(hold, {"affinity": GameplayTypes.Affinity.XUAN, "unit_kind": &"hold"})
	check(not hold._edge_head_glow.visible and not hold._edge_body_glow.visible, "Pooled Hold refreshes disabled Xuan glow")
	check(head_material.get_shader_parameter(&"glow_color") == theme.xuan_hold_glow_color, "Pooled Hold refreshes Xuan color")
	if DisplayServer.get_name() != "headless":
		await _render_samples(theme, host)

	first_tap.free()
	second_tap.free()
	hold.free()
	host.free()
	print("NOTE EDGE GLOW TESTS: ", failures)
	quit(1 if failures else 0)


func _render_samples(theme: StageVisualTheme, host: NoteVisualHost) -> void:
	## Compatibility 渲染器下同时覆盖横屏、竖屏和 Hold 的动态尖尾网格。
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sample_root := Node2D.new()
	viewport.add_child(sample_root)

	var tap := GrayboxNoteVisual.new()
	sample_root.add_child(tap)
	tap.prepare({"event_id": "edge_tap", "affinity": GameplayTypes.Affinity.ZHU, "unit_kind": &"tap"})
	host._apply_edge_glow(tap, {"affinity": GameplayTypes.Affinity.ZHU, "unit_kind": &"tap"})

	var sample_hold := GrayboxHoldVisual.new()
	sample_root.add_child(sample_hold)
	sample_hold.prepare({"event_id": "edge_hold", "affinity": GameplayTypes.Affinity.XUAN, "unit_kind": &"hold", "start_us": 0, "end_us": 0})
	theme.xuan_hold_glow_enabled = true
	host._apply_edge_glow(sample_hold, {"affinity": GameplayTypes.Affinity.XUAN, "unit_kind": &"hold"})
	sample_hold.advance_body(1.0 / 60.0)

	DirAccess.make_dir_recursive_absolute("res://builds/visual-review/note-edge-glow")
	for dimensions: Vector2i in [Vector2i(640, 360), Vector2i(360, 640)]:
		viewport.size = dimensions
		tap.position = Vector2(dimensions) * Vector2(0.28, 0.32)
		sample_hold.position = Vector2(dimensions) * Vector2(0.72, 0.66)
		sample_hold.advance_body(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var visible_pixels := 0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.01:
					visible_pixels += 1
		check(visible_pixels > 500, "Edge glow renders in %s" % dimensions)
		image.save_png("res://builds/visual-review/note-edge-glow/glow-%dx%d.png" % [dimensions.x, dimensions.y])
	viewport.queue_free()
