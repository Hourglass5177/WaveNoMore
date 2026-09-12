class_name LevelDocument
extends RefCounted
## 历史只保存本次操作涉及的条目；选区、游标与尚未提交的拖动属于视图。
signal changed(kind: String)
var data: Dictionary = LevelFormat.new_level()
var directory := ""
var dirty := false
var revision := 0
var history: Array[Dictionary] = []
var cursor := 0
var saved_cursor := 0
var clipboard: Dictionary = {}
var last_changes: Array = []
var editing := false
var _edit_changes: Array = []
var _edit_label := ""


func reset(next: Dictionary, path := "") -> void:
	data = next.duplicate(true); directory = path; history.clear(); cursor = 0; saved_cursor = 0; dirty = false; revision += 1
	changed.emit("project")

func entries(kind: String) -> Array:
	return data.show[kind]

func find(kind: String, entry_id: String) -> Dictionary:
	return LevelFormat.find(entries(kind), entry_id)

func replace(label: String, kind: String, before: Array, after: Array) -> void:
	commit(label, [{"kind": kind, "before": before.duplicate(true), "after": after.duplicate(true)}])

func fields(label: String, values: Dictionary) -> void:
	var before := {}
	for key in values: before[key] = data.get(key)
	commit(label, [{"kind": "metadata", "before": before, "after": values.duplicate(true)}])

func commit(label: String, changes: Array) -> void:
	changes=changes.filter(func(change): return change.before!=change.after)
	if changes.is_empty(): return
	if editing:
		_edit_label=label
		# 一个字段手势只保留首次旧值和末次新值，预览不占撤销历史。
		for change: Dictionary in changes:
			var merged := false
			for previous: Dictionary in _edit_changes:
				if previous.kind==change.kind and (change.kind=="metadata" or previous.after.map(func(item):return item.id)==change.before.map(func(item):return item.id)):
					if change.kind=="metadata":
						for key: String in change.before:
							if not previous.before.has(key): previous.before[key]=change.before[key]
						previous.after.merge(change.after.duplicate(true),true)
					else: previous.after=change.after.duplicate(true)
					merged=true; break
			if not merged: _edit_changes.append(change.duplicate(true))
		_apply(changes,false); return
	# 仅记录被修改条目的位置，删除后撤销仍能恢复对象与轨道的原始顺序。
	for change: Dictionary in changes:
		if change.kind == "metadata": continue
		var positions := {}
		var collection: Array = entries(change.kind)
		for entry: Dictionary in change.before:
			positions[entry.id] = collection.find(find(change.kind, entry.id))
		change["before_positions"] = positions
	if cursor < history.size() and saved_cursor > cursor: saved_cursor = -1
	history.resize(cursor); history.append({"label": label, "changes": changes}); cursor += 1
	_apply(changes, false)

func undo(redo := false) -> void:
	if (redo and cursor == history.size()) or (not redo and cursor == 0): return
	var command: Dictionary = history[cursor if redo else cursor - 1]
	cursor += 1 if redo else -1
	_apply(command.changes, not redo)

func _apply(changes: Array, reverse: bool) -> void:
	for change: Dictionary in changes:
		var before = change.after if reverse else change.before
		var after = change.before if reverse else change.after
		if change.kind == "metadata": data.merge(after.duplicate(true), true); continue
		var collection: Array = entries(change.kind)
		var removed := {}
		for entry: Dictionary in before: removed[entry.id] = true
		var updated := {}
		for entry: Dictionary in after: updated[entry.id] = entry
		var next := []
		for entry: Dictionary in collection:
			if updated.has(entry.id): next.append(updated[entry.id].duplicate(true)); updated.erase(entry.id)
			elif not removed.has(entry.id): next.append(entry)
		var additions: Array = updated.values()
		if reverse:
			additions.sort_custom(func(a, b): return int(change.get("before_positions",{}).get(a.id, next.size())) < int(change.get("before_positions",{}).get(b.id, next.size())))
		for entry: Dictionary in additions:
			var index: int = int(change.get("before_positions",{}).get(entry.id, next.size())) if reverse else next.size()
			next.insert(clampi(index, 0, next.size()), entry.duplicate(true))
		if change.kind=="tracks":
			for track:Dictionary in next:track.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
		data.show[change.kind] = next
	last_changes=changes.duplicate(true)
	revision += 1; dirty = cursor != saved_cursor; changed.emit("preview" if editing else "edit")

func mark_saved() -> void:
	saved_cursor = cursor; dirty = false; changed.emit("saved")

func add_object(kind: String, asset := "") -> String:
	var object_data := LevelFormat.object(kind, asset)
	replace("添加" + object_data.name, "objects", [], [object_data]); return object_data.id

