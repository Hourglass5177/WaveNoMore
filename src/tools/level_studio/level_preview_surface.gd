class_name LevelPreviewSurface
extends Control
## 编辑手势与游戏画布分离；按真实预览变换拾取，松手才提交对象改动。
signal selection_changed(ids: PackedStringArray)
signal transform_committed(before: Array, after: Array)
signal candidate_changed(objects: Array)
signal asset_dropped(asset: String, position: Vector2)
var document: LevelDocument
var player: LevelShowPlayer
var viewport: SubViewport
var selected := PackedStringArray()
var mode := "move"
var grid_size := 10.0
var show_grid := true
var show_paths := true
var emissions := {}
var zoom := 1.0
var record_at_cursor := false
var pan := Vector2.ZERO
var _gesture := {}
var _candidate: Array = []
var _display_rect := Rect2()

func _ready() -> void:
	clip_contents = true; focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(320, 180)
	resized.connect(update_resolution)
	update_resolution.call_deferred()

func update_resolution() -> void:
	_update_display_rect()
	if not is_instance_valid(viewport):return
	# 渲染跟随物理像素，玩法与鼠标拾取继续使用 1920×1080 设计坐标。
	var physical_width:=minf(size.x,size.y*16.0/9.0)*get_window().content_scale_factor
	var width:=maxi(1920,ceili(physical_width/16.0)*16)
	viewport.size_2d_override=Vector2i(1920,1080);viewport.size_2d_override_stretch=true
	viewport.size=Vector2i(width,width*9/16)
	queue_redraw()

func _update_display_rect() -> void:
	var fit:=minf(size.x/1920.0,size.y/1080.0)*zoom
	_display_rect=Rect2((size-Vector2(1920,1080)*fit)*0.5+pan,Vector2(1920,1080)*fit)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b111b"))
	_update_display_rect()
	if is_instance_valid(viewport): draw_texture_rect(viewport.get_texture(), _display_rect, false)
	else: draw_rect(_display_rect, Color("253043"))
	if show_grid:
		for x in range(0, 1921, 120): draw_line(to_view(Vector2(x,0)), to_view(Vector2(x,1080)), Color(0.7,0.8,0.9,0.08))
		for y in range(0, 1081, 120): draw_line(to_view(Vector2(0,y)), to_view(Vector2(1920,y)), Color(0.7,0.8,0.9,0.08))
		draw_line(to_view(Vector2(0,1080)), to_view(Vector2(1920,0)), Color(0.7,0.8,0.9,0.25))
	if not is_instance_valid(player) or document == null: return
	for id in selected:
		var object_data := document.find("objects", id)
		if object_data.is_empty() or not player.objects.has(id): continue
		var transform: Transform2D = player.objects[id].transform
		var bounds := object_bounds(object_data)
		var corners := PackedVector2Array()
		for point in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.position]: corners.append(to_view(transform * point))
		draw_polyline(corners, Color("edd3a3"), 1.5, true)
		var pivot := to_view(transform.origin)
		draw_line(pivot - Vector2(9,0), pivot + Vector2(9,0), Color("f68b79"), 2)
		draw_line(pivot - Vector2(0,9), pivot + Vector2(0,9), Color("77c7b0"), 2)
		draw_circle(pivot, 3, Color.WHITE)
		if mode == "rotate": draw_arc(pivot, 42, 0, TAU, 48, Color("edd3a3"), 1.5, true)
		if mode == "scale":
			for point in corners: draw_rect(Rect2(point - Vector2(4,4), Vector2(8,8)), Color("edd3a3"))
		if show_paths:
			for path:Dictionary in emissions.values():
				if path.object_id!=id or absi(int(path.release_us)-player.current_us)>3000000:continue
				var points:=PackedVector2Array()
				for step in 65:points.append(to_view(BossEmissionPath.sample(path,roundi(float(path.duration_us)*step/64.0)).position))
				draw_polyline(points,Color(0.4,0.85,0.75,0.7),1.5,true)
			for track: Dictionary in player.show.get("tracks", []):
				if track.object_id != id or track.property != "position" or track.section != player.current_section or track.keys.size() < 2: continue
				var points := PackedVector2Array()
				var start := int(track.keys.front().time_us); var end := int(track.keys.back().time_us)
				for index in 65:
					var pose := LevelShowSampler.object_transform(player.show, id, player.current_section, start + (end - start) * index / 64, player.difficulty)
					points.append(to_view(pose.origin))
				draw_polyline(points, Color(0.9,0.75,0.4,0.65), 1.5, true)
			if player.assets.entries.has(object_data.asset):
				for anchor: String in player.assets.entries[object_data.asset].anchors:
					var point := to_view(player.anchor_at(id, anchor, player.current_section, player.current_us))
					draw_circle(point, 4, Color("a4e3d6"), false, 1.5)
					draw_string(get_theme_default_font(), point + Vector2(6,-5), anchor, HORIZONTAL_ALIGNMENT_LEFT, 100, 11, Color("a4e3d6"))
	if _gesture.get("mode", "") == "box": draw_rect(Rect2(_gesture.origin, _gesture.current - _gesture.origin).abs(), Color(0.5,0.7,1,0.2))

