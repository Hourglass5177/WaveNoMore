@tool
extends Control
## 画布浏览与选取手势。图像始终由正式 ParallaxController 在独立视口绘制。

signal selection_changed
signal gesture_changed
signal files_dropped(paths: PackedStringArray, position: Vector2)
const Document = preload("res://addons/parallax_background_editor/document.gd")
var document: Document
var controller: ParallaxController
var viewport: SubViewport
var zoom := 0.4
var pan := Vector2.ZERO
var preview := false
var handheld := false
var references_visible := true
var snap_enabled := false
var grid_size := 32.0
var camera := Vector2.ZERO
var song_time := 0.0
var message := ""
var _gesture := ""
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _before: Dictionary = {}
var _move_id := -1
var _move_origin := Vector2.ZERO
var _refresh_pending := false
var _images: Dictionary = {}
var _auto_fit := true
const RESIZE_HANDLES: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
var _resize_id := -1
var _resize_bounds := Rect2()
var _resize_anchor := Vector2.ZERO
var _resize_direction := Vector2.ZERO
var _resize_scale := 1.0


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	controller = ParallaxController.new()
	viewport.add_child(controller)
	resized.connect(_resize)
	focus_exited.connect(cancel_gesture)
	_resize()
	fit_canvas.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_gesture()


func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()


func _resize() -> void:
	viewport.size = Vector2i(maxf(size.x, 1), maxf(size.y, 1))
	if _auto_fit: fit_canvas()
	else: _update_transform()


func _update_transform() -> void:
	if controller == null: return
	controller.transform = Transform2D(Vector2(zoom, 0), Vector2(0, zoom), pan)
	controller.set_camera_position(camera)
	queue_redraw()


func to_design(point: Vector2) -> Vector2:
	return (point - pan) / zoom


func fit_canvas() -> void:
	_auto_fit = true
	zoom = maxf(0.02, minf((size.x - 50) / 1920.0, (size.y - 50) / 1080.0))
	pan = (size - Vector2(1920, 1080) * zoom) * 0.5
	_update_transform()


func frame_selection() -> void:
	if document == null or document.selected_entry() == null: return
	_auto_fit = false
	var bounds := selection_bounds()
	zoom = clampf(minf((size.x - 70) / maxf(bounds.size.x, 1), (size.y - 70) / maxf(bounds.size.y, 1)), 0.02, 8.0)
	pan = size * 0.5 - bounds.get_center() * zoom
	_update_transform()


func entry_size(id: int) -> Vector2:
	var entry := document.entry(id)
	if entry.texture != null: return entry.texture.get_size()
	if entry.sprite_frames != null and entry.sprite_frames.has_animation(entry.animation) and entry.sprite_frames.get_frame_count(entry.animation) > 0:
		var image := entry.sprite_frames.get_frame_texture(entry.animation, 0)
		if image != null: return image.get_size()
	return Vector2(32, 32)


func selection_bounds() -> Rect2:
	var entry := document.selected_entry()
	return Rect2(entry.position, entry_size(document.selected_id) * entry.uniform_scale) if entry != null else Rect2()


## 同帧数据修改合并装配，先归零后装配，再恢复时间与镜头。
func request_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	refresh.call_deferred()


func refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree() or document == null: return
	message = document.validation_error()
	controller.clear()
	_images.clear()
	if message.is_empty(): message = controller.configure(document.definition(), preview)
	controller.set_song_time(song_time, preview)
	controller.set_camera_position(camera)
	var ids := document.configured_ids()
	for index in ids.size():
		var object := controller.get_configured_object(index)
		if object != null: object.visible = not document.hidden.has(ids[index])
	queue_redraw()


func update_sample() -> void:
	controller.set_song_time(song_time, preview)
	controller.set_camera_position(camera)
	queue_redraw()


func set_preview(value: bool) -> void:
	cancel_gesture()
	preview = value
	if not preview:
		camera = Vector2.ZERO
		handheld = false
	update_sample()
	request_refresh()


## 命中实际精灵的当前帧；无限图案按同一素材格取局部像素，不改写资源位置。
func hit(point: Vector2) -> int:
	for id in document.front_ids():
		if document.hidden.has(id) or document.locked.has(id): continue
		var object := controller.get_configured_object(document.configured_index(id))
		if object == null: continue
		var local := object.get_global_transform_with_canvas().affine_inverse() * point
		var extent := entry_size(id)
		if document.entry(id).infinite:
			local = Vector2(fposmod(local.x, extent.x), fposmod(local.y, extent.y))
		if not Rect2(Vector2.ZERO, extent).has_point(local): continue
		var image_texture: Texture2D = object.texture if object is Sprite2D else object.sprite_frames.get_frame_texture(object.animation, object.frame)
		if not _images.has(image_texture): _images[image_texture] = image_texture.get_image()
		var image: Image = _images[image_texture]
		if image == null or image.is_empty() or image.get_pixel(clampi(int(local.x), 0, image.get_width() - 1), clampi(int(local.y), 0, image.get_height() - 1)).a > 0.05:
			return id
	return -1


