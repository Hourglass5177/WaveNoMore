class_name PetVisual
extends Node2D
## 随从表现接口：bind 选择资源，set_state 按歌曲时间采样，不自主推进动画。
@export var texture: Texture2D
@export var frames: SpriteFrames
@export var display_size := Vector2(80, 80)
@export var idle_bob: float = 4.0
var _song_time := 0.0
var _trigger_age := 1000.0

func bind(pet: PetDefinition, advanced: bool) -> void:
	if texture == null: texture = pet.icon(advanced)
	queue_redraw()

func set_state(song_time: float, trigger_us: int) -> void:
	_song_time = song_time
	_trigger_age = song_time - float(trigger_us) / 1000000.0
	queue_redraw()

func _draw() -> void:
	var duration := _trigger_duration()
	var active := _trigger_age >= 0.0 and _trigger_age < duration
	var shown := texture
	if frames != null:
		var animation: StringName = &"trigger" if active and frames.has_animation(&"trigger") else &"idle"
		if frames.has_animation(animation) and frames.get_frame_count(animation) > 0:
			var total := 0.0
			for i in frames.get_frame_count(animation): total += frames.get_frame_duration(animation, i)
			var time := _trigger_age if animation == &"trigger" else maxf(0.0, _song_time)
			var phase := time * frames.get_animation_speed(animation)
			phase = fposmod(phase, total) if frames.get_animation_loop(animation) else minf(phase, total - 0.00001)
			for i in frames.get_frame_count(animation):
				phase -= frames.get_frame_duration(animation, i)
				if phase < 0.0:
					shown = frames.get_frame_texture(animation, i)
					break
	if shown == null: return
	var bob := Vector2(0, sin(_song_time * TAU / 2.0) * idle_bob)
	var pulse := 1.0 + (sin(_trigger_age / duration * PI) * 0.12 if active else 0.0)
	var extent := shown.get_size() * minf(display_size.x / shown.get_width(), display_size.y / shown.get_height()) * pulse
	draw_texture_rect(shown, Rect2(bob - extent * 0.5, extent), false)
	if active: draw_arc(bob, display_size.x * 0.55, 0, TAU, 32, Color(1, 0.85, 0.5, 1.0 - _trigger_age / duration), 2.0, true)

## 触发动画按自身帧时长完整播放；静态立绘使用短脉冲。
func _trigger_duration() -> float:
	if frames == null or not frames.has_animation(&"trigger") or frames.get_frame_count(&"trigger") == 0:
		return 0.35
	var duration := 0.0
	for i in frames.get_frame_count(&"trigger"):
		duration += frames.get_frame_duration(&"trigger", i)
	var speed := frames.get_animation_speed(&"trigger")
	return duration / speed if speed > 0.0 else 0.35