func to_view(point: Vector2) -> Vector2: return _display_rect.position + point * (_display_rect.size.x / 1920.0)
func to_world(point: Vector2) -> Vector2: return (point - _display_rect.position) / maxf(_display_rect.size.x / 1920.0, 0.001)

func object_bounds(object_data: Dictionary) -> Rect2:
	if is_instance_valid(player) and player.assets.entries.has(object_data.asset): return player.assets.entries[object_data.asset].visual_bounds
	if object_data.type == "text":
		var extent := LevelFormat.vec(object_data.fields.get("size", [560,100])); return Rect2(-extent * 0.5, extent)
	if is_instance_valid(player):
		var texture := player.assets.resolve(str(object_data.asset)) as Texture2D
		if texture != null: return Rect2(-texture.get_size() * 0.5, texture.get_size())
	return Rect2(-64,-64,128,128)

func _gui_input(event: InputEvent) -> void:
	if document == null or not is_instance_valid(player): return
	if event is InputEventPanGesture:
		if _gesture.is_empty(): pan -= event.delta*32; queue_redraw()
		accept_event(); return
	if event is InputEventMouseButton:
		if event.pressed: grab_focus()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT] and event.pressed:
			if not _gesture.is_empty(): accept_event(); return
			var vertical: bool = event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]
			var amount: float=(-1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_LEFT] else 1)*event.factor
			if vertical and event.ctrl_pressed:
				var anchor:=to_world(event.position)
				zoom=clampf(zoom*pow(1.15,-amount),0.25,5)
				_update_display_rect(); pan+=event.position-to_view(anchor)
			else: pan-=Vector2(0,amount*48) if vertical else Vector2(amount*100,0)
			_update_display_rect(); queue_redraw(); accept_event(); return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and _gesture.is_empty(): _gesture={"mode":"pan","origin":event.position,"pan":pan}
			elif not event.pressed and _gesture.get("mode","")=="pan": _gesture.clear()
			accept_event(); return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		if not event.pressed:
			if not _candidate.is_empty():
				var before: Array = _gesture.before; var after := _candidate.duplicate(true)
				_candidate.clear(); _gesture.clear(); candidate_changed.emit([]); transform_committed.emit(before, after)
			_gesture.clear(); queue_redraw(); return
		var hit := ""
		var point := to_world(event.position)
		var objects := document.entries("objects").duplicate()
		objects.sort_custom(func(a,b):
			var za: int=player.objects[a.id].z_index if player.objects.has(a.id) else 0
			var zb: int=player.objects[b.id].z_index if player.objects.has(b.id) else 0
			return za<zb if za!=zb else document.entries("objects").find(a)<document.entries("objects").find(b))
		for index in range(objects.size() - 1, -1, -1):
			var object_data: Dictionary = objects[index]
			if not document.editable_object(object_data.id) or not player.objects.has(object_data.id): continue
			var node: Node2D = player.objects[object_data.id]
			if not node.visible or is_zero_approx(node.transform.determinant()): continue
			if object_bounds(object_data).has_point(node.transform.affine_inverse() * point): hit = object_data.id; break
		if hit.is_empty():
			if not (event.shift_pressed or event.ctrl_pressed): selected.clear(); selection_changed.emit(selected)
			_gesture = {"mode": "box", "origin": event.position, "current": event.position, "previous": selected.duplicate(),"pan":pan,"zoom":zoom}
		else:
			if event.ctrl_pressed or event.shift_pressed:
				if hit in selected: selected.remove_at(selected.find(hit))
				else: selected.append(hit)
				selection_changed.emit(selected); queue_redraw(); return
			elif not hit in selected: selected = PackedStringArray([hit])
			selection_changed.emit(selected)
			var before := []
			for id in selected:
				var object_data := document.find("objects", id)
				if document.editable_object(id) and not _has_selected_parent(object_data):
					var entry:=object_data.duplicate(true)
					if record_at_cursor:entry.fields=LevelShowSampler.object_state(player.show,object_data,player.current_section,player.current_us,player.difficulty)
					before.append(entry)
			_gesture = {"mode": mode, "origin": event.position, "world": point, "before": before, "pivot": player.objects[hit].position,"pan":pan,"zoom":zoom,"moved":false}
		queue_redraw()
	elif event is InputEventMouseMotion and not _gesture.is_empty():
		var point := to_world(event.position)
		if _gesture.has("moved"):
			_gesture.moved=_gesture.moved or event.position.distance_to(_gesture.origin)>=6
			if not _gesture.moved: return
		if _gesture.mode == "pan": pan = _gesture.pan + event.position - _gesture.origin
		elif _gesture.mode == "box":
			_gesture.current = event.position; selected = _gesture.previous.duplicate()
			var box := Rect2(to_world(_gesture.origin), point - to_world(_gesture.origin)).abs()
			for object_data: Dictionary in document.entries("objects"):
				if not document.editable_object(object_data.id) or not player.objects.has(object_data.id): continue
				if box.intersects(player.objects[object_data.id].transform * object_bounds(object_data)) and not object_data.id in selected: selected.append(object_data.id)
			selection_changed.emit(selected)
		else:
			_candidate = _gesture.before.duplicate(true)
			var delta: Vector2 = point - _gesture.world
			for object_data: Dictionary in _candidate:
				var local_delta := delta
				var parent := str(object_data.parent_id)
				var transform := Transform2D.IDENTITY
				if not parent.is_empty(): transform = LevelShowSampler.object_transform(player.show, parent, player.current_section, player.current_us, player.difficulty)
				elif object_data.layer == "death": transform = Transform2D(PI, Vector2(1920,1080))
				local_delta = transform.basis_xform_inv(delta)
				if object_data.layer!="hud":local_delta/=maxf(player.camera_zoom,0.01)
				match str(_gesture.mode):
					"move":
						var position := LevelFormat.vec(object_data.fields.position) + local_delta
						if grid_size > 0 and not event.alt_pressed: position = position.snapped(Vector2.ONE * grid_size)
						object_data.fields.position = [position.x, position.y]
					"rotate":
						var angle := rad_to_deg((point - _gesture.pivot).angle() - (_gesture.world - _gesture.pivot).angle())
						object_data.fields.rotation = float(object_data.fields.rotation) + (snappedf(angle, 15) if event.shift_pressed else angle)
					"scale":
						var factor := maxf(0.05, point.distance_to(_gesture.pivot) / maxf(1, _gesture.world.distance_to(_gesture.pivot)))
						var value := LevelFormat.vec(object_data.fields.scale) * factor
						object_data.fields.scale = [value.x, value.y]
			candidate_changed.emit(_candidate)
		queue_redraw(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: cancel_drag(); accept_event()

func cancel_drag() -> void:
	if _gesture.is_empty() and _candidate.is_empty(): return
	if _gesture.has("pan"): pan=_gesture.pan
	if _gesture.has("zoom"): zoom=_gesture.zoom
	_gesture.clear(); _candidate.clear(); candidate_changed.emit([]); queue_redraw()

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("level_asset")

func _drop_data(position: Vector2, data: Variant) -> void:
	asset_dropped.emit(str(data.level_asset), to_world(position))

func _has_selected_parent(object_data: Dictionary) -> bool:
	var parent := str(object_data.parent_id)
	while not parent.is_empty():
		if parent in selected: return true
		parent=str(document.find("objects",parent).get("parent_id",""))
	return false

func frame_selection() -> void:
	if selected.is_empty() or not is_instance_valid(player): return
	var bounds := Rect2(); var first := true
	for id in selected:
		if not player.objects.has(id): continue
		var box: Rect2=player.objects[id].transform*object_bounds(document.find("objects",id))
		bounds=box if first else bounds.merge(box); first=false
	if first: return
	zoom=clampf(minf(size.x/maxf(1,bounds.size.x+100),size.y/maxf(1,bounds.size.y+100))/minf(size.x/1920,size.y/1080),0.25,5)
	pan=Vector2.ZERO; _update_display_rect(); pan=size*0.5-to_view(bounds.get_center()); _update_display_rect(); queue_redraw()