func _gui_input(event: InputEvent) -> void:
	if document == null: return
	if event is InputEventKey and event.pressed:
		if _gesture == "resize" and event.keycode != KEY_ESCAPE:
			accept_event()
			return
		if event.keycode == KEY_ESCAPE:
			cancel_gesture()
			accept_event()
		if not preview and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var delta := Vector2.ZERO
			match event.keycode:
				KEY_LEFT: delta.x = -1
				KEY_RIGHT: delta.x = 1
				KEY_UP: delta.y = -1
				KEY_DOWN: delta.y = 1
			var before := document.snapshot()
			if document.editable_entry() != null:
				document.editable_entry().position += delta * (10 if event.shift_pressed else 1)
				document.commit("微调坐标", before)
			accept_event()
	if event is InputEventMouseButton:
		grab_focus()
		# 缩放过程中不切换浏览手势，确保固定点和撤销快照保持一致。
		if _gesture == "resize" and event.button_index != MOUSE_BUTTON_LEFT:
			accept_event()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_auto_fit = false
			var anchor := to_design(event.position)
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.02, 8)
			pan = event.position - anchor * zoom
			_update_transform()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_auto_fit = false
			_gesture = "pan" if event.pressed else ""
			_last = event.position
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin(event)
			else: _finish(event.position)
			accept_event()
	if event is InputEventMouseMotion:
		if _gesture.is_empty(): _update_resize_cursor(event.position)
		match _gesture:
			"resize":
				_resize_to(event.position)
			"pan":
				pan += event.position - _last
				_update_transform()
			"camera":
				camera -= event.relative / zoom
				update_sample()
				gesture_changed.emit()
			"move":
				var delta: Vector2 = (event.position - _start) / zoom
				if snap_enabled:
					delta = (_move_origin + delta).snapped(Vector2.ONE * grid_size) - _move_origin
				document.entry(_move_id).position = _move_origin + delta
				message = "移动 ΔX %.1f  ΔY %.1f" % [delta.x, delta.y]
				request_refresh()
				gesture_changed.emit()
		_last = event.position


func _begin(event: InputEventMouseButton) -> void:
	_start = event.position
	if preview:
		_gesture = "camera" if not handheld else ""
		return
	var handle := resize_handle_at(event.position)
	if handle >= 0:
		_before = document.snapshot()
		_resize_id = document.selected_id
		_resize_bounds = selection_bounds()
		_resize_scale = document.entry(_resize_id).uniform_scale
		var direction := RESIZE_HANDLES[handle]
		_resize_anchor = _resize_bounds.get_center() - direction * _resize_bounds.size * 0.5
		_resize_direction = direction * _resize_bounds.size
		_gesture = "resize"
		return
	var id := hit(event.position)
	document.selected_id = id
	if id < 0:
		_gesture = ""
		selection_changed.emit()
		return
	selection_changed.emit()
	_before = document.snapshot()
	_move_id = id
	_move_origin = document.entry(id).position
	_gesture = "move"


func _finish(point: Vector2) -> void:
	if _gesture == "resize":
		_resize_to(point)
		if not is_equal_approx(document.entry(_resize_id).uniform_scale, _resize_scale):
			document.commit("等比缩放素材", _before)
	elif _gesture == "move" and point.distance_to(_start) > 0.1:
		document.commit("移动素材", _before)
	_gesture = ""
	message = ""
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	queue_redraw()


func cancel_gesture() -> void:
	if _gesture in ["move", "resize"]: document.restore(_before)
	_gesture = ""
	message = ""
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	queue_redraw()


func _display_rect(id: int, near: Vector2) -> Rect2:
	var object := controller.get_configured_object(document.configured_index(id))
	if object == null: return Rect2()
	var pose := object.get_global_transform_with_canvas()
	var extent := entry_size(id)
	var origin := Vector2.ZERO
	if document.entry(id).infinite:
		origin = ((pose.affine_inverse() * near) / extent).floor() * extent
	return Rect2(pose * origin, extent * Vector2(pose.x.length(), pose.y.length()))


