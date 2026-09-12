@tool
extends VBoxContainer
## 背景编辑主界面。保存与切换集中在这里，画布和列表共用一个文档。

const Document = preload("res://addons/parallax_background_editor/document.gd")
const Surface = preload("res://addons/parallax_background_editor/surface.gd")
const LayerTree = preload("res://addons/parallax_background_editor/layer_tree.gd")
var document := Document.new()
var surface: Surface
var layer_tree: LayerTree
var _title: Label
var _status: Label
var _fields: Dictionary = {}
var _properties: VBoxContainer
var _sublayer_properties: VBoxContainer
var _sublayer_fields: Dictionary = {}
var _sublayer_name: LineEdit
var _sublayer_picker: OptionButton
var _new_sublayer_depth: SpinBox
var _selected_depth: int = 2147483647
var _infinite: OptionButton
var _animations: OptionButton
var _asset: Label
var _replace: Button
var _material: Label
var _material_dialog: FileDialog
var _material_buttons: Array[Button] = []
var _material_config: ConfirmationDialog
var _material_inspector: EditorInspector
var _material_draft: ShaderMaterial
var _material_target_id := -1
var _mode: CheckButton
var _play: Button
var _handheld: CheckButton
var _time: SpinBox
var _camera_x: SpinBox
var _camera_y: SpinBox
var _camera_reset: Button
var _undo: Button
var _redo: Button
var _edit_buttons: Array[Button] = []
var _open_dialog: FileDialog
var _asset_dialog: FileDialog
var _unsaved: ConfirmationDialog
var _external: ConfirmationDialog
var _pending: Callable
var _replacing := false
var _updating := false
var _playing := false
var _external_elapsed := 0.0
var _driver := ParallaxHandheldDriver.new()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	document.changed.connect(_document_changed)
	_document_changed()


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, title: String) -> Label:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	return label


func _spin(parent: Node, title: String, step: float = 1.0) -> SpinBox:
	_label(parent, title)
	var field := SpinBox.new()
	field.allow_greater = true
	field.allow_lesser = true
	field.min_value = -1000000
	field.max_value = 1000000
	field.step = step
	field.custom_minimum_size.x = 105
	field.update_on_text_changed = false
	parent.add_child(field)
	return field


