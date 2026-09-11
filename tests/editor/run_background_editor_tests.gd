extends SceneTree
## 通过真实工作区、控制中心和输入事件验证编辑行为；仅在 builds 下写测试资源。
const Document = preload("res://addons/parallax_background_editor/document.gd")
const Workspace = preload("res://addons/parallax_background_editor/workspace.gd")
var failures := 0
var checks := 0
const OUTPUT := "res://builds/background-editor-validation"


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL ", label)


func make_texture(color: Color) -> ImageTexture:
	var image := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func mouse(surface: Control, point: Vector2, pressed: bool, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift
	surface._gui_input(event)


func motion(surface: Control, point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	surface._gui_input(event)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if Engine.is_editor_hint(): await test_editor_plugin()
	if "--background-shader-only" in OS.get_cmdline_user_args():
		print("BACKGROUND SHADER: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	var document := Document.new()
	check(document.open("res://content/stages/s08/stage_definition.tres").is_empty(), "打开 s08")
	check(document.items.size() == 5, "还原五层条目")
	var original: StageBackgroundDefinition = load("res://content/stages/s08/stage_background.tres")
	var original_position := original.layers[0].sublayers[0].entries[0].position
	check(document.entry(document.items[0].id).position == original_position, "还原素材坐标")
	document.items[0].entry.position.x += 10
	check(original.layers[0].sublayers[0].entries[0].position == original_position, "编辑副本不修改共享条目")
	check(document.items[0].entry.texture == original.layers[0].sublayers[0].entries[0].texture, "素材资源引用共享")
	var fixture := OUTPUT.path_join("background.tres")
	check(ResourceSaver.save(original, fixture) == OK, "建立测试资源")
	check(document.open(fixture).is_empty(), "打开独立背景")
	var id: int = document.items[0].id
	document.selected_id = id
	var before := document.snapshot()
	document.entry(id).position += Vector2(18, 37)
	document.commit("移动", before)
	check(document.is_dirty(), "编辑后未保存")
	document.history.undo()
	check(not document.is_dirty() and document.entry(id).position == original_position, "撤销回到已保存状态")
	document.history.redo()
	check(document.entry(id).position == original_position + Vector2(18, 37), "重做还原坐标")
	document.hidden[id] = true
	document.locked[id] = true
	check(document.save().is_empty(), "保存条目")
	var reopened := Document.new()
	check(reopened.open(fixture).is_empty() and reopened.items[0].entry.position == original_position + Vector2(18, 37), "保存重开坐标一致")
	check(reopened.hidden.is_empty() and reopened.locked.is_empty(), "临时状态不写入资源")
	var count := document.items.size()
	document.delete_selected()
	check(document.items.size() == count, "锁定条目不能删除")
	document.locked.clear()
	document.duplicate_selected()
	check(document.items.size() == count + 1, "复制条目")
	document.history.undo()
	check(document.items.size() == count, "撤销复制")
	var ids: Array[int] = [document.items[0].id, document.items[1].id]
	var target: int = document.items[2].id
	var untouched_depth := document.depth_of(ids[1])
	document.reorder(ids[0], -2, target, true)
	check(document.depth_of(ids[0]) == -2 and document.depth_of(ids[1]) == untouched_depth, "跨深度拖放只修改一个素材")
	document.reorder(ids[1], -2, target, true)
	document.reorder(ids[0], -2, ids[1], true)
	check(document.front_ids().find(ids[0]) < document.front_ids().find(ids[1]), "同层前后顺序")
	var stage := StageDefinition.new()
	stage.stage_id = "editor_fixture"
	stage.description = "保持关卡其他字段"
	var stage_path := OUTPUT.path_join("stage_definition.tres")
	# 上次运行生成的背景允许存在，使用本次唯一子目录测试首次挂接。
	var new_dir := OUTPUT.path_join("new_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(new_dir)
	stage_path = new_dir.path_join("stage_definition.tres")
	ResourceSaver.save(stage, stage_path)
	var stage_text := FileAccess.get_file_as_string(stage_path)
	check(reopened.open(stage_path).is_empty() and not reopened.external_changed(), "空背景关卡打开")
	check(reopened.save().is_empty(), "首次保存创建并挂接")
	check(FileAccess.get_file_as_string(stage_path).begins_with(stage_text.strip_edges()), "挂接保留原关卡内容")
	var loaded_stage: StageDefinition = ResourceLoader.load(stage_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded_stage.background_resource_path == new_dir.path_join("stage_background.tres"), "延迟路径挂接")
	var file := FileAccess.open(reopened.background_path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\n; external edit\n")
	file.close()
	check(reopened.external_changed(), "检测外部修改")
	reopened.acknowledge_external()
	check(not reopened.external_changed(), "明确保留草稿后接纳外部版本基线")
	await test_sublayer_workspace()
	await test_workspace(fixture)
	print("BACKGROUND EDITOR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## 子层属性经真实控件修改，验证撤销、层级保存、预览和跨子层挂载。
func test_sublayer_workspace() -> void:
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.document.add_sublayer(2)
	var child_id := workspace.document.selected_sublayer_id
	check(workspace._sublayer_properties.visible and not workspace._properties.visible, "选中子层显示独立属性页")
	workspace._sublayer_fields["速度 X"].value = 24
	workspace._sublayer_fields["速度 Y"].value = -12
	var child := workspace.document.sublayer_record(child_id)
	check(child.resource.velocity == Vector2(24, -12), "速度 X/Y 控件分别提交")
	workspace._undo_action()
	check(workspace.document.sublayer_record(child_id).resource.velocity == Vector2(24, 0), "子层速度撤销")
	workspace._redo_action()
	workspace._sublayer_name.text = "流云"
	workspace._sublayer_name.text_submitted.emit("流云")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("sublayer-properties.png"))
	workspace.document.add_asset(make_texture(Color.RED), Vector2(10, 20))
	var id := workspace.document.selected_id
	check(workspace.document.sublayer_of(id) == child_id, "新增素材进入选中子层")
	workspace.document.background_path = OUTPUT.path_join("sublayers.tres")
	check(workspace.document.save().is_empty(), "保存层级与速度")
	var reopened := Document.new()
	check(reopened.open(workspace.document.background_path).is_empty(), "重开子层资源")
	var loaded := reopened.definition()
	check(loaded.layers[0].depth == 2 and loaded.layers[0].sublayers[0].display_name == "流云" and loaded.layers[0].sublayers[0].velocity == Vector2(24, -12), "重开保留子层属性")
	workspace.surface.song_time = 5
	workspace.surface.refresh()
	check(workspace.surface.controller.get_configured_object(0).position.is_equal_approx(Vector2(10, 20)), "布局保持素材原坐标")
	workspace._set_preview(true)
	workspace.surface.refresh()
	check(workspace.surface.controller.get_configured_object(0).global_position.is_equal_approx(Vector2(70, -10)), "编辑器预览复用正式速度")
	check(not workspace._sublayer_fields["速度 X"].editable, "预览禁止子层编辑")
	workspace._set_preview(false)
	workspace.document.add_sublayer(2)
	var target := workspace.document.selected_sublayer_id
	workspace.document.reorder(id, 2, -1, true, target)
	check(workspace.document.sublayer_of(id) == target, "挂载对象移动到另一子层")
	workspace._undo_action()
	check(workspace.document.sublayer_of(id) == child_id, "撤销恢复所属子层")
	workspace.queue_free()
	await process_frame


func test_workspace(fixture: String) -> void:
	root.size = Vector2i(1440, 900)
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.request_open(fixture)
	await process_frame
	await process_frame
	var surface := workspace.surface
	check(surface.controller.get_configured_object(4) != null, "实际工作区装配背景")
	check(surface.size.x >= 320 and surface.size.y >= 240, "画布布局可用")
	await test_material_modes(workspace)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("s08-workspace.png"))
	check(surface.to_design(surface.pan + Vector2(700, 300) * surface.zoom).is_equal_approx(Vector2(700, 300)), "浏览变换精确逆换算")
	workspace.document.items.clear()
	workspace.document.sublayers.clear()
	workspace.document.selected_sublayer_id = -1
	workspace.document.selected_id = -1
	workspace.document.hidden.clear()
	workspace.document.locked.clear()
	workspace.document.add_asset(make_texture(Color.RED), Vector2(250, 250))
	var first: int = workspace.document.items[0].id
	workspace.document.add_asset(make_texture(Color.BLUE), Vector2(350, 250))
	var second: int = workspace.document.items[1].id
	await process_frame
	await process_frame
	mouse(surface, surface.pan + Vector2(240, 240) * surface.zoom, true)
	motion(surface, surface.pan + Vector2(400, 290) * surface.zoom, Vector2.ZERO)
	mouse(surface, surface.pan + Vector2(400, 290) * surface.zoom, false)
	check(workspace.document.selected_id == -1, "空白拖动不再框选")
	check(workspace.layer_tree.select_mode == Tree.SELECT_SINGLE, "列表使用单选模式")
	mouse(surface, surface.pan + Vector2(500, 300) * surface.zoom, true)
	mouse(surface, surface.pan + Vector2(500, 300) * surface.zoom, false)
	check(workspace.document.selected_id == -1, "空白单击清除选择")
	mouse(surface, surface.pan + Vector2(260, 260) * surface.zoom, true)
	mouse(surface, surface.pan + Vector2(260, 260) * surface.zoom, false)
	check(workspace.document.selected_id == first, "画布点击选择")
	mouse(surface, surface.pan + Vector2(360, 260) * surface.zoom, true, true)
	mouse(surface, surface.pan + Vector2(360, 260) * surface.zoom, false, true)
	check(workspace.document.selected_id == second, "Shift 点击仍只选择当前素材")
	var start := surface.pan + Vector2(260, 260) * surface.zoom
	mouse(surface, start, true)
	motion(surface, start + Vector2(30, 20) * surface.zoom, Vector2(30, 20) * surface.zoom)
	mouse(surface, start + Vector2(30, 20) * surface.zoom, false)
	check(workspace.document.entry(first).position.is_equal_approx(Vector2(280, 270)) and workspace.document.entry(second).position.is_equal_approx(Vector2(350, 250)), "拖动仅移动当前素材")
	workspace._undo_action()
	check(workspace.document.entry(first).position == Vector2(250, 250) and workspace.document.entry(second).position == Vector2(350, 250), "一次撤销整次拖动")
	await process_frame
	await process_frame
	mouse(surface, start, true)
	motion(surface, start + Vector2(20, 30), Vector2(20, 30))
	surface.cancel_gesture()
	check(workspace.document.entry(first).position == Vector2(250, 250), "取消拖动恢复草稿")
	await process_frame
	await process_frame
	surface.snap_enabled = true
	surface.grid_size = 32
	mouse(surface, start, true)
	motion(surface, start + Vector2(13, 13) * surface.zoom, Vector2(13, 13) * surface.zoom)
	mouse(surface, start + Vector2(13, 13) * surface.zoom, false)
	check(workspace.document.entry(first).position == Vector2(256, 256), "网格吸附按设计坐标")
	workspace._undo_action()
	surface.snap_enabled = false
	workspace.document.locked[first] = true
	workspace.document.selected_id = first
	workspace._update_properties()
	check(not workspace._fields.X.editable and workspace._replace.disabled, "锁定素材属性不可修改")
	workspace.document.locked.clear()
	workspace.document.hidden[first] = true
	surface.refresh()
	check(not surface.controller.get_configured_object(0).visible and surface.hit(start) == -1, "隐藏不绘制且不命中")
	workspace.document.hidden.clear()
	surface.refresh()
	workspace.document.selected_id = first
	workspace._property_changed(100, "X")
	check(workspace.document.entry(first).position.x == 100 and workspace.document.entry(second).position.x == 350, "坐标修改不影响其他素材")
	workspace._property_changed(-2, "深度")
	check(workspace.document.depth_of(first) == -2 and workspace.document.depth_of(second) == 1, "深度修改只影响选中素材")
	workspace._change_entry("infinite", true)
	check(workspace.document.entry(first).infinite and not workspace.document.entry(second).infinite, "拼接修改只影响选中素材")
	workspace.document.selected_id = second
	workspace._update_properties()
	check(workspace._fields["深度"].value == 1 and workspace._fields["深度"].suffix.is_empty() and workspace._infinite.item_count == 2, "属性区仅显示当前素材，无混合值")
	workspace._property_changed(400, "X")
	check(workspace.document.entry(first).position.x == 100 and workspace.document.entry(second).position.x == 400, "切换素材后只修改新选中项")
	workspace._undo_action()
	check(workspace.document.entry(first).position.x == 100 and workspace.document.entry(second).position.x == 350, "撤销单项修改保持其他项")
	workspace._set_preview(true)
	var signature := workspace.document.signature()
	mouse(surface, Vector2(100, 100), true)
	motion(surface, Vector2(120, 130), Vector2(20, 30))
	mouse(surface, Vector2(120, 130), false)
	check(surface.camera != Vector2.ZERO and signature == workspace.document.signature(), "镜头拖动不改素材")
	workspace._set_preview(false)
	check(surface.camera == Vector2.ZERO and not surface.handheld and not workspace._playing, "返回布局归零停止预览")
	workspace.document.entry(first).infinite = true
	workspace.document.selected_id = first
	surface.request_refresh()
	await process_frame
	await process_frame
	check(surface.hit(Vector2(15, 15)) == first, "无限重复区域可命中原条目")
	var animation := SpriteFrames.new()
	animation.set_animation_speed(&"default", 2)
	animation.add_frame(&"default", make_texture(Color.RED))
	animation.add_frame(&"default", make_texture(Color.GREEN))
	workspace.document.assign_asset(workspace.document.entry(first), animation)
	surface.request_refresh()
	await process_frame
	await process_frame
	surface.song_time = 0.75
	surface.update_sample()
	var object := surface.controller.get_configured_object(workspace.document.configured_index(first)) as AnimatedSprite2D
	check(object.frame == 1, "编辑器按时间采样正式动画")
	workspace.document.entry(first).animation = &"missing"
	check(workspace.document.validation_error().contains("条目 %d" % (workspace.document.index_of(first) + 1)), "非法动画标明条目")
	check(not workspace.document.save().is_empty(), "无效配置阻止保存")
	workspace.document.entry(first).animation = &"default"
	workspace.request_open(fixture)
	check(workspace._unsaved.visible and workspace.document.items.size() == 2, "切换先提示未保存")
	workspace._unsaved.hide()
	workspace._unsaved.canceled.emit()
	check(workspace.document.items.size() == 2, "取消切换保留草稿")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("workspace.png"))
		var image := surface.viewport.get_texture().get_image()
		check(image.get_pixel(15, 15).g > 0.9, "渲染重复画面为当前动画帧")
	await test_resize(workspace)
	workspace._close_document()
	check(workspace.document.items.is_empty() and surface.document == workspace.document, "关闭后工作区使用新草稿")
	workspace.queue_free()
	await process_frame


func test_resize(workspace: Workspace) -> void:
	var doc := workspace.document
	var surface := workspace.surface
	doc.items.clear()
	doc.selected_id = -1
	doc.hidden.clear()
	doc.locked.clear()
	doc.add_asset(make_texture(Color.YELLOW), Vector2(100, 120))
	var id: int = doc.items[0].id
	surface.zoom = 2.0
	surface.pan = Vector2(25, 15)
	surface._auto_fit = false
	surface._update_transform()
	await process_frame
	await process_frame
	for handle in surface.RESIZE_HANDLES:
		var before := surface.selection_bounds()
		var fixed := before.get_center() - handle * before.size * 0.5
		var start := surface.pan + (before.get_center() + handle * before.size * 0.5) * surface.zoom
		var finish := start + handle * before.size * surface.zoom
		mouse(surface, start, true)
		motion(surface, finish, finish - start)
		mouse(surface, finish, false)
		check(is_equal_approx(doc.entry(id).uniform_scale, 2.0), "八方向手柄等比放大 %s" % handle)
		var after := surface.selection_bounds()
		check((after.get_center() - handle * after.size * 0.5).is_equal_approx(fixed), "缩放固定对侧 %s" % handle)
		workspace._undo_action()
		check(doc.entry(id).position == Vector2(100, 120) and doc.entry(id).uniform_scale == 1.0, "撤销恢复位置与倍率")
	workspace._redo_action()
	await process_frame
	await process_frame
	var object := surface.controller.get_configured_object(0)
	check(is_equal_approx(object.get_global_transform_with_canvas().x.length(), 4.0), "运行时应用保存倍率与浏览缩放")
	check(surface.hit(surface.pan + (doc.entry(id).position + Vector2(10, 10)) * surface.zoom) == id, "缩放后命中准确")
	check(doc.save().is_empty(), "保存缩放配置")
	var reopened := Document.new()
	check(reopened.open(doc.background_path).is_empty() and reopened.items[0].entry.uniform_scale == 2.0 and reopened.items[0].entry.position == doc.entry(id).position, "重开保留缩放和固定点坐标")
	var bounds := surface.selection_bounds()
	var start := surface.pan + bounds.end * surface.zoom
	mouse(surface, start, true)
	motion(surface, start + Vector2(40, 30), Vector2(40, 30))
	surface.cancel_gesture()
	check(doc.entry(id).uniform_scale == 2.0 and not doc.is_dirty(), "取消缩放不留下修改")
	doc.entry(id).infinite = true
	surface.refresh()
	check(surface.hit(Vector2(15, 15)) == id, "缩放无限素材重复格命中")
	var display := surface._display_rect(id, Vector2(15, 15))
	check(display.size == Vector2(128, 96), "拼接格与选框同步缩放")
	doc.locked[id] = true
	check(surface.resize_handle_at(start) == -1, "锁定对象没有缩放手柄")
	doc.locked.clear()
	surface.set_preview(true)
	check(surface.resize_handle_at(start) == -1, "预览模式禁止素材缩放")
	surface.set_preview(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		check(surface.viewport.get_texture().get_image().get_pixel(15, 15).r > 0.9, "缩放后无限绘制仍覆盖视口")


## 布局/预览切换只影响显示，材质修改通过完整替换接入历史与持久化。
func test_material_modes(workspace: Workspace) -> void:
	workspace.document.selected_id = workspace.document.items[0].id
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float amount : hint_range(0.0, 1.0) = 1.0; void fragment() { COLOR = vec4(amount, 0.0, 0.0, 1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"amount", 0.75)
	workspace._change_entry("material", material)
	await process_frame
	await process_frame
	check(workspace.surface.controller.get_configured_object(0).material == null, "布局模式不应用背景 Shader")
	workspace._set_preview(true)
	await process_frame
	await process_frame
	var rendered := workspace.surface.controller.get_configured_object(0).material as ShaderMaterial
	check(rendered != null and rendered.get_shader_parameter(&"amount") == 0.75, "切换预览立即应用 Shader 参数")
	check(workspace._material_buttons[0].disabled, "预览锁定材质编辑")
	workspace._set_preview(false)
	await process_frame
	await process_frame
	check(workspace.surface.controller.get_configured_object(0).material == null, "退出预览恢复原素材")
	check(workspace.document.selected_entry().material == material, "模式切换保留保存用材质")
	if Engine.is_editor_hint():
		workspace._inspect_material()
		check(workspace._material_inspector.get_edited_object() == workspace._material_draft, "原生 Inspector 绑定材质副本")
		workspace._material_draft.set_shader_parameter(&"amount", 0.25)
		check(material.get_shader_parameter(&"amount") == 0.75, "配置副本不修改原材质")
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			workspace._material_config.get_texture().get_image().save_png(OUTPUT.path_join("shader-config.png"))
		workspace._material_config.hide()
		workspace._cancel_material_config()
		check(workspace.document.selected_entry().material == material, "取消参数编辑不改变背景")
		workspace._inspect_material()
		workspace._material_draft.set_shader_parameter(&"amount", 0.25)
		workspace._material_config.hide()
		workspace._apply_material_config()
		check(workspace.document.selected_entry().material.get_shader_parameter(&"amount") == 0.25, "应用参数更新条目")
		workspace._undo_action()
		check(workspace.document.selected_entry().material.get_shader_parameter(&"amount") == 0.75, "参数编辑一次撤销")
		workspace._redo_action()
		check(workspace.document.selected_entry().material.get_shader_parameter(&"amount") == 0.25, "参数编辑一次重做")
	var path := OUTPUT.path_join("configured-shader.tres")
	check(ResourceSaver.save(workspace.document.definition(), path) == OK, "编辑后的材质可保存")
	var reopened := Document.new()
	check(reopened.open(path).is_empty(), "配置背景重新打开")
	check(reopened.items[0].entry.material.get_shader_parameter(&"amount") == workspace.document.selected_entry().material.get_shader_parameter(&"amount"), "配置参数保存重开一致")
	workspace._set_preview(false)


func test_editor_plugin() -> void:
	var plugin_workspace: Workspace
	for attempt in 120:
		for child in EditorInterface.get_editor_main_screen().get_children():
			if child.get_script() == Workspace: plugin_workspace = child
		if plugin_workspace != null: break
		await process_frame
	check(plugin_workspace != null, "Godot 主编辑页插件已挂载")
	if plugin_workspace == null: return
	EditorInterface.set_main_screen_editor("背景编辑器")
	plugin_workspace.request_open("res://content/stages/s08/stage_definition.tres")
	await process_frame
	await process_frame
	check(plugin_workspace.surface.controller.get_configured_object(4) != null, "编辑器工具模式执行五层装配")
	await test_material_modes(plugin_workspace)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("godot-plugin.png"))
	plugin_workspace._close_document()
