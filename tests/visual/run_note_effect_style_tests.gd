extends SceneTree

## 正式素材、独立碎片生命周期与实际 GPU 取样，不以截图代替状态断言。
var failures := 0
var checks := 0
const STYLE = preload("res://content/presentation/note_effect_style.tres")
const THEME = preload("res://content/stages/s08/stage_visual_theme.tres")
const OUTPUT := "res://builds/visual-review/note-effects"

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
	print("PASS " if value else "FAIL ", message)

func tap(parent: Node, side: int, at: Vector2) -> GrayboxNoteVisual:
	var item := GrayboxNoteVisual.new()
	item.tap_texture = THEME.zhu_tap_texture
	item.tap_material = THEME.zhu_tap_material.duplicate(false)
	parent.add_child(item)
	item.prepare({"event_id": str(at), "affinity": side, "unit_kind": &"tap", "double_tap": true})
	item.position = at
	item.set_approach_progress(1.0)
	item.set_note_glow_time(0.0, 1.0)
	return item

func hold(parent: Node, side: int, at: Vector2) -> GrayboxHoldVisual:
	var item := GrayboxHoldVisual.new()
	item.head_texture = THEME.zhu_hold_head_texture
	item.body_texture = load("res://assets/image/note/hold_body.png")
	parent.add_child(item)
	item.prepare({"event_id": str(at), "affinity": side, "unit_kind": &"hold", "start_us": 0, "end_us": 3000000})
	item.position = at
	item.set_body_target(220)
	item.advance_body(0.0)
	return item