func set_key(object_id: String, property: String, section: String, time_us: int, value, difficulty := "") -> void:
	var target := {}
	for track_data: Dictionary in entries("tracks"):
		if track_data.object_id == object_id and track_data.property == property and track_data.section == section and track_data.type == "property" and track_data.difficulties == ([] if difficulty.is_empty() else [difficulty]): target = track_data; break
	var before := [] if target.is_empty() else [target.duplicate(true)]
	if target.is_empty(): target = LevelFormat.track(object_id, property, section); target.difficulties = [] if difficulty.is_empty() else [difficulty]
	else: target = target.duplicate(true)
	var existing := -1
	for i in target.keys.size():
		if int(target.keys[i].time_us) == time_us: existing = i; break
	if existing < 0: target.keys.append(LevelFormat.key(time_us, value))
	else: target.keys[existing].value = value
	target.keys.sort_custom(func(a, b): return int(a.time_us) < int(b.time_us))
	replace("设置关键帧", "tracks", before, [target])

func delete_objects(ids: PackedStringArray) -> void:
	var removed := {}
	for entry_id in ids: removed[entry_id] = true
	# 删除分组一并删除其成员，撤销时所有引用原样恢复。
	for pass_index in entries("objects").size():
		for object_data: Dictionary in entries("objects"):
			if removed.has(object_data.get("parent_id", "")): removed[object_data.id] = true
	var changes := []
	for kind in ["objects", "tracks", "bindings"]:
		var before := entries(kind).filter(func(entry): return removed.has(entry.id if kind == "objects" else entry.get("object_id", "")))
		if not before.is_empty(): changes.append({"kind": kind, "before": before.duplicate(true), "after": []})
	if not changes.is_empty(): commit("删除对象", changes)

func copy_objects(ids: PackedStringArray) -> void:
	ids=ids.duplicate()
	for pass_index in entries("objects").size():
		for object_data:Dictionary in entries("objects"):
			if object_data.get("parent_id","") in ids and not object_data.id in ids:ids.append(object_data.id)
	clipboard = {"objects": [], "tracks": []}
	for object_data: Dictionary in entries("objects"):
		if object_data.id in ids: clipboard.objects.append(object_data.duplicate(true))
	for track_data: Dictionary in entries("tracks"):
		if track_data.object_id in ids: clipboard.tracks.append(track_data.duplicate(true))

func paste_objects(mirror := false) -> PackedStringArray:
	var objects := []; var tracks := []; var remap := {}; var result := PackedStringArray()
	for source: Dictionary in clipboard.get("objects", []):
		var entry := source.duplicate(true); entry.id = LevelFormat.id("object"); remap[source.id] = entry.id; result.append(entry.id)
		entry.name += " · 对称" if mirror else " · 副本"
		if mirror and not source.get("parent_id", "") in clipboard.objects.map(func(object_data):return object_data.id):
			entry.fields.position = [1920.0 - float(entry.fields.position[0]), 1080.0 - float(entry.fields.position[1])]
			if entry.layer != "hud": entry.fields.rotation = float(entry.fields.rotation) + 180.0
		objects.append(entry)
	for entry: Dictionary in objects:
		var parent:=str(entry.get("parent_id",""))
		# 单独复制组内对象时保留原父组，避免局部坐标突然变成画布坐标。
		entry.parent_id=remap.get(parent,parent if not find("objects",parent).is_empty() else "")
	for source: Dictionary in clipboard.get("tracks", []):
		var entry := source.duplicate(true); entry.id = LevelFormat.id("track"); entry.object_id = remap[source.object_id]
		for key_data: Dictionary in entry.keys:
			key_data.id = LevelFormat.id("key")
			var source_object:=LevelFormat.find(clipboard.objects,source.object_id)
			var mirror_root:bool=mirror and not source_object.get("parent_id","") in clipboard.objects.map(func(object_data):return object_data.id)
			if mirror_root and entry.property == "position": key_data.value = [1920.0 - float(key_data.value[0]), 1080.0 - float(key_data.value[1])]
			if mirror_root and entry.property == "rotation" and source_object.layer!="hud":key_data.value=float(key_data.value)+180.0
		for clip_data: Dictionary in entry.clips: clip_data.id = LevelFormat.id("clip")
		tracks.append(entry)
	if not objects.is_empty(): commit("对称复制" if mirror else "粘贴对象", [{"kind": "objects", "before": [], "after": objects}, {"kind": "tracks", "before": [], "after": tracks}])
	return result

func editable_object(id: String) -> bool:
	# 隐藏、锁定的父组同样约束其成员。
	var entry := find("objects",id)
	while not entry.is_empty():
		if entry.locked or entry.hidden: return false
		entry=find("objects",str(entry.parent_id))
	return true

func begin_edit() -> void:
	if editing: return
	editing=true; _edit_changes.clear()

func end_edit(cancel := false) -> void:
	if not editing: return
	var changes := _edit_changes.duplicate(true)
	# 先回到手势起点，再沿用普通命令记录位置和保存游标。
	if not changes.is_empty(): _apply(changes,true)
	editing=false; _edit_changes.clear()
	if not cancel and not changes.is_empty(): commit(_edit_label,changes)
	elif cancel: changed.emit("edit")