## 缩放只作用于单个未锁定素材。边缘固定对侧中点，角点固定对角，始终保持宽高比。
func resize_handle_at(point: Vector2) -> int:
	if preview or document.selected_entry() == null: return -1
	var id := document.selected_id
	if document.locked.has(id) or document.hidden.has(id): return -1
	var bounds := selection_bounds()
	var rectangle := Rect2(pan + bounds.position * zoom, bounds.size * zoom)
	for index in RESIZE_HANDLES.size():
		var location := rectangle.get_center() + RESIZE_HANDLES[index] * rectangle.size * 0.5
		if point.distance_to(location) <= 6: return index
	# 两个角点之间的整条边缘也能拖动。
	if point.y >= rectangle.position.y and point.y <= rectangle.end.y:
		if absf(point.x - rectangle.position.x) <= 4: return 4
		if absf(point.x - rectangle.end.x) <= 4: return 5
	if point.x >= rectangle.position.x and point.x <= rectangle.end.x:
		if absf(point.y - rectangle.position.y) <= 4: return 6
		if absf(point.y - rectangle.end.y) <= 4: return 7
	return -1


func _update_resize_cursor(point: Vector2) -> void:
	var handle := resize_handle_at(point)
	if handle < 0: mouse_default_cursor_shape = Control.CURSOR_CROSS
	elif handle in [0, 2]: mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	elif handle in [1, 3]: mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	elif handle in [4, 5]: mouse_default_cursor_shape = Control.CURSOR_HSIZE
	else: mouse_default_cursor_shape = Control.CURSOR_VSIZE


func _resize_to(point: Vector2) -> void:
	var delta := (point - _start) / zoom
	var factor := 1.0 + delta.dot(_resize_direction) / maxf(_resize_direction.length_squared(), 0.000001)
	factor = maxf(factor, 0.01 / _resize_scale)
	var value := document.entry(_resize_id)
	value.uniform_scale = _resize_scale * factor
	value.position = _resize_anchor + (_resize_bounds.position - _resize_anchor) * factor
	message = "等比缩放 %.1f%% · %.1f × %.1f" % [value.uniform_scale * 100.0, _resize_bounds.size.x * factor, _resize_bounds.size.y * factor]
	request_refresh()
	gesture_changed.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("20252e"))
	var canvas := Rect2(pan, Vector2(1920, 1080) * zoom)
	draw_rect(canvas, Color("333b48"))
	if viewport != null: draw_texture_rect(viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	draw_rect(canvas, Color("7b879b"), false)
	if document == null: return
	if snap_enabled and grid_size * zoom >= 8:
		var spacing := grid_size * zoom
		for x in range(int(fposmod(pan.x, spacing)), int(size.x), maxi(1, int(spacing))): draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.08))
		for y in range(int(fposmod(pan.y, spacing)), int(size.y), maxi(1, int(spacing))): draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.08))
	if references_visible:
		draw_line(pan + Vector2(0, 540) * zoom, pan + Vector2(1920, 540) * zoom, Color(0.9, 0.8, 0.5, 0.6))
		var labels := ["生者", "死者", "生钟", "死钟"]
		for index in document.references.size():
			var point := pan + document.references[index] * zoom
			draw_circle(point, 6, Color("d5bd83"), false, 1.5)
			draw_string(get_theme_default_font(), point + Vector2(9, -7), labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d5bd83"))
	var id := document.selected_id
	if document.selected_entry() != null and not document.hidden.has(id):
		var rectangle := _display_rect(id, get_local_mouse_position())
		if not preview:
			rectangle = Rect2(pan + document.entry(id).position * zoom, entry_size(id) * document.entry(id).uniform_scale * zoom)
		var color := Color("ffa978") if document.locked.has(id) else Color("63d9e8")
		draw_rect(rectangle, color, false, 2)
		if not preview and not document.locked.has(id):
			for handle in RESIZE_HANDLES:
				var location := rectangle.get_center() + handle * rectangle.size * 0.5
				draw_rect(Rect2(location - Vector2.ONE * 3.5, Vector2.ONE * 7), color)
		var origin := pan + document.entry(id).position * zoom
		draw_line(origin - Vector2(6, 0), origin + Vector2(6, 0), color, 2)
		draw_line(origin - Vector2(0, 6), origin + Vector2(0, 6), color, 2)
	if not message.is_empty(): draw_string(get_theme_default_font(), Vector2(15, size.y - 18), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not preview and data is Dictionary and data.get("type", "") == "files"


func _drop_data(position: Vector2, data: Variant) -> void:
	files_dropped.emit(PackedStringArray(data.files), to_design(position))
