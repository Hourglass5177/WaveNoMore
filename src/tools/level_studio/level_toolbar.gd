extends HFlowContainer
## 保留原按钮及信号，窄窗口仅把可菜单化操作映射到所属工具组的“更多”。
var _more := MenuButton.new()
var _queued := false
var _arranging := false

func _ready() -> void:
	_more.text="更多";_more.tooltip_text="当前工具组的其他操作";add_child(_more);_more.hide()
	resized.connect(_queue)
	child_entered_tree.connect(func(_child):_queue())
	_queue()

func _queue() -> void:
	if _queued or _arranging:return
	_queued=true;_arrange.call_deferred()

func _arrange() -> void:
	_queued=false;_arranging=true
	var buttons:=[];var occupied:=0.0;var gap:=get_theme_constant("h_separation")
	for child in get_children():
		if child==_more or not child is Control:continue
		if child is BaseButton and not child.has_meta("keep_hidden"):
			buttons.append(child);child.show()
		if child.visible:occupied+=child.get_combined_minimum_size().x+gap
	var popup:=_more.get_popup();popup.clear()
	for child in popup.get_children():child.queue_free()
	_more.visible=occupied>size.x
	if _more.visible:
		occupied+=_more.get_combined_minimum_size().x+gap
		buttons.reverse()
		for button: BaseButton in buttons:
			if occupied<=size.x:break
			if button.text in ["播放","暂停","保存","在游戏中试玩","移动","旋转","缩放"]:continue
			occupied-=button.get_combined_minimum_size().x+gap;button.hide()
			if button is MenuButton:
				var menu:=PopupMenu.new();menu.name="Group"+str(popup.item_count);popup.add_child(menu)
				var source: PopupMenu=button.get_popup()
				_copy_menu(menu,source)
				menu.id_pressed.connect(func(id):source.id_pressed.emit(id);source.index_pressed.emit(source.get_item_index(id)))
				menu.about_to_popup.connect(func():
					source.about_to_popup.emit()
					_copy_menu(menu,source))
				popup.add_submenu_item(button.text,menu.name)
			elif button is OptionButton:
				var menu:=PopupMenu.new();menu.name="Choice"+str(popup.item_count);popup.add_child(menu)
				for index in button.item_count:
					menu.add_radio_check_item(button.get_item_text(index),index);menu.set_item_checked(index,index==button.selected)
				menu.id_pressed.connect(func(index):button.select(index);button.item_selected.emit(index))
				menu.about_to_popup.connect(func():
					for index in button.item_count:menu.set_item_checked(index,index==button.selected))
				popup.add_submenu_item(button.tooltip_text if not button.tooltip_text.is_empty() else button.text,menu.name)
			else:
				var id:=popup.item_count
				if button.toggle_mode:popup.add_check_item(button.text,id);popup.set_item_checked(id,button.button_pressed)
				else:popup.add_item(button.text,id)
				popup.set_item_disabled(id,button.disabled);popup.set_item_tooltip(id,button.tooltip_text)
				popup.set_item_metadata(id,button)
	if not popup.id_pressed.is_connected(_activate):popup.id_pressed.connect(_activate)
	if not popup.about_to_popup.is_connected(_sync):popup.about_to_popup.connect(_sync)
	_arranging=false

func _activate(id: int) -> void:
	var button= _more.get_popup().get_item_metadata(id)
	if not button is BaseButton:return
	if button.toggle_mode:button.button_pressed=not button.button_pressed
	button.pressed.emit()

func _sync() -> void:
	var popup:=_more.get_popup()
	for index in popup.item_count:
		var button=popup.get_item_metadata(index)
		if button is BaseButton:
			popup.set_item_disabled(index,button.disabled)
			if button.toggle_mode:popup.set_item_checked(index,button.button_pressed)

func _copy_menu(target: PopupMenu, source: PopupMenu) -> void:
	# 原菜单可能在打开时刷新项目；按当前结构递归映射，保持唯一命令入口。
	target.clear()
	for child in target.get_children():target.remove_child(child);child.queue_free()
	for index in source.item_count:
		var caption:=source.get_item_text(index)
		var id:=source.get_item_id(index)
		var path:=source.get_item_submenu(index)
		if source.is_item_separator(index):target.add_separator(caption,id)
		elif not path.is_empty():
			var original: PopupMenu=source.get_node(path)
			var nested:=PopupMenu.new();nested.name="Nested"+str(index);target.add_child(nested)
			_copy_menu(nested,original);target.add_submenu_item(caption,nested.name,id)
			nested.id_pressed.connect(func(item_id):original.id_pressed.emit(item_id);original.index_pressed.emit(original.get_item_index(item_id)))
			nested.about_to_popup.connect(func():original.about_to_popup.emit();_copy_menu(nested,original))
		elif source.is_item_radio_checkable(index):target.add_radio_check_item(caption,id)
		elif source.is_item_checkable(index):target.add_check_item(caption,id)
		else:target.add_item(caption,id)
		target.set_item_checked(index,source.is_item_checked(index))
		target.set_item_disabled(index,source.is_item_disabled(index))
		target.set_item_tooltip(index,source.get_item_tooltip(index))