func run() -> void:
	var a := tap(root, 0, Vector2(200, 150))
	var b := tap(root, 1, Vector2(500, 150))
	check(a.effect_style == b.effect_style and a.effect_style == STYLE, "两侧使用同一全局设计资源")
	check(a.material != b.material, "贴图参数属于各自实例")
	check(a.tap_material.get_shader_parameter(&"life_tint") and not b.tap_material.get_shader_parameter(&"life_tint"), "仅生侧重映射底色")
	a.set_note_glow_time(0.5, 0.5)
	check(float(a.tap_material.get_shader_parameter(&"condition_light")) > 0.0, "条件白光进入正式贴图本体")
	a.play_timing_confirmed(GameplayTypes.JudgmentGrade.PERFECT)
	check(not a._aura.visible and is_equal_approx(a.tap_material.get_shader_parameter(&"body_brightness"), 0.45), "命中后熄灭阵营光并保留 45% 本体")
	a.play_wave_contact({"contact_us": 600000, "position": a.position})
	a.set_note_glow_time(0.65, 0.0)
	check(not a.visible and a._standalone_effects._active.has(a.event_id + ":break"), "ArtLab 独立实例也播放裂解")
	var effects := NoteFragmentHost.new(); root.add_child(effects)
	var source := b.effect_snapshot()
	effects.burst("one", source, 1.0, Vector2.RIGHT)
	effects.set_time(1.12)
	var fragment: MeshInstance2D = effects._active.one.node
	var mesh := fragment.mesh
	var transform := fragment.transform
	effects.burst("one", source, 1.0, Vector2.RIGHT)
	check(effects._active.size() == 1, "重复事件不会重播裂解")
	b.reset_for_pool()
	check(fragment.visible and fragment.transform == transform, "音符回收不截断、不移动碎片")
	effects.set_time(1.12)
	check(is_equal_approx(fragment.material.get_shader_parameter(&"age"), 0.12), "重复时钟保持粒子年龄")
	effects.set_time(1.35)
	check(effects._active.is_empty() and not fragment.visible, "光尘结束回到对象池")
	effects.burst("two", source, 2.0, Vector2.LEFT)
	check(effects._active.two.node.mesh == mesh, "第二次裂解复用网格模板")
	effects.clear()
	check(effects._active.is_empty(), "重试和定位清理旧特效")
	var sustain := hold(root, 0, Vector2(600, 400))
	sustain.set_tuning_glow(true, 0.0); sustain.set_tuning_glow(true, 0.1)
	check(is_equal_approx(sustain._runtime_body_material.get_shader_parameter(&"condition_light"), 1.0), "Hold 身体与头部共用白光强度")
	sustain.emit_consumption(0.0, 0.1, 0.1)
	var count := sustain._standalone_effects._active.size()
	sustain.emit_consumption(0.1, 0.1, 0.1)
	check(sustain._standalone_effects._active.size() == count, "固定消耗进度不重复发射细屑")
	sustain.play_hold_finished(0.2); sustain.play_hold_finished(0.2)
	check(not sustain.visible and sustain._standalone_effects._active.has(sustain.event_id + ":finish"), "Hold 结束一次裂解并隐藏完整头部")
	a.free(); b.free(); sustain.free(); effects.free()
	var art_result: Dictionary = load("res://tests/integration/art/test_art_manifest_contract.gd").new().run()
	check(art_result.ok, "ArtLab 清单、实际场景与状态接口检查通过")
	var manifest := load("res://content/visual/graybox_manifest.tres") as VisualAssetManifest
	var canvas := MingheArtLabCanvas.new(); canvas.size = Vector2(800, 600); root.add_child(canvas)
	for entry: VisualAssetEntry in manifest.entries:
		if entry.asset_id not in ["note_zhu", "note_xuan", "note_hold"]: continue
		check(canvas.set_manifest_entry(entry), "ArtLab 装入正式音符 " + entry.asset_id)
		var sample = canvas.get_preview_instance()
		canvas.apply_state(&"perfect")
		sample.art_lab_set_progress(0.0); sample.art_lab_set_progress(0.12); sample.art_lab_set_progress(0.25)
		check(not sample._notes[0].visible and sample._notes[0]._standalone_effects._active.size() > 0, "ArtLab 完整播放命中与裂解 " + entry.asset_id)
	canvas.free()
	if DisplayServer.get_name() != "headless": await render_samples()
	print("NOTE EFFECT STYLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func label(parent: Node, caption: String, at: Vector2, size := 24) -> void:
	var item := Label.new(); item.text = caption; item.position = at
	item.add_theme_font_size_override("font_size", size); parent.add_child(item)

func render_samples() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node2D.new(); viewport.add_child(stage)
	for side: int in 2:
		var background := ColorRect.new()
		background.position = Vector2(0, side * 500)
		background.size = Vector2(1600, 500)
		background.color = Color("12282a") if side == 0 else Color("713e35")
		stage.add_child(background)
		label(stage, "生 · 赭红漆色" if side == 0 else "死 · 青黑柔光", Vector2(30, side * 500 + 20), 30)
		for i: int in 6:
			var x := 160.0 + i * 250.0
			var y := 200.0 + side * 500
			label(stage, ["常态", "双押", "命中后", "裂解 0.06 s", "裂解 0.14 s", "裂解 0.26 s"][i], Vector2(x - 70, y - 122), 20)
			var note := tap(stage, side, Vector2(x, y))
			if i == 1: note.set_note_glow_time(0.6, 0.0)
			if i >= 2:
				note.set_note_glow_time(1, 0); note.play_timing_confirmed(GameplayTypes.JudgmentGrade.PERFECT)
				note.set_note_glow_time(1.1, 0)
			if i >= 3:
				note.play_wave_contact({"contact_us": 1100000, "position": note.position})
				note.set_note_glow_time(1.1 + [0.06, 0.14, 0.26][i - 3], 0)
		var quiet := hold(stage, side, Vector2(430, 365 + side * 500))
		label(stage, "Hold", Vector2(180, 265 + side * 500), 20)
		var controlled := hold(stage, side, Vector2(925, 365 + side * 500))
		controlled.set_tuning_glow(true, 0); controlled.set_tuning_glow(true, 0.1)
		label(stage, "调频接管", Vector2(660, 265 + side * 500), 20)
		var finished := hold(stage, side, Vector2(1340, 365 + side * 500))
		finished.play_hold_finished(1.0); finished.set_preview_time(1.10)
		label(stage, "结束裂解", Vector2(1220, 265 + side * 500), 20)
		quiet.set_preview_time(1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	screenshot.save_png(OUTPUT + "/palette-and-fracture.png")
	check(screenshot.get_pixel(160, 200) != Color("12282a"), "Compatibility 实际绘制正式素材")
	viewport.queue_free()
