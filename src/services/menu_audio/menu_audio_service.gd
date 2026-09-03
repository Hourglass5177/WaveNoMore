extends Node

## 菜单歌曲试听服务。用独立播放器播放限定时长的预览，不参与关卡时钟和判定。

## 菜单试听专用播放器，固定输出到 Music 总线，不与关卡 SongClock 绑定。
var _player: AudioStreamPlayer
## 限制试听长度的一次性计时器；到时调用 `stop_preview()`。
var _preview_timer: Timer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.timeout.connect(stop_preview)
	add_child(_preview_timer)


func play_preview(song: SongDefinition) -> void:
	stop_preview()
	if song == null or song.audio_stream == null:
		return
	_player.stream = song.audio_stream
	_player.play(song.preview_start_sec)
	_preview_timer.start(song.preview_duration_sec)


func stop_preview() -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	if _player != null:
		_player.stop()
		_player.stream = null