func _build() -> void:
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	_button(toolbar, "打开背景资源…", func(): _open_dialog.popup_centered_ratio(0.7))
	_button(toolbar, "保存 Ctrl+S", save_document)
	_undo = _button(toolbar, "撤销", _undo_action)
	_redo = _button(toolbar, "重做", _redo_action)
	_button(toolbar, "关闭背景", func(): _guard(_close_document))
	_mode = CheckButton.new()
	_mode.text = "视差预览"
	_mode.toggled.connect(_set_preview)
	toolbar.add_child(_mode)
	_title = _label(self, "打开背景资源开始编辑")
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)
	_label(left, "层次 · 从前向后")
	var tools := HBoxContainer.new()
	left.add_child(tools)
	_edit_buttons.append(_button(tools, "添加", func(): _choose_asset(false)))
	_edit_buttons.append(_button(tools, "复制", func(): document.duplicate_selected()))
	_edit_buttons.append(_button(tools, "删除", func(): document.delete_selected()))
	var sublayer_tools := HBoxContainer.new()
	left.add_child(sublayer_tools)
	_new_sublayer_depth = _spin(sublayer_tools, "深度")
	_new_sublayer_depth.value = 1
	_edit_buttons.append(_button(sublayer_tools, "添加子层", func(): document.add_sublayer(int(_new_sublayer_depth.value))))
	_edit_buttons.append(_button(sublayer_tools, "删除子层", func(): document.delete_sublayer(document.selected_sublayer_id)))
	layer_tree = LayerTree.new()
	layer_tree.columns = 3
	layer_tree.hide_root = true
	layer_tree.select_mode = Tree.SELECT_SINGLE
	layer_tree.column_titles_visible = true
	layer_tree.set_column_title(0, "层 / 子层 / 素材")
	layer_tree.set_column_title(1, "显")
	layer_tree.set_column_title(2, "锁")
	for column in [1, 2]:
		layer_tree.set_column_expand(column, false)
		layer_tree.set_column_custom_minimum_width(column, 32)
	layer_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer_tree.item_selected.connect(_tree_selection)
	layer_tree.item_edited.connect(_tree_edited)
	layer_tree.reorder_requested.connect(func(id: int, depth: int, target: int, front: bool, sublayer: int):
		if sublayer >= 0 and target >= 0: document.reorder_sublayer(sublayer, target, front)
		elif id >= 0: document.reorder(id, depth, target, front, sublayer))
	left.add_child(layer_tree)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(middle)
	var view_tools := HFlowContainer.new()
	middle.add_child(view_tools)
	_button(view_tools, "适配画布", func(): surface.fit_canvas())
	_button(view_tools, "定位选中", func(): surface.frame_selection())
	var guides := CheckBox.new()
	guides.text = "玩法参考"
	guides.button_pressed = true
	guides.toggled.connect(func(value: bool): surface.references_visible = value)
	view_tools.add_child(guides)
	var snap := CheckBox.new()
	snap.text = "网格吸附"
	snap.toggled.connect(func(value: bool): surface.snap_enabled = value)
	view_tools.add_child(snap)
	var grid := _spin(view_tools, "间距")
	grid.allow_lesser = false
	grid.min_value = 1
	grid.value = 32
	grid.value_changed.connect(func(value: float): surface.grid_size = value)
	surface = Surface.new()
	surface.document = document
	surface.custom_minimum_size = Vector2(320, 240)
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.selection_changed.connect(_selection_changed)
	surface.gesture_changed.connect(_gesture_changed)
	surface.files_dropped.connect(_drop_assets)
	middle.add_child(surface)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 280
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	var properties := VBoxContainer.new()
	properties.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	pages.add_child(properties)
	_properties = properties
	_sublayer_properties = VBoxContainer.new()
	pages.add_child(_sublayer_properties)
	_label(_sublayer_properties, "子层属性")
	_label(_sublayer_properties, "名称")
	_sublayer_name = LineEdit.new()
	_sublayer_properties.add_child(_sublayer_name)
	_sublayer_name.text_submitted.connect(func(_text: String): _commit_sublayer_name())
	_sublayer_name.focus_exited.connect(_commit_sublayer_name)
	for key in ["所属深度", "速度 X", "速度 Y"]:
		var field := _spin(_sublayer_properties, key, 1.0 if key == "所属深度" else 0.1)
		_sublayer_fields[key] = field
		field.value_changed.connect(_sublayer_property_changed.bind(key))
	_label(_sublayer_properties, "速度单位：设计像素/秒。\n实际位移按所属深度折算；深度 0 静止。\n正深度：X 正向右，Y 正向下。\n视差预览中播放时间查看移动。").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(properties, "素材属性")
	_asset = _label(properties, "未选择")
	_asset.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_replace = _button(properties, "替换素材…", func(): _choose_asset(true))
	_material = _label(properties, "未设置 ShaderMaterial")
	_material.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_material_buttons.append(_button(properties, "选择 ShaderMaterial…", func(): _material_dialog.popup_centered_ratio(0.7)))
	_material_buttons.append(_button(properties, "清除 ShaderMaterial", func(): _change_entry("material", null)))
	_material_buttons.append(_button(properties, "配置 Shader 与参数…", _inspect_material))
	for key in ["X", "Y", "深度"]:
		var field := _spin(properties, key, 1.0 if key == "深度" else 0.1)
		_fields[key] = field
		field.value_changed.connect(_property_changed.bind(key))
	_label(properties, "所属子层")
	_sublayer_picker = OptionButton.new()
	properties.add_child(_sublayer_picker)
	_sublayer_picker.item_selected.connect(func(index: int):
		if _updating or surface.preview or document.editable_entry() == null: return
		var id: int = _sublayer_picker.get_item_metadata(index)
		document.reorder(document.selected_id, document.sublayer_record(id).depth, -1, true, id))
	_label(properties, "坐标为素材左上角。\n深度越小越靠前，0 静止。").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_infinite = OptionButton.new()
	for label in ["有限素材", "无限拼接"]: _infinite.add_item(label)
	_infinite.item_selected.connect(func(index: int): _change_entry("infinite", index == 1))
	properties.add_child(_infinite)
	var random_flip := CheckButton.new()
	random_flip.text = "无限拼接随机翻转"
	random_flip.name = "RandomFlip"
	random_flip.toggled.connect(func(value: bool): _change_entry("random_flip", value))
	properties.add_child(random_flip)
	_label(properties, "动画")
	_animations = OptionButton.new()
	_animations.item_selected.connect(func(index: int): _change_entry("animation", StringName(_animations.get_item_text(index))))
	properties.add_child(_animations)
	_label(properties, "单选后拖动边缘或角点等比缩放。\n隐藏与锁定只影响此编辑会话。").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var transport := HFlowContainer.new()
	add_child(transport)
	_play = _button(transport, "播放", func(): _playing = not _playing; _play.text = "暂停" if _playing else "播放")
	_time = _spin(transport, "时间（秒）", 0.01)
	_time.value_changed.connect(func(value: float):
		if not _updating: surface.song_time = value; _sample())
	_camera_x = _spin(transport, "镜头 X", 0.1)
	_camera_y = _spin(transport, "Y", 0.1)
	_camera_x.value_changed.connect(func(value: float):
		if not _updating: surface.camera.x = value; surface.update_sample())
	_camera_y.value_changed.connect(func(value: float):
		if not _updating: surface.camera.y = value; surface.update_sample())
	_camera_reset = _button(transport, "镜头归零", func(): surface.camera = Vector2.ZERO; surface.update_sample(); _gesture_changed())
	_handheld = CheckButton.new()
	_handheld.text = "手持晃动"
	_handheld.toggled.connect(func(value: bool): surface.handheld = value; _sample(); _update_controls())
	transport.add_child(_handheld)
	_status = _label(self, "拖入项目素材添加 · 中键浏览 · 滚轮缩放 · Esc 取消拖动")
	_open_dialog = _file_dialog(["*.tres ; StageBackgroundDefinition 背景资源"])
	_open_dialog.file_selected.connect(request_open)
	_asset_dialog = _file_dialog(["*.png,*.jpg,*.jpeg,*.webp,*.svg,*.tres,*.res ; 纹理或 SpriteFrames"])
	_asset_dialog.file_selected.connect(_asset_chosen)
	_material_dialog = _file_dialog(["*.tres,*.res ; ShaderMaterial"])
	_material_dialog.file_selected.connect(_material_chosen)
	if Engine.is_editor_hint():
		_material_config = ConfirmationDialog.new()
		_material_config.title = "背景 Shader 与参数"
		_material_config.ok_button_text = "应用"
		_material_config.cancel_button_text = "取消"
		_material_config.min_size = Vector2i(400, 300)
		_material_inspector = EditorInspector.new()
		_material_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_material_config.add_child(_material_inspector)
		_material_config.confirmed.connect(_apply_material_config)
		_material_config.canceled.connect(_cancel_material_config)
		add_child(_material_config)
	_unsaved = ConfirmationDialog.new()
	_unsaved.title = "背景尚未保存"
	_unsaved.dialog_text = "保存当前背景后继续？"
	_unsaved.ok_button_text = "保存"
	_unsaved.cancel_button_text = "取消"
	_unsaved.add_button("放弃修改", false, "discard")
	_unsaved.confirmed.connect(func():
		if save_document(): _continue_pending())
	_unsaved.custom_action.connect(func(action: StringName):
		if action == &"discard": _unsaved.hide(); _continue_pending())
	_unsaved.canceled.connect(func(): _pending = Callable())
	add_child(_unsaved)
	_external = ConfirmationDialog.new()
	_external.title = "背景文件已在外部修改"
	_external.dialog_text = "重新载入会替换当前草稿；保留草稿后再次保存会覆盖外部版本。"
	_external.ok_button_text = "重新载入"
	_external.cancel_button_text = "保留草稿"
	_external.confirmed.connect(func(): document.reload_assets(); _open(document.source_path))
	_external.canceled.connect(func(): document.acknowledge_external(); _status.text = "已保留草稿；下次保存将覆盖外部背景版本。")
	add_child(_external)
	_update_controls()


