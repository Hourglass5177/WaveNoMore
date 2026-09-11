extends SceneTree
## 同一场景贯穿正式装配、编辑历史、交付与定位；临时资源验证刷新确实越过深层缓存。
var failures := 0
var checks := 0
const RULES = preload("res://content/rules/default_gameplay_rules.tres")
const FIXTURE := "res://tests/editor/fixtures/training/song.json"
var output := "user://chart_studio/tests/scenes_%d" % Time.get_ticks_usec()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func settle() -> void:
	for i in 4: await process_frame
func presentation(doc: StudioDocument) -> Dictionary:
	return doc.chart().get_meta("json_source", {}).get("presentation", {})

func run() -> void:
	var library := ChartSceneLibrary.shared()
	var ids := library.scene_ids()
	check(ids.has("s08"), "目录自动提供 s08")
	check(library.all_stages().map(func(s): return s.stage_id) == root.get_node("ContentCatalog").all_stages().map(func(s): return s.stage_id), "游戏目录与写谱器发现和排序一致")
	var doc := StudioDocument.new(); doc.new_project()
	check(presentation(doc) == {"scene_id": "s02", "use_scene_show": false}, "新谱默认 s02，演出关闭")
	StudioProjectIO.open_project(FIXTURE, doc)
	var legacy := ChartProjectLoader.make_stage(doc.song, doc.chart())
	check(legacy.background == null and legacy.stage_show.cues.is_empty() and not presentation(doc).has("scene_id"), "旧谱仍只加载原主题，不隐式迁移")
	var before: CompiledChart = ChartCompiler.compile(legacy.chart, RULES).compiled
	doc.change_presentation({"scene_id": "s08", "use_scene_show": false, "palette_overrides": {"life": "#123456"}})
	var stage := ChartProjectLoader.make_stage(doc.song, doc.chart())
	var source := library.resolve(presentation(doc))
	check(stage.background != null and stage.background.layers.size() == source.background.layers.size(), "装配 s08 全部背景层")
	check(stage.visual_theme.zhu_tap_texture != null and stage.visual_theme.zhu_hold_head_texture != null, "装入正式 Tap 与 Hold 素材")
	check(stage.stage_show.cues.is_empty(), "选择场景不自动带入教学演出")
	check(stage.song.song_id == doc.song.song_id and stage.chart.chart_id == doc.chart().chart_id and stage.rule_set == RULES, "场景选择保留当前音乐、谱面与规则")
	check(stage.visual_theme.life_color == Color("123456") and source.theme.life_color != Color("123456"), "配色仅覆盖会话副本")
	var velocity: Vector2 = source.background.layers[0].sublayers[0].velocity
	stage.background.layers[0].sublayers[0].velocity += Vector2(10, 20)
	check(source.background.layers[0].sublayers[0].velocity == velocity, "背景运行副本不修改源资源")
	var after: CompiledChart = ChartCompiler.compile(stage.chart, RULES).compiled
	var replay := ReplayData.new(); replay.inputs = StudioPreviewInputs.build(before, RULES)
	check(before.content_hash == after.content_hash and ReplayRunner.run(before, RULES, replay).digest == ReplayRunner.run(after, RULES, replay).digest, "场景与配色不改变 Replay 哈希和判定结果")
	doc.undo(); check(not presentation(doc).has("scene_id"), "撤销场景选择恢复旧主题")
	doc.undo(true); check(presentation(doc).scene_id == "s08", "重做恢复场景")
	doc.add_difficulty("copy", true)
	check(presentation(doc).scene_id == "s08" and not presentation(doc).use_scene_show, "复制难度保留场景配置")
	var raw := presentation(doc).duplicate(true); raw.use_scene_show = true; doc.change_presentation(raw)
	doc.current = 0
	check(not presentation(doc).use_scene_show, "演出开关只修改当前难度")
	check(StudioProjectIO.save_project(doc, output.path_join("project")).is_empty(), "保存多难度场景项目")
	var reopened := StudioDocument.new()
	check(StudioProjectIO.open_project(output.path_join("project/song.json"), reopened).is_empty() and presentation(reopened).scene_id == "s08", "重开保留场景与配色")
	var zip := output.path_join("chart.zip")
	check(StudioProjectIO.export_zip(doc, zip).is_empty(), "含场景引用的可玩 ZIP")
	var reader := ZIPReader.new(); reader.open(zip)
	check(reader.file_exists("charts/normal.json") and reader.file_exists("charts/copy.json") and reader.file_exists("song.json") and reader.file_exists("audio/song.wav") and not Array(reader.get_files()).any(func(p): return p.ends_with(".tres") or p.ends_with(".tscn")), "交付只包含两张谱、清单与音频")
	reader.close()
	var loaded := ChartProjectLoader.load_stage(zip, "copy")
	check(loaded.errors.is_empty() and loaded.stage.stage_show.cues.size() > 0 and loaded.stage.background != null, "游戏 ZIP 入口采用同一场景和演出开关")
	var migrated := StudioDocument.new()
	check(StudioProjectIO.import_legacy("res://content/stages/s02/stage_definition.tres", output.path_join("migrated"), migrated).is_empty() and presentation(migrated).scene_id == "s02" and not presentation(migrated).use_scene_show, "旧关卡导入关联已登记场景，演出关闭")
	var invalid := ChartJsonCodec.encode_chart(doc.chart()); invalid.presentation.scene_id = 123
	check(ChartJsonCodec.decode_chart(invalid).chart == null, "场景 ID 类型错误有明确解析结果")
	doc.change_presentation({"scene_id": "missing_scene", "use_scene_show": false})
	check(StudioProjectIO.save_project(doc).is_empty() and not StudioProjectIO.export_zip(doc, output.path_join("invalid.zip")).is_empty(), "缺失场景可保存草稿，但不能交付可玩包")
	await jobs_test(zip)
	await package_worker_test(reopened)
	await preview_test(reopened)
	refresh_test()
	await ui_test()
	print("SCENE BINDING TESTS: %d (%d checks)" % [failures, checks])
	quit(1 if failures else 0)

