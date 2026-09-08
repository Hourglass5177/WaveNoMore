extends Control

## 选关页。它把内容目录与玩家存档整理成关卡卡片，不负责加载或启动关卡。

## 玩家确认关卡时发出；`stage_id` 用来从 ContentCatalog 重新解析关卡资源。
signal stage_selected(stage_id: String)
## 玩家请求返回标题页时发出。
signal back_requested
## 玩家请求打开设置弹窗时发出。
signal settings_requested
## 玩家请求打开随从弹窗时发出。
signal local_charts_requested
signal pets_requested

## 关卡卡片的纵向容器；每次刷新会按内容目录重建。
var _stage_list: VBoxContainer
var _stage_scroll: ScrollContainer
## 标题栏中的当前装备随从摘要。
var _pet_label: Label


func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	column.add_child(header)
	var title := Label.new()
	title.text = "择一处渡口"
	MingheUiStyle.style_title(title, 45)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_pet_label = Label.new()
	MingheUiStyle.style_body(_pet_label, 20)
	_pet_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pet_label.custom_minimum_size.x = 240
	header.add_child(_pet_label)
	var local := Button.new()
	local.text = "本地谱面"
	MingheUiStyle.style_button(local)
	local.custom_minimum_size.x = 220
	local.pressed.connect(func(): local_charts_requested.emit())
	header.add_child(local)
	var pets := Button.new()
	pets.text = "随从"
	pets.custom_minimum_size.x = 140
	MingheUiStyle.style_button(pets)
	pets.custom_minimum_size.x = 140
	pets.pressed.connect(func() -> void: pets_requested.emit())
	header.add_child(pets)
	var settings := Button.new()
	settings.text = "设置"
	settings.custom_minimum_size.x = 140
	MingheUiStyle.style_button(settings)
	settings.custom_minimum_size.x = 140
	settings.pressed.connect(func() -> void: settings_requested.emit())
	header.add_child(settings)
	_stage_scroll = ScrollContainer.new()
	# 手柄切换歌曲时，焦点与目录滚动同步；更换美术布局时也保留这一行为。
	_stage_scroll.follow_focus = true
	_stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_stage_scroll)
	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_list.add_theme_constant_override("separation", 18)
	_stage_scroll.add_child(_stage_list)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size.x = 220
	MingheUiStyle.style_button(back)
	back.pressed.connect(func() -> void: back_requested.emit())
	column.add_child(back)
	_refresh()


func _refresh() -> void:
	for child: Node in _stage_list.get_children():
		child.queue_free()
	var equipped := SaveService.equipped_pet_id()
	var pet := ContentCatalog.get_pet(equipped)
	_pet_label.text = "随从：%s" % ("未装备" if pet == null else pet.display_name + (" · 进阶" if SaveService.equipped_pet_advanced() else ""))
	var first_button: Button
	for stage: StageDefinition in ContentCatalog.all_stages():
		var unlocked := SaveService.is_stage_unlocked(stage)
		var result := SaveService.stage_result(stage.stage_id)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
		_stage_list.add_child(row)
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 28)
		row.add_child(content)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(details)
		var name_label := Label.new()
		name_label.text = "%02d  %s" % [stage.order_index, stage.display_name]
		name_label.add_theme_font_size_override("font_size", 31)
		name_label.add_theme_color_override("font_color", MingheUiStyle.BONE)
		details.add_child(name_label)
		var song_label := Label.new()
		var title_text := stage.song.title if stage.song != null else stage.song_title
		var artist_text := stage.song.artist if stage.song != null else stage.song_artist
		song_label.text = "%s · %s" % [title_text, artist_text]
		MingheUiStyle.style_body(song_label, 20)
		details.add_child(song_label)
		var record_label := Label.new()
		if result.is_empty():
			record_label.text = "尚无记录"
		else:
			var marks: Array[String] = []
			if bool(result.get("full_combo", false)):
				marks.append("FC")
			if bool(result.get("all_perfect", false)):
				marks.append("AP")
			record_label.text = "最好成绩 %d  %s" % [int(result.get("best_score", 0)), " / ".join(marks)]
		MingheUiStyle.style_body(record_label, 18)
		details.add_child(record_label)
		var play := Button.new()
		play.text = "进入" if unlocked else "未解锁"
		play.disabled = not unlocked
		play.custom_minimum_size = Vector2(220, 72)
		MingheUiStyle.style_button(play, unlocked)
		play.pressed.connect(func() -> void: stage_selected.emit(stage.stage_id))
		content.add_child(play)
		# 焦点进入后露出整张歌曲卡片，包括歌曲名和成绩。
		play.focus_entered.connect(func() -> void: _stage_scroll.ensure_control_visible.call_deferred(row))
		if first_button == null and unlocked:
			first_button = play
	if first_button != null:
		first_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
