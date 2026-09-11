@tool
extends RefCounted
## 独立编辑草稿和撤销历史。条目复制，纹理与动画资源只读共享；会话状态不写入 .tres。

signal changed
var items: Array[Dictionary] = []
## 唯一选中素材 ID；-1 表示无选中对象。
var selected_id: int = -1
var hidden: Dictionary = {}
var locked: Dictionary = {}
var history := UndoRedo.new()
var source_path := ""
var background_path := ""
var stage_path := ""
var needs_link := false
var references: Array[Vector2] = [Vector2(270, 235), Vector2(1650, 845), Vector2(350, 280), Vector2(1570, 800)]
var _next_id := 1
var _saved: Array = []
var _watched: Dictionary = {}
var _asset_times: Dictionary = {}


func _notification(what: int) -> void:
	# UndoRedo 继承 Object，需要显式释放；其回调使用弱引用，不延长文档寿命。
	if what == NOTIFICATION_PREDELETE:
		history.free()


## 从关卡入口或独立背景资源打开。失败不覆盖当前草稿。
func open(path: String) -> String:
	var resource := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	var definition: StageBackgroundDefinition
	var target := path
	var stage_file := ""
	var link := false
	var markers: Array[Vector2] = [Vector2(270, 235), Vector2(1650, 845), Vector2(350, 280), Vector2(1570, 800)]
	if resource is StageDefinition:
		stage_file = path
		definition = resource.background
		target = resource.background_resource_path
		if definition != null:
			target = definition.resource_path
			if target.is_empty() or target.contains("::"):
				target = path.get_base_dir().path_join("stage_background.tres")
				if FileAccess.file_exists(target): return "内嵌背景的另存位置已存在，请先为关卡指定独立背景资源。"
				link = true
			else:
				definition = ResourceLoader.load(target, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as StageBackgroundDefinition
				if definition == null: return "无法读取指定的背景资源。"
		elif not target.is_empty():
			definition = ResourceLoader.load(target, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as StageBackgroundDefinition
			if definition == null:
				return "无法读取指定的背景资源。"
		else:
			target = path.get_base_dir().path_join("stage_background.tres")
			if FileAccess.file_exists(target):
				return "同目录已有未挂接的 stage_background.tres，请先在关卡资源中挂接。"
			link = true
		var rules: GameplayRuleSet = resource.rule_set
		if rules == null and not resource.rule_set_resource_path.is_empty():
			rules = load(resource.rule_set_resource_path) as GameplayRuleSet
		if rules != null:
			markers[2] = rules.life_wave_origin
			markers[3] = rules.death_wave_origin
	elif resource is StageBackgroundDefinition:
		definition = resource
	else:
		return "请选择 StageDefinition 或 StageBackgroundDefinition 资源。"
	items.clear()
	selected_id = -1
	hidden.clear()
	locked.clear()
	history.clear_history()
	if definition != null:
		for entry in definition.entries:
			items.append({"id": _next_id, "entry": entry.duplicate(false) if entry != null else StageBackgroundEntry.new()})
			_next_id += 1
	source_path = path
	background_path = target
	stage_path = stage_file
	needs_link = link
	references = markers
	_saved = signature()
	acknowledge_external()
	changed.emit()
	return ""


## 获取可交给运行时装配或保存的独立资源，不包含选中、隐藏、锁定状态。
func definition() -> StageBackgroundDefinition:
	var result := StageBackgroundDefinition.new()
	for item in items:
		result.entries.append(item.entry.duplicate(false))
	return result


func index_of(id: int) -> int:
	for index in items.size():
		if items[index].id == id: return index
	return -1


func entry(id: int) -> StageBackgroundEntry:
	var index := index_of(id)
	return items[index].entry if index >= 0 else null


func selected_entry() -> StageBackgroundEntry:
	return entry(selected_id)


func editable_entry() -> StageBackgroundEntry:
	return null if locked.has(selected_id) else selected_entry()


## 前到后排序：较小深度在前，同深度数组后项在前。
func front_ids() -> Array[int]:
	var indices: Array[int] = []
	for index in items.size(): indices.append(index)
	indices.sort_custom(func(a: int, b: int):
		return items[a].entry.depth < items[b].entry.depth if items[a].entry.depth != items[b].entry.depth else a > b)
	var result: Array[int] = []
	for index in indices: result.append(items[index].id)
	return result


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items: result.append({"id": item.id, "entry": item.entry.duplicate(false)})
	return result


func signature() -> Array:
	var result: Array = []
	for item in items:
		var value: StageBackgroundEntry = item.entry
		result.append([value.texture, value.sprite_frames, value.animation, value.depth, value.infinite, value.position, value.uniform_scale, value.material])
	return result


func is_dirty() -> bool:
	return signature() != _saved


## 一次手势或属性提交对应一次撤销；拖动过程中只更改草稿，结束后调用此方法。
func commit(label: String, before: Array[Dictionary]) -> void:
	history.create_action(label)
	# 撤销栈只持有弱引用，避免文档与 UndoRedo 的回调构成引用环。
	history.add_do_method(_apply_weak.bind(weakref(self), snapshot()))
	history.add_undo_method(_apply_weak.bind(weakref(self), before))
	history.commit_action()


static func _apply_weak(reference: WeakRef, state: Array[Dictionary]) -> void:
	var document = reference.get_ref()
	if document != null: document._apply(state)


func _apply(state: Array[Dictionary]) -> void:
	items.clear()
	for item in state: items.append({"id": item.id, "entry": item.entry.duplicate(false)})
	if index_of(selected_id) < 0: selected_id = -1
	changed.emit()


func restore(state: Array[Dictionary]) -> void:
	_apply(state)


## 添加只引用项目内美术资源的条目。新条目位于指定设计坐标。
func add_asset(resource: Resource, position: Vector2) -> bool:
	if not resource is Texture2D and not resource is SpriteFrames: return false
	var before := snapshot()
	var value := StageBackgroundEntry.new()
	assign_asset(value, resource)
	value.position = position
	items.append({"id": _next_id, "entry": value})
	selected_id = _next_id
	_next_id += 1
	commit("添加素材", before)
	return true


func assign_asset(value: StageBackgroundEntry, resource: Resource) -> void:
	value.texture = resource as Texture2D
	value.sprite_frames = resource as SpriteFrames
	if value.sprite_frames != null and not value.sprite_frames.has_animation(value.animation):
		var names := value.sprite_frames.get_animation_names()
		value.animation = names[0] if not names.is_empty() else &"default"


func duplicate_selected() -> void:
	var source := editable_entry()
	if source == null: return
	var before := snapshot()
	items.append({"id": _next_id, "entry": source.duplicate(false)})
	selected_id = _next_id
	_next_id += 1
	commit("复制素材", before)


func delete_selected() -> void:
	if editable_entry() == null: return
	var before := snapshot()
	items.remove_at(index_of(selected_id))
	selected_id = -1
	commit("删除素材", before)


## 只移动指定的一件素材到目标深度与位置。
func reorder(id: int, depth: int, target_id: int = -1, in_front: bool = true) -> void:
	if index_of(id) < 0 or locked.has(id) or id == target_id: return
	var before := snapshot()
	var moving := items[index_of(id)]
	items.remove_at(index_of(id))
	moving.entry.depth = depth
	var target := index_of(target_id)
	var at := items.size() if target < 0 else target + (1 if in_front else 0)
	items.insert(at, moving)
	commit("调整层次", before)


## 保存前逐项校验；无限动画必须等画布，任何无效条目都给出所在序号。
func validation_error() -> String:
	for index in items.size():
		var value: StageBackgroundEntry = items[index].entry
		var issue := ""
		if not is_finite(value.uniform_scale) or value.uniform_scale < 0.01:
			return "条目 %d：缩放倍率必须至少为 0.01" % (index + 1)
		if (value.texture == null) == (value.sprite_frames == null):
			issue = "必须选择一项纹理或动画资源"
		elif value.sprite_frames != null:
			var frames := value.sprite_frames
			if not frames.has_animation(value.animation) or frames.get_frame_count(value.animation) == 0:
				issue = "动画不存在或没有帧"
			else:
				var size := Vector2.ZERO
				for frame in frames.get_frame_count(value.animation):
					var image := frames.get_frame_texture(value.animation, frame)
					if image == null:
						issue = "动画包含空帧"
						break
					if value.infinite and frame > 0 and image.get_size() != size: issue = "无限动画的帧画布必须等大"
					size = image.get_size()
		if not issue.is_empty(): return "条目 %d：%s" % [index + 1, issue]
	return ""


## 检查文件内容变化，不做哈希；外部变化须由工作区先让用户选择。
func external_changed() -> bool:
	for path: String in _watched:
		var content := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		if content != _watched[path]: return true
	for path: String in _asset_times:
		if FileAccess.get_modified_time(path) != _asset_times[path]: return true
	return false


func acknowledge_external() -> void:
	_watched.clear()
	_asset_times.clear()
	for path in [source_path, background_path]:
		if not path.is_empty(): _watched[path] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	for item in items:
		var material: ShaderMaterial = item.entry.material
		for resource: Resource in [item.entry.texture, item.entry.sprite_frames, material, material.shader if material != null else null]:
			if resource != null and not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
				_asset_times[resource.resource_path] = FileAccess.get_modified_time(resource.resource_path)


## 用户明确要求重新载入时刷新素材缓存，随后重新打开背景草稿。
func reload_assets() -> void:
	for path: String in _asset_times:
		ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE)


## 保存 .tres。首次挂接只修改关卡 [resource] 的背景字段，不重新序列化关卡依赖。
func save() -> String:
	var issue := validation_error()
	if not issue.is_empty(): return issue
	if background_path.is_empty(): return "请先打开关卡或背景资源。"
	var link_text := ""
	if needs_link:
		link_text = FileAccess.get_file_as_string(stage_path)
		var at := link_text.find("[resource]")
		if at < 0: return "关卡不是可编辑的文本资源。"
		var head := link_text.substr(0, at)
		var lines := link_text.substr(at).split("\n")
		var body := PackedStringArray()
		for line in lines:
			if not line.begins_with("background =") and not line.begins_with("background_resource_path ="): body.append(line)
		link_text = head + "\n".join(body).strip_edges() + "\nbackground_resource_path = " + JSON.stringify(background_path) + "\n"
	var error := ResourceSaver.save(definition(), background_path)
	if error != OK: return "背景保存失败：%s" % error_string(error)
	if needs_link:
		var file := FileAccess.open(stage_path, FileAccess.WRITE)
		if file == null: return "背景已保存，但关卡挂接失败。请重试保存。"
		file.store_string(link_text)
		file.close()
		needs_link = false
	_saved = signature()
	acknowledge_external()
	changed.emit()
	return ""