func _file_dialog(filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = filters
	add_child(dialog)
	return dialog


## 所有打开入口经过未保存检查，取消不会改变原文档。
func request_open(path: String) -> void:
	surface.cancel_gesture()
	_guard(_open.bind(path))


func _guard(action: Callable) -> void:
	if document.is_dirty():
		_pending = action
		_unsaved.popup_centered()
	else: action.call()


func _continue_pending() -> void:
	var action := _pending
	_pending = Callable()
	if action.is_valid(): action.call()


func _open(path: String) -> void:
	var error := document.open(path)
	if not error.is_empty(): _status.text = error; return
	_mode.button_pressed = false
	_set_preview(false)
	surface.song_time = 0
	_time.set_value_no_signal(0)
	surface.fit_canvas()
	_status.text = "已打开 " + path


func _close_document() -> void:
	document = Document.new()
	document.changed.connect(_document_changed)
	surface.document = document
	_mode.button_pressed = false
	_set_preview(false)
	_document_changed()


func save_document() -> bool:
	surface.cancel_gesture()
	if document.external_changed():
		_external.popup_centered()
		return false
	var error := document.save()
	_status.text = "已保存 " + document.source_path if error.is_empty() else error
	if error.is_empty() and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(document.source_path)
	return error.is_empty()


func _document_changed() -> void:
	_rebuild_tree()
	_update_properties()
	_update_controls()
	_title.text = ("● " if document.is_dirty() else "") + (document.source_path if not document.source_path.is_empty() else "打开背景资源开始编辑")
	surface.request_refresh()


func _rebuild_tree() -> void:
	_updating = true
	layer_tree.clear()
	var root_item := layer_tree.create_item()
	var divider_added := false
	var depths: Array[int] = []
	for record in document.sublayers:
		if not depths.has(record.depth): depths.append(record.depth)
	depths.sort()
	for depth in depths:
		if depth >= 0 and not divider_added:
			var divider := layer_tree.create_item(root_item)
			divider.set_text(0, "──── 玩法参考层 ────")
			divider.set_selectable(0, false)
			divider_added = true
		var group := layer_tree.create_item(root_item)
		group.set_text(0, "深度 %d%s" % [depth, " · 静止" if depth == 0 else ""])
		group.set_metadata(0, {"depth": depth})
		group.set_editable(0, not surface.preview)
		for index in range(document.sublayers.size() - 1, -1, -1):
			var record: Dictionary = document.sublayers[index]
			if record.depth != depth: continue
			var child := layer_tree.create_item(group)
			child.set_text(0, record.resource.display_name)
			child.set_tooltip_text(0, "%s · 速度 %s px/s" % [record.resource.sublayer_id, record.resource.velocity])
			child.set_metadata(0, {"depth": depth, "sublayer": record.id})
			if document.selected_id < 0 and document.selected_sublayer_id == record.id: child.select(0)
			for id in document.front_ids():
				if document.sublayer_of(id) == record.id: _add_entry_row(child, id, depth, record.id)
	if not divider_added:
		var divider := layer_tree.create_item(root_item)
		divider.set_text(0, "──── 玩法参考层 ────")
		divider.set_selectable(0, false)
	_updating = false


func _add_entry_row(parent: TreeItem, id: int, depth: int, sublayer: int) -> void:
	var value := document.entry(id)
	var row := layer_tree.create_item(parent)
	var resource: Resource = value.texture if value.texture != null else value.sprite_frames
	row.set_text(0, (resource.resource_path.get_file() if not resource.resource_path.is_empty() else "内嵌素材") if resource != null else "未指定素材")
	row.set_tooltip_text(0, "条目 %d · %s" % [document.index_of(id) + 1, resource.resource_path if resource != null else ""])
	row.set_metadata(0, {"id": id, "depth": depth, "sublayer": sublayer})
	var icon: Texture2D = value.texture
	if icon == null and value.sprite_frames != null and value.sprite_frames.has_animation(value.animation) and value.sprite_frames.get_frame_count(value.animation) > 0:
		icon = value.sprite_frames.get_frame_texture(value.animation, 0)
	if icon != null:
		row.set_icon(0, icon)
		row.set_icon_max_width(0, 36)
	for column in [1, 2]:
		row.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
		row.set_editable(column, true)
		row.set_selectable(column, false)
	row.set_checked(1, not document.hidden.has(id))
	row.set_checked(2, document.locked.has(id))
	if document.selected_id == id: row.select(0)


func _tree_selection() -> void:
	if _updating: return
	document.selected_id = -1
	document.selected_sublayer_id = -1
	var item := layer_tree.get_selected()
	if item != null:
		var metadata = item.get_metadata(0)
		if metadata is Dictionary and metadata.has("id"): document.selected_id = metadata.id
		elif metadata is Dictionary and metadata.has("sublayer"): document.selected_sublayer_id = metadata.sublayer
		elif metadata is Dictionary and metadata.has("depth"): _selected_depth = metadata.depth
	_update_properties()


func _tree_edited() -> void:
	var item := layer_tree.get_edited()
	var metadata: Dictionary = item.get_metadata(0)
	if metadata.has("depth"):
		var old_depth: int = metadata.depth
		var text := item.get_text(0).replace(" · 静止", "")
		var new_depth := int(text.trim_prefix("深度 "))
		if not document.change_depth(old_depth, new_depth):
			_status.text = "目标深度存在同标识子层，未修改。"
		_rebuild_tree()
		return
	var id: int = metadata.id
	var column := layer_tree.get_edited_column()
	var state: Dictionary = document.hidden if column == 1 else document.locked
	var active := not item.is_checked(column) if column == 1 else item.is_checked(column)
	if active: state[id] = true
	else: state.erase(id)
	surface.request_refresh()
	_update_properties()


func _selection_changed() -> void:
	document.selected_sublayer_id = -1
	_rebuild_tree()
	_update_properties()


func _update_properties() -> void:
	_updating = true
	var record := document.sublayer_record(document.selected_sublayer_id) if document.selected_id < 0 else {}
	_sublayer_properties.visible = not record.is_empty()
	_properties.visible = record.is_empty()
	for field: SpinBox in _sublayer_fields.values(): field.editable = not surface.preview
	if not record.is_empty():
		_sublayer_name.text = record.resource.display_name
		_sublayer_name.editable = not surface.preview
		_sublayer_fields["所属深度"].set_value_no_signal(record.depth)
		_sublayer_fields["速度 X"].set_value_no_signal(record.resource.velocity.x)
		_sublayer_fields["速度 Y"].set_value_no_signal(record.resource.velocity.y)
		_new_sublayer_depth.set_value_no_signal(record.depth)
	var first := document.selected_entry()
	var editable := document.editable_entry() != null and not surface.preview
	for field: SpinBox in _fields.values(): field.editable = editable
	_infinite.disabled = not editable
	var random_flip: CheckButton = _properties.get_node_or_null("RandomFlip")
	_replace.disabled = not editable
	for button in _material_buttons: button.disabled = not editable
	_material_buttons[2].disabled = not editable or not Engine.is_editor_hint()
	_animations.clear()
	_animations.disabled = true
	_sublayer_picker.clear()
	_sublayer_picker.disabled = not editable
	if first == null:
		_asset.text = "未选择素材"
		_material.text = "未设置 ShaderMaterial"
		_updating = false
		return
	if random_flip != null:
		random_flip.button_pressed = first.infinite and first.random_flip
	random_flip.disabled = not editable or not first.infinite
	_fields.X.set_value_no_signal(first.position.x)
	_fields.Y.set_value_no_signal(first.position.y)
	_fields["深度"].set_value_no_signal(document.depth_of(document.selected_id))
	for layer in document.sublayers:
		_sublayer_picker.add_item("%d / %s" % [layer.depth, layer.resource.display_name])
		var index := _sublayer_picker.item_count - 1
		_sublayer_picker.set_item_metadata(index, layer.id)
		if layer.id == document.sublayer_of(document.selected_id): _sublayer_picker.select(index)
	_infinite.select(1 if first.infinite else 0)
	var resource: Resource = first.texture if first.texture != null else first.sprite_frames
	_asset.text = (resource.resource_path if resource != null else "未指定素材") + (" · 已锁定" if document.locked.has(document.selected_id) else "")
	_material.text = "ShaderMaterial：" + (first.material.resource_path if first.material != null and not first.material.resource_path.is_empty() else "内嵌材质") if first.material != null else "未设置 ShaderMaterial"
	_material.tooltip_text = "Shader 参数在 Godot Inspector 中配置"
	if first.sprite_frames != null:
		for name in first.sprite_frames.get_animation_names():
			_animations.add_item(name)
			if name == first.animation: _animations.select(_animations.item_count - 1)
		_animations.disabled = not editable
	_updating = false


func _property_changed(value: float, key: String) -> void:
	if _updating or surface.preview or document.editable_entry() == null: return
	var before := document.snapshot()
	var entry := document.editable_entry()
	match key:
		"X": entry.position.x = value
		"Y": entry.position.y = value
		"深度":
			document.reorder(document.selected_id, int(value))
			return
	document.commit("修改" + key, before)


func _commit_sublayer_name() -> void:
	if _updating or surface.preview: return
	var record := document.sublayer_record(document.selected_sublayer_id)
	if not record.is_empty() and record.resource.display_name != _sublayer_name.text:
		document.change_sublayer(record.id, "display_name", _sublayer_name.text)


func _sublayer_property_changed(value: float, key: String) -> void:
	if _updating or surface.preview: return
	var record := document.sublayer_record(document.selected_sublayer_id)
	if record.is_empty(): return
	if key == "所属深度":
		if not document.change_sublayer(record.id, "depth", int(value)):
			_status.text = "目标深度存在同标识子层，未移动。"
			_update_properties()
	else:
		var velocity: Vector2 = record.resource.velocity
		if key == "速度 X": velocity.x = value
		else: velocity.y = value
		document.change_sublayer(record.id, "velocity", velocity)


func _change_entry(key: String, value: Variant) -> void:
	if _updating or surface.preview or document.editable_entry() == null: return
	var before := document.snapshot()
	document.editable_entry().set(key, value)
	document.commit("修改素材属性", before)


func _choose_asset(replace: bool) -> void:
	_replacing = replace
	_asset_dialog.popup_centered_ratio(0.7)


func _asset_chosen(path: String) -> void:
	if surface.preview: return
	var resource := load(path)
	if not resource is Texture2D and not resource is SpriteFrames:
		_status.text = "请选择纹理或 SpriteFrames。"
		return
	if _replacing:
		if document.editable_entry() == null: return
		var before := document.snapshot()
		document.assign_asset(document.editable_entry(), resource)
		document.commit("替换素材", before)
	else: document.add_asset(resource, Vector2.ZERO)


func _material_chosen(path: String) -> void:
	if surface.preview or document.editable_entry() == null: return
	var resource := load(path)
	if not resource is ShaderMaterial:
		_status.text = "请选择 ShaderMaterial。"
		return
	_change_entry("material", resource)


## 原生 Inspector 编辑当前条目的材质副本；空材质可直接创建和指定 Shader。
func _inspect_material() -> void:
	if surface.preview or document.editable_entry() == null or not Engine.is_editor_hint(): return
	_material_target_id = document.selected_id
	var source := document.editable_entry().material
	_material_draft = source.duplicate(false) as ShaderMaterial if source != null else ShaderMaterial.new()
	_material_inspector.edit(_material_draft)
	_material_config.popup_centered_clamped(Vector2i(560, 640), 0.85)


## 以替换材质的单次命令提交参数，旧材质不被原地修改，撤销可恢复全部 uniform。
func _apply_material_config() -> void:
	if _material_draft != null and document.selected_id == _material_target_id:
		# Inspector 可能仍持有副本；提交另一份副本避免后续编辑修改撤销快照。
		_change_entry("material", _material_draft.duplicate(false))
	_cancel_material_config()


## 取消仅释放草稿，不修改背景文档或外部材质文件。
func _cancel_material_config() -> void:
	if _material_inspector != null: _material_inspector.edit(null)
	_material_draft = null
	_material_target_id = -1


func _drop_assets(paths: PackedStringArray, position: Vector2) -> void:
	if document.source_path.is_empty(): _status.text = "请先打开背景资源。"; return
	for path in paths:
		if not document.add_asset(load(path), position): _status.text = "跳过非纹理或 SpriteFrames：" + path


func _set_preview(value: bool) -> void:
	_playing = false
	_play.text = "播放"
	_handheld.set_pressed_no_signal(false)
	surface.handheld = false
	surface.set_preview(value)
	_update_controls()
	_update_properties()
	_gesture_changed()


func _update_controls() -> void:
	var editing := not surface.preview and not document.source_path.is_empty()
	layer_tree.editing_enabled = editing
	for button in _edit_buttons: button.disabled = not editing
	_undo.disabled = not editing or not document.history.has_undo()
	_redo.disabled = not editing or not document.history.has_redo()
	_play.disabled = not surface.preview
	_handheld.disabled = not surface.preview
	_camera_x.editable = surface.preview and not surface.handheld
	_camera_y.editable = surface.preview and not surface.handheld
	_camera_reset.disabled = not surface.preview or surface.handheld


func _gesture_changed() -> void:
	_camera_x.set_value_no_signal(surface.camera.x)
	_camera_y.set_value_no_signal(surface.camera.y)
	if surface._gesture in ["move", "resize"]: _status.text = surface.message


func _sample() -> void:
	if surface.handheld: surface.camera = _driver.offset_at(surface.song_time)
	surface.update_sample()
	_gesture_changed()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or surface == null: return
	if _playing and surface.preview:
		surface.song_time += delta
		_time.set_value_no_signal(surface.song_time)
		_sample()
	_external_elapsed += delta
	if _external_elapsed > 1.0:
		_external_elapsed = 0
		if not _external.visible and not _unsaved.visible and document.external_changed(): _external.popup_centered()


func _undo_action() -> void:
	if surface.preview: return
	surface.cancel_gesture()
	document.history.undo()


func _redo_action() -> void:
	if surface.preview: return
	surface.cancel_gesture()
	document.history.redo()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if _unsaved.visible or _external.visible or _open_dialog.visible or _asset_dialog.visible or _material_dialog.visible: return
	if _material_config != null and _material_config.visible: return
	var focus := get_viewport().gui_get_focus_owner()
	var text_input := focus is LineEdit or focus is TextEdit
	if event.ctrl_pressed and event.keycode == KEY_S:
		if focus is LineEdit: focus.text_submitted.emit(focus.text)
		save_document()
	elif not text_input and event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed: _redo_action()
		else: _undo_action()
	elif not text_input and event.ctrl_pressed and event.keycode == KEY_Y: _redo_action()
	elif not text_input and not surface.preview and event.ctrl_pressed and event.keycode == KEY_D: document.duplicate_selected()
	elif not text_input and not surface.preview and event.keycode == KEY_DELETE: document.delete_selected()
	else: return
	get_viewport().set_input_as_handled()
