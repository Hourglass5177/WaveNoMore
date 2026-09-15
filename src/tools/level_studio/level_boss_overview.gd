extends AcceptDialog
## 浏览和筛选不更改选区或绑定；写入只由明确的加入按钮触发。
var workspace
var selected_id:=""
var records: Array[Dictionary]=[]

func _ready() -> void:
	%Filter.item_selected.connect(func(_index):refresh())
	%Search.text_changed.connect(func(_text):refresh())
	%Notes.item_selected.connect(func(index):selected_id=str(%Notes.get_item_metadata(index));_details())
	%Notes.item_activated.connect(func(_index):_locate())
	%Locate.pressed.connect(_locate)
	%Previous.pressed.connect(func():_neighbor(-1));%Next.pressed.connect(func():_neighbor(1))
	%Add.pressed.connect(func():hide();workspace._add_boss_reference(selected_id);queue_free())
	%Source.pressed.connect(func():
		var record:=_selected()
		if record.is_empty() or record.owners.is_empty():return
		var binding: Dictionary=record.owners[0];hide()
		workspace.select_objects(PackedStringArray([str(binding.object_id)]));workspace.open_boss_binding(str(binding.id));queue_free())
	confirmed.connect(queue_free);close_requested.connect(queue_free)
	refresh()

func refresh() -> void:
	records=LevelBossReference.collect(workspace);%Notes.clear()
	%Summary.text="当前难度：%s · BOSS 音符 %d · 未绑定 %d · 失效关联 %d"%[workspace.difficulty(),records.filter(func(item):return item.time_us>=0).size(),records.filter(func(item):return item.status=="未绑定").size(),records.filter(func(item):return item.status=="失效关联").size()]
	for record in records:
		if %Filter.selected>0 and record.status!=%Filter.get_item_text(%Filter.selected):continue
		var caption:=LevelBossReference.describe(record,workspace.document)
		if not %Search.text.is_empty() and not %Search.text.to_lower() in caption.to_lower():continue
		var index: int=%Notes.add_item(caption.replace("\n"," · "));%Notes.set_item_metadata(index,record.id);%Notes.set_item_custom_fg_color(index,LevelBossReference.COLORS[record.status])
		%Notes.set_item_tooltip(index,caption)
		if record.id==selected_id:%Notes.select(index);%Notes.ensure_current_is_visible()
	_details()

func _selected() -> Dictionary:
	if %Notes.get_selected_items().is_empty():return {}
	for record in records:
		if record.id==selected_id:return record
	return {}

func _details() -> void:
	var record:=_selected()
	%Details.text="先导入歌曲与谱面。" if workspace.song_document.charts.is_empty() else ("选择音符查看详情；双击仅定位，不修改绑定。" if record.is_empty() else LevelBossReference.describe(record,workspace.document))
	%Locate.disabled=record.is_empty() or record.get("time_us",-1)<0
	%Source.disabled=record.is_empty() or record.get("owners",[]).is_empty()
	var target: Dictionary=workspace.document.find("objects",workspace.selection[0]) if workspace.selection.size()==1 else {}
	%Add.disabled=%Locate.disabled or target.get("type","") not in ["actor","animated_sprite"]
	%Add.text="加入绑定："+str(target.get("name","")) if not %Add.disabled else "加入绑定（请先选中一个 BOSS 对象）"
	%Add.tooltip_text="将此音符加入所选对象的当前绑定；无当前绑定时创建草稿。已有来源绑定不会自动移除。"
	var available:=_visible_timed()
	%Previous.disabled=not available.any(func(item):return item.time_us<workspace.time_us)
	%Next.disabled=not available.any(func(item):return item.time_us>workspace.time_us)

func _visible_timed() -> Array:
	var ids:=[]
	for index in %Notes.item_count:ids.append(str(%Notes.get_item_metadata(index)))
	return records.filter(func(item):return item.id in ids and item.time_us>=0)

func _locate() -> void:
	var record:=_selected()
	if not record.is_empty() and record.time_us>=0:workspace._locate_boss_reference(record.id);_details()

func _neighbor(direction: int) -> void:
	var available:=_visible_timed()
	if direction<0:available.reverse()
	for record in available:
		if (int(record.time_us)-workspace.time_us)*direction>0:
			selected_id=record.id;refresh();_locate();return