func jobs_test(zip: String) -> void:
	var jobs := ChartReadJobs.new(); root.add_child(jobs)
	jobs.request(zip, "copy")
	var result: Array = await jobs.completed
	check(result[1].errors.is_empty() and result[1].stage.background != null and result[1].stage.stage_show.cues.size() > 0, "后台使用 ID 快照读谱，主线程装配完整场景")
	jobs.request(zip, "", true)
	result = await jobs.completed
	check(result[1].errors.is_empty() and result[1].charts.size() == 2, "后台全难度检查支持场景引用")
	jobs.queue_free(); await settle()

func background_position(preview) -> Vector2:
	return preview.stage_root.get_parallax_controller().get_configured_object(0).get_global_transform_with_canvas().origin

func package_worker_test(doc: StudioDocument) -> void:
	# 与一键试玩使用相同的冻结快照和主线程检查，验证后台打包后仍能装配所选场景。
	var song := doc.song.duplicate(true) as SongDefinition
	var charts: Array[SongChart] = [doc.chart().duplicate(true)]
	var issues := {charts[0].chart_id: ChartProjectLoader.check_chart(charts[0])}
	var result := {"error": ""}
	var path := output.path_join("worker.zip")
	var task := WorkerThreadPool.add_task(func():
		result.error = ChartPackageWriter.write(song, charts, doc.directory, path, issues))
	while not WorkerThreadPool.is_task_completed(task): await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var loaded := ChartProjectLoader.load_stage(path)
	check(result.error.is_empty() and loaded.errors.is_empty() and loaded.stage.background != null, "一键试玩的后台快照打包保留场景引用")

