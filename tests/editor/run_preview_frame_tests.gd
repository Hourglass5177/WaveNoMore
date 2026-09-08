extends SceneTree
## 重演仍运行真实 StageRoot，但让出的渲染帧只能看见上一张完整画面。
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var document := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document)
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,360); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# Autoload 就绪后加载正式预览脚本，与工作区的加载时机一致。
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	if not preview.load_preview(ChartProjectLoader.make_stage(document.song, document.chart()), viewport):
		check(false, "装入正式预览"); quit(1); return
	check(preview.stage_root.active_pet == null and preview.stage_root.gameplay_coordinator.simulation.pet_effect.hold_head_bonus_ms == 0, "内嵌预览使用无随从的原始判定")
	await preview.seek_preview(9_600_000)
	var digest: String = preview.stage_root.gameplay_coordinator.result_digest()
	var pixels := PackedByteArray()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		pixels = viewport.get_texture().get_image().get_data()
	preview.seek_preview(9_600_000)
	check(preview.rebuilding and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "历史重演让帧前先冻结预览纹理")
	var observed := 0; var stable := true
	while preview.rebuilding:
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		else: await process_frame
		if preview.rebuilding:
			observed += 1
			stable = stable and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
			if not pixels.is_empty() and observed <= 3: stable = stable and viewport.get_texture().get_image().get_data() == pixels
	check(observed > 0 and stable, "跨帧重演期间不显示历史调频画面")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and preview.get_preview_state().time_us == 9_600_000, "恢复完成后显示精确目标帧")
	check(preview.stage_root.gameplay_coordinator.result_digest() == digest, "冻结渲染不改变重演判定结果")
	preview.seek_preview(9_600_000)
	await preview.seek_preview(500_000)
	await process_frame; await process_frame
	check(not preview.rebuilding and preview.get_preview_state().time_us == 500_000 and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "后来的定位替换旧请求，旧协程不覆盖结果")
	preview.seek_preview(9_600_000)
	preview.set_suspended(true)
	var cursor: int = preview.get_preview_state().input_cursor
	for frame in 5: await process_frame
	check(preview.rebuilding and preview.get_preview_state().input_cursor == cursor, "后台休眠暂停尚未完成的历史重演")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and preview.stage_root.process_mode == Node.PROCESS_MODE_DISABLED, "后台不提交预览纹理且停止场景处理")
	preview.set_suspended(false)
	while preview.rebuilding: await process_frame
	check(preview.stage_root.gameplay_coordinator.result_digest() == digest and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "切回后继续定位，结果与从头重演一致")
	preview.set_suspended(true)
	preview.seek_preview(9_600_000)
	preview.seek_preview(500_000)
	for frame in 3: await process_frame
	preview.set_suspended(false)
	while preview.rebuilding: await process_frame
	await process_frame
	check(preview.get_preview_state().time_us == 500_000, "休眠期间新定位仍可取消旧请求")
	preview.set_suspended(true)
	preview.seek_preview(9_600_000); preview.clear_preview()
	await process_frame; await process_frame
	check(preview.stage_root == null and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "清空或换谱取消重演并解除冻结")
	check(preview.load_preview(ChartProjectLoader.make_stage(document.song, document.chart()), viewport), "后台允许装入新预览")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "后台换谱继续保持纹理休眠")
	preview.set_suspended(false)
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "切回新谱恢复原渲染模式")
	preview.queue_free(); viewport.queue_free(); await process_frame
	print("PREVIEW FRAME TESTS: ", failures); quit(1 if failures else 0)
