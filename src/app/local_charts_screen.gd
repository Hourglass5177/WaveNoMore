extends Control
signal play_requested(context: Dictionary)
signal back_requested
signal close_requested
var library: LocalChartLibrary
var jobs: ChartReadJobs
var selected_song := ""
var selected_chart := ""
var import_only := false
var _request := -1
var _source := ""
var _songs: Array[String] = []
var _charts: Array[String] = []
@onready var list: ItemList = %Songs
@onready var difficulties: OptionButton = %Difficulties
@onready var message: Label = %Message

func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	MingheUiStyle.style_title(%Title, 42)
	for button in [%Import, %Play, %Remove, %Back]: MingheUiStyle.style_button(button)
	for label in [%Details, %Message]: MingheUiStyle.style_body(label, 22)
	list.add_theme_font_size_override("font_size", 26)
	difficulties.add_theme_font_size_override("font_size", 24)
	%Import.pressed.connect(_choose_file)
	%Back.pressed.connect(_back)
	%Play.pressed.connect(func(): play_requested.emit(library.context(selected_song, selected_chart)))
	%Remove.pressed.connect(_remove)
	list.item_selected.connect(func(i: int): selected_song = _songs[i]; selected_chart = ""; list.ensure_current_is_visible(); _refresh_difficulties())
	list.item_activated.connect(func(_i: int): difficulties.grab_focus())
	difficulties.item_selected.connect(func(i: int): selected_chart = _charts[i]; _show_details())
	jobs.completed.connect(_loaded)
	get_window().files_dropped.connect(_dropped)
	if import_only:
		%Play.hide(); %Remove.hide(); %Back.text = "返回试玩"
	refresh()
	%Import.grab_focus()

func refresh() -> void:
	list.clear(); _songs.clear()
	var ids: Array = library.data.songs.keys()
	ids.sort_custom(func(a, b): return int(library.data.songs[a].get("order_index", 0)) < int(library.data.songs[b].get("order_index", 0)))
	for id: String in ids:
		_songs.append(id)
		var song: Dictionary = library.data.songs[id]
		var cover: Texture2D
		if song.has("cover_path"):
			var picture := Image.load_from_file(library.directory.path_join(song.cover_path))
			if picture != null: cover = ImageTexture.create_from_image(picture)
		list.add_item(str(song.title), cover)
	if not _songs.has(selected_song): selected_song = _songs[0] if not _songs.is_empty() else ""
	if not selected_song.is_empty(): list.select(_songs.find(selected_song)); list.ensure_current_is_visible()
	_refresh_difficulties()
	message.text = library.error if not library.error.is_empty() else ("还没有本地谱面。点击“导入谱面”，或将一个 ZIP 拖到这里。" if _songs.is_empty() else "")

func _refresh_difficulties() -> void:
	difficulties.clear(); _charts.clear()
	var song: Dictionary = library.data.songs.get(selected_song, {})
	for id: String in song.get("charts", {}):
		_charts.append(id)
		difficulties.add_item(str(song.charts[id].name))
	if not _charts.has(selected_chart): selected_chart = _charts[0] if not _charts.is_empty() else ""
	if not selected_chart.is_empty(): difficulties.select(_charts.find(selected_chart))
	%Play.disabled = selected_chart.is_empty()
	%Remove.disabled = selected_chart.is_empty()
	_show_details()

func _show_details() -> void:
	var song: Dictionary = library.data.songs.get(selected_song, {})
	var chart: Dictionary = song.get("charts", {}).get(selected_chart, {})
	%Details.text = "作者：%s\n谱师：%s" % [song.get("artist", ""), chart.get("mapper", "")] if not chart.is_empty() else ""
	if song.has("level_id"):
		%Details.text += "\n" + str(song.get("description", ""))
		var locked: bool = not bool(song.get("unlocked_by_default", true)) and song.level_id not in SaveService.data.get("unlocked_stages", [])
		%Play.disabled = chart.is_empty() or locked
		if locked: %Details.text += "\n尚未解锁，请先完成前置关卡。"

func _choose_file() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.zip ; 谱面包或关卡包"])
	dialog.title = "导入谱面或关卡"
	add_child(dialog)
	dialog.tree_exited.connect(func(): %Import.grab_focus())
	dialog.file_selected.connect(func(path: String): import_path(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree(): return
	if files.size() != 1 or files[0].get_extension().to_lower() != "zip":
		message.text = "请一次拖入一个 ZIP 谱面包。"
		return
	import_path(files[0])

func import_path(path: String) -> void:
	jobs.cancel_request(_request)
	_source = path
	_request = jobs.request(path, "", true)
	message.text = "正在检查所有难度和音乐…"
	%Import.disabled = true

func _loaded(id: int, result: Dictionary) -> void:
	if id != _request: return
	_request = -1
	%Import.disabled = false
	if not result.errors.is_empty():
		message.text = ChartProjectLoader.describe_issues(result.errors)
		return
	var info: Dictionary = result.metadata
	var source := _source
	var summary := library.update_summary(info)
	if summary.is_empty(): _commit_import(source, info)
	else: _confirm(summary, func(): _commit_import(source, info))

func _commit_import(path: String, info: Dictionary) -> void:
	var error := library.import_checked(path, info)
	if not error.is_empty(): message.text = error; return
	selected_song = info.song_id
	selected_chart = info.charts[0].chart_id
	refresh()
	message.text = "已导入：%s" % info.title
	if not import_only: %Play.grab_focus()

func _remove() -> void:
	var song := selected_song
	var chart := selected_chart
	_confirm("移除当前难度？原始导入文件不会删除。", func():
		var error := library.remove(song, chart)
		refresh()
		message.text = "已移除" if error.is_empty() else error)

func _confirm(text: String, action: Callable) -> void:
	var previous := get_viewport().gui_get_focus_owner()
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.title = "本地谱面"
	dialog.ok_button_text = "确定"; dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.tree_exited.connect(func():
		if is_instance_valid(previous): previous.grab_focus())
	dialog.confirmed.connect(func(): action.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(660, 220))

func _back() -> void:
	jobs.cancel_request(_request)
	_request = -1
	back_requested.emit()
	close_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()

func _exit_tree() -> void:
	jobs.cancel_request(_request)