func preview_test(doc: StudioDocument) -> void:
	doc.current = 1
	var stage := ChartProjectLoader.make_stage(doc.song, doc.chart())
	var view := SubViewport.new(); view.size = Vector2i(960, 540); root.add_child(view)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	check(preview.load_preview(stage, view), "s08 场景装入正式 StageRoot 预览")
	var presentation = preview.stage_root.presentation
	check(stage.stage_id != "s08" and presentation._parallax_actors.size() == 2 and presentation._life_actor.is_class("SpineSprite"), "自制谱 ID 装入灵均，并按主题配置挂入角色子层")
	presentation.handheld_camera_enabled = false
	stage.visual_theme.camera_velocity = Vector2(60, -10)
	var director = preview.stage_root.stage_show_director
	var expected: TempoMap = preview.stage_root.stage_session.compiled_chart.tempo_map
	check(director.get_compiled_cues().all(func(c): return c.start_us == expected.tick_to_us(c.tick)), "原演出拍点按当前谱面的变 BPM 时间表计算")
	await preview.seek_preview(4_200_000); await settle()
	var pose: Vector2 = background_position(preview)
	var cues: Array = director.get_active_cues()
	var digest: String = preview.stage_root.gameplay_coordinator.result_digest()
	var actor_pose := actor_state(presentation)
	check(preview.stage_root.get_parallax_controller().get_camera_position().is_equal_approx(Vector2(60, -10) * 2.2), "自制谱按主题速度与当前歌曲时间移动镜头")
	await create_timer(0.1).timeout
	check(actor_state(presentation) == actor_pose, "暂停预览不会继续推进真实 Spine 动画")
	await preview.seek_preview(2_000_000); preview.advance(4.2, false); await settle()
	check(actor_state(presentation) == actor_pose, "真实角色的直接定位与回拖后推进相位一致")
	check(background_position(preview).is_equal_approx(pose), "背景运动的直接定位与回拖后推进一致")
	check(director.get_active_cues() == cues and preview.stage_root.gameplay_coordinator.result_digest() == digest, "演出与判定在循环回放后恢复相同状态")
	var layer: StageBackgroundLayer = stage.background.layers[0]
	var sublayer: StageBackgroundSubLayer = layer.sublayers[0]
	check(preview.stage_root.get_parallax_controller().get_sublayer_velocity(layer.depth, sublayer.sublayer_id) == sublayer.velocity, "预览读取正式背景运动参数")
	await preview.seek_preview(0)
	check(presentation._life_actor.get_animation_state().get_num_tracks() == 0 and presentation._death_actor.get_animation_state().get_num_tracks() == 0, "回到首个输入前清除旧角色轨道")
	await preview.seek_preview(4_200_000)
	check(actor_state(presentation) == actor_pose, "从无轨道初态重新定位仍恢复相同角色相位")
	preview.clear_preview(); preview.queue_free(); view.queue_free(); await settle()

func actor_state(presentation) -> Array:
	var values := []
	for actor in [presentation._life_actor, presentation._death_actor]:
		var state = actor.get_animation_state()
		var track = state.get_track(0) if state.get_num_tracks() > 0 else null
		# 微秒采样允许浮点误差；观察真实轨道及动画状态，避免只检查我们自己的控制变量。
		values.append([roundi(track.get_track_time() * 1000000.0), track.get_loop()] if track != null else [])
	return values

func write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(value)

func write_fixture(folder: String, value: int) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var texture := GradientTexture2D.new(); texture.width = value; texture.height = 8; texture.gradient = Gradient.new()
	ResourceSaver.save(texture, folder.path_join("texture.tres"))
	var shader := Shader.new(); shader.code = "shader_type canvas_item; uniform float amount = 0.5; void fragment(){ COLOR *= amount; }"
	ResourceSaver.save(shader, folder.path_join("effect.gdshader"))
	var material := ShaderMaterial.new(); material.shader = shader; material.set_shader_parameter("amount", value / 100.0)
	ResourceSaver.save(material, folder.path_join("material.tres"))
	# 显式外部引用模拟 Godot 保存后的多层 .tscn，避免临时内存资源被 Saver 内嵌。
	write_text(folder.path_join("material.tres"), """[gd_resource type="ShaderMaterial" load_steps=2 format=3]
[ext_resource type="Shader" path="%s/effect.gdshader" id="1"]
[resource]
shader = ExtResource("1")
shader_parameter/amount = %s
""" % [folder, value / 100.0])
	write_text(folder.path_join("inner.tscn"), """[gd_scene load_steps=3 format=3]
[ext_resource type="Texture2D" path="%s/texture.tres" id="1"]
[ext_resource type="Material" path="%s/material.tres" id="2"]
[node name="Inner" type="Node2D"]
position = Vector2(%d, 0)
[node name="Art" type="Sprite2D" parent="."]
texture = ExtResource("1")
material = ExtResource("2")
""" % [folder, folder, value])
	if value == 16:
		write_text(folder.path_join("outer.tscn"), """[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="%s/inner.tscn" id="1"]
[node name="Outer" type="Node2D"]
[node name="Inner" parent="." instance=ExtResource("1")]
""" % folder)
		write_text(folder.path_join("theme.tres"), """[gd_resource type="Resource" script_class="StageVisualTheme" load_steps=3 format=3]
[ext_resource type="Script" path="res://src/content/resources/stage_visual_theme.gd" id="1"]
[ext_resource type="PackedScene" path="%s/outer.tscn" id="2"]
[resource]
script = ExtResource("1")
life_world_scene = ExtResource("2")
""" % folder)
	var entry := StageBackgroundEntry.new(); entry.texture = texture; entry.material = material
	var sublayer := StageBackgroundSubLayer.new(); sublayer.entries.assign([entry]); sublayer.velocity = Vector2(value, 0)
	var layer := StageBackgroundLayer.new(); layer.sublayers.assign([sublayer])
	var background := StageBackgroundDefinition.new(); background.layers.assign([layer])
	ResourceSaver.save(background, folder.path_join("background.tres"))
	var stage := StageDefinition.new(); stage.stage_id = "fixture"; stage.display_name = "场景 %d" % value
	stage.visual_theme_resource_path = folder.path_join("theme.tres")
	stage.background_resource_path = folder.path_join("background.tres")
	ResourceSaver.save(stage, folder.path_join("stage_definition.tres"))

func nested_state(theme: StageVisualTheme) -> Array:
	var world := theme.life_world_scene.instantiate()
	var sprite: Sprite2D = world.get_node("Inner/Art")
	var state := [world.get_node("Inner").position.x, sprite.texture.get_width(), sprite.material.get_shader_parameter("amount")]
	world.free()
	return state

func refresh_test() -> void:
	var stages_root := output.path_join("stages")
	var folder := stages_root.path_join("first")
	write_fixture(folder, 16)
	var catalog := ContentCatalogData.new()
	var catalog_path := output.path_join("catalog.tres")
	ResourceSaver.save(catalog, catalog_path)
	var library := ChartSceneLibrary.new(catalog_path, stages_root)
	var raw := {"scene_id": "fixture", "use_scene_show": false}
	var original := library.resolve(raw)
	check(original.errors.is_empty() and nested_state(original.theme) == [16.0, 16, 0.16], "临时场景加载嵌套场景、材质和纹理")
	check(library.resolve(raw).theme == original.theme, "普通编辑复用场景资源缓存")
	write_fixture(folder, 32)
	check(nested_state(library.resolve(raw).theme) == [16.0, 16, 0.16], "保存源资源后保持原会话，等待显式刷新")
	library.refresh()
	var refreshed := library.resolve(raw)
	check(refreshed.errors.is_empty() and nested_state(refreshed.theme) == [32.0, 32, 0.32], "刷新重新读取深层场景、材质及纹理")
	check(refreshed.background.layers[0].sublayers[0].velocity.x == 32 and library.all_stages()[0].display_name == "场景 32", "刷新背景参数与目录显示名")
	check(nested_state(original.theme) == [16.0, 16, 0.16], "刷新不覆盖旧会话持有的资源")
	var inner_path := folder.path_join("inner.tscn")
	var saved_inner := FileAccess.get_file_as_string(inner_path)
	write_text(inner_path, saved_inner.replace("texture.tres", "missing_texture.tres"))
	library.refresh()
	check(not library.resolve(raw).errors.is_empty(), "嵌套场景中的缺失纹理也作为依赖错误报告")
	write_text(inner_path, saved_inner); library.refresh()
	var texture_path := folder.path_join("texture.tres")
	var saved_texture := FileAccess.get_file_as_string(texture_path)
	DirAccess.remove_absolute(texture_path); library.refresh()
	check(not library.resolve(raw).errors.is_empty(), "已缓存的纹理被删除后，刷新仍报告缺失")
	write_text(texture_path, saved_texture); library.refresh()
	check(library.resolve(raw).errors.is_empty(), "修复素材后刷新恢复加载")
	var new_folder := stages_root.path_join("second"); DirAccess.make_dir_recursive_absolute(new_folder)
	var stage := StageDefinition.new(); stage.stage_id = "new_scene"; stage.visual_theme_resource_path = folder.path_join("theme.tres")
	stage.song_resource_path = folder.path_join("unrelated_missing_song.tres")
	ResourceSaver.save(stage, new_folder.path_join("stage_definition.tres"))
	var frozen_ids := library.scene_ids()
	library.refresh()
	check(library.scene_ids().has("new_scene") and not frozen_ids.has("new_scene"), "新增场景刷新可见，已有任务的 ID 快照不变")
	check(library.resolve({"scene_id": "new_scene"}).errors.is_empty(), "场景装配不读取原关卡音乐等无关懒加载依赖")
	stage.stage_id = "broken"; stage.background_resource_path = folder.path_join("missing.tres")
	ResourceSaver.save(stage, new_folder.path_join("stage_definition.tres")); library.refresh()
	check(not library.resolve({"scene_id": "broken"}).errors.is_empty(), "缺失背景返回场景依赖错误")

func choose_scene(workspace: Control, id: String) -> void:
	var menu: OptionButton = workspace.get_node("Layout/Split/Top/Main/PreviewColumn/SceneControls/Scene")
	for i in menu.item_count:
		if menu.get_item_metadata(i) == id:
			menu.select(i); menu.item_selected.emit(i); return
	check(false, "场景菜单存在 " + id)

func ui_test() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false; workspace.recovery_path = output.path_join("recovery.json")
	root.add_child(workspace); await settle()
	workspace._open_path(FIXTURE); await settle()
	workspace.timeline.selected = PackedStringArray(["n03"]); workspace._inspect()
	workspace.audio.seek(2.3); workspace.audio.set_playing(true)
	var count: int = workspace.preview.load_count
	choose_scene(workspace, "s08")
	var paused_at: float = workspace.audio.position
	check(not workspace.audio.playing and workspace.timeline.selected.has("n03"), "选中音符时仍可切换场景，暂停并保留选区")
	await settle()
	while workspace.preview.rebuilding: await process_frame
	check(workspace.preview.stage_root != null and workspace.preview.stage_root.stage_session.stage_definition.background != null, "固定场景菜单更新正式预览")
	check(workspace.preview.load_count == count + 1 and is_equal_approx(workspace.audio.position, paused_at), "切换合并为一次重建，保持暂停位置")
	var toggle: CheckButton = workspace.get_node("Layout/Split/Top/Main/PreviewColumn/SceneControls/SceneShow")
	toggle.button_pressed = true; await settle()
	check(presentation(workspace.document).use_scene_show and not workspace.preview.stage_root.stage_show_director.get_compiled_cues().is_empty(), "真实开关带入场景演出")
	workspace.document.undo(); await settle()
	check(not toggle.button_pressed and workspace.preview.stage_root.stage_show_director.get_compiled_cues().is_empty(), "撤销同步开关与预览演出")
	count = workspace.preview.load_count
	var raw := presentation(workspace.document).duplicate(true); raw.palette_overrides = {"life": "#345678"}
	workspace.document.change_presentation(raw); await settle()
	check(workspace.preview.load_count == count, "单改配色不重建场景")
	choose_scene(workspace, "s02"); choose_scene(workspace, "s08"); await settle()
	check(workspace.preview.load_count == count + 1 and presentation(workspace.document).palette_overrides.life == "#345678", "连续切换只装配最终场景并保留配色")
	count = workspace.preview.load_count
	var button: Button = workspace.get_node("Layout/Split/Top/Main/PreviewColumn/SceneControls/RefreshScene")
	button.pressed.emit(); button.pressed.emit(); await settle()
	check(workspace.preview.load_count == count + 1 and workspace.viewport.get_child_count() == 1, "连续刷新合并，旧场景节点已释放")
	workspace._write_recovery()
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(workspace.recovery_path))
	workspace.document.new_project(); workspace._restore_recovery(recovery); await settle()
	check(presentation(workspace.document).scene_id == "s08", "恢复稿保留场景绑定")
	if DisplayServer.get_name() != "headless":
		while workspace.preview.rebuilding: await process_frame
		var folder := "res://builds/visual-review/scene-binding"; DirAccess.make_dir_recursive_absolute(folder)
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(1440, 900)]:
			root.size = size; await settle(); await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("workspace-%d.png" % size.x))
		workspace.viewport.get_texture().get_image().save_png(folder.path_join("s08.png"))
	workspace.document.change_presentation({"scene_id": "missing"}); await settle()
	check(workspace.preview.stage_root == null and workspace.problems.item_count > 0, "缺失场景在问题列表说明，预览不静默回退")
	workspace.queue_free(); await settle()
