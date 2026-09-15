class_name StageHud
extends CanvasLayer

@export var judgment_textures: JudgmentTextureSet = preload("res://content/presentation/judgment_textures.tres")

## 关卡 HUD。监听 Session 和 SongClock，显示魂火、得分、连击、判定与歌曲进度。

@export_group("Scene Wiring")
## 魂火进度条路径；其最大值和当前值来自 StageSession 的 health_changed。
@export var soul_fire_bar_path: NodePath = ^"Root/Margin/Layout/TopRow/SoulFireBar"
## 魂火数字 Label 路径，显示“当前值 / 上限”。
@export var soul_fire_value_path: NodePath = ^"Root/Margin/Layout/TopRow/SoulFireValue"
## 总分 Label 路径；画面会用 Tween 平滑追到真实整数分数。
@export var score_label_path: NodePath = ^"Root/Margin/Layout/TopRow/ScoreLabel"
## 连击 Label 路径；连击归零时隐藏文字。
@export var combo_label_path: NodePath = ^"Root/Margin/Layout/ComboLabel"
## 最近一次判定文字路径，位于共同中心附近并短暂淡出。
@export var judgment_label_path: NodePath = ^"Root/JudgmentLabel"
## 歌曲总进度条路径，取值为 0～100，不参与谱面判定。
@export var song_progress_path: NodePath = ^"Root/SongProgress"

# 这些字段缓存场景中的控件，避免每次刷新 HUD 都重新查找节点。
var _soul_fire_bar: ProgressBar
# 显示当前魂火数值的文字节点。
var _soul_fire_value: Label
# 显示当前得分的文字节点。
var _score_label: Label
# 显示当前连击数的文字节点。
var _combo_label: Label
# 短暂显示本次 Perfect、Good 或 Miss 结果的文字节点。
var _judgment_label: TextureRect
# 显示歌曲播放进度的进度条节点；0 是开头，满值是关卡结束。
var _song_progress: ProgressBar
# 歌曲时长单位为秒，至少为 0.001；用于换算总进度条百分比。
var _song_duration_sec: float = 1.0
# 显示分数与真实分数分开保存，Tween 才能从当前画面值平滑过渡。
var _displayed_score: int = 0
# 保存正在运行的 Tween，下一次更新前先停止，避免多个动画同时改同一属性。
var _score_tween: Tween
# 当前判定文字的淡出补间；新判定出现前会停止旧补间。
var _judgment_tween: Tween
var _judgment_regions: Dictionary = {}
var _judgment_material: ShaderMaterial


func _ready() -> void:
	layer = 10
	_soul_fire_bar = get_node(soul_fire_bar_path) as ProgressBar
	_soul_fire_value = get_node(soul_fire_value_path) as Label
	_score_label = get_node(score_label_path) as Label
	_combo_label = get_node(combo_label_path) as Label
	_judgment_label = get_node(judgment_label_path) as TextureRect
	_prepare_judgment_art()
	_song_progress = get_node(song_progress_path) as ProgressBar
	_soul_fire_bar.step = 0.0
	_song_progress.step = 0.0
	# HUD 只展示信息，必须让鼠标穿透到底层输入单例，否则左右鼠标敲钟会失效。
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)


func configure(stage: StageDefinition) -> void:
	_song_duration_sec = 1.0
	if stage == null or stage.song == null:
		return
	if stage.song.audio_stream != null and stage.song.audio_stream.get_length() > 0.0:
		_song_duration_sec = maxf(stage.song.audio_stream.get_length() - stage.song.first_beat_offset_sec, 0.001)
	else:
		_song_duration_sec = maxf(stage.song.fallback_duration_sec, 0.001)


func set_song_duration(duration_sec: float) -> void:
	_song_duration_sec = maxf(duration_sec, 0.001)


func bind(session: StageSession, clock: SongClock) -> void:
	if not session.health_changed.is_connected(_on_health_changed):
		session.health_changed.connect(_on_health_changed)
	if not session.score_changed.is_connected(_on_score_changed):
		session.score_changed.connect(_on_score_changed)
	if not session.judgment_recorded.is_connected(_on_judgment_recorded):
		session.judgment_recorded.connect(_on_judgment_recorded)
	if not clock.sample_published.is_connected(_on_clock_sample):
		clock.sample_published.connect(_on_clock_sample)


func _on_health_changed(current: int, maximum: int) -> void:
	_soul_fire_bar.max_value = max(maximum, 1)
	_soul_fire_value.text = "%d / %d" % [current, maximum]
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_soul_fire_bar, "value", current, 0.18)


func _on_score_changed(score: int, combo: int) -> void:
	if _score_tween != null:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.set_trans(Tween.TRANS_QUAD)
	_score_tween.set_ease(Tween.EASE_OUT)
	_score_tween.tween_method(_set_displayed_score, float(_displayed_score), float(score), 0.22)
	_combo_label.text = "连响  %d" % combo if combo > 0 else ""
	if combo > 0 and combo % 10 == 0:
		_combo_label.scale = Vector2(1.20, 0.82)
		var combo_tween := create_tween()
		combo_tween.set_trans(Tween.TRANS_BACK)
		combo_tween.set_ease(Tween.EASE_OUT)
		combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.18)


func _on_judgment_recorded(record: JudgmentRecord) -> void:
	if judgment_textures == null: return
	_judgment_label.texture = _judgment_texture(record.grade)
	_judgment_label.modulate = Color.WHITE
	_apply_judgment_layout()
	_judgment_material.set_shader_parameter("ink",judgment_textures.grade_color(record.grade))
	_judgment_label.modulate.a = judgment_textures.opacity
	var display_scale := maxf(0.01, judgment_textures.scale) if judgment_textures != null else 1.0
	_judgment_label.scale = Vector2(display_scale * 1.25, display_scale * 0.78)
	if _judgment_tween != null:
		_judgment_tween.kill()
	_judgment_tween = create_tween()
	_judgment_tween.set_parallel(true)
	_judgment_tween.tween_property(_judgment_label, "scale", Vector2.ONE * display_scale, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_judgment_tween.tween_property(_judgment_label, "modulate:a", 0.0, 0.42).set_delay(0.20)


func _on_clock_sample(sample: ClockSample) -> void:
	_song_progress.value = clampf(sample.song_time_sec / _song_duration_sec, 0.0, 1.0) * 100.0


func _set_displayed_score(value: float) -> void:
	_displayed_score = roundi(value)
	_score_label.text = "%08d" % _displayed_score

func _judgment_texture(grade: int) -> Texture2D:
	if judgment_textures == null: return null
	match grade:
		GameplayTypes.JudgmentGrade.PERFECT: return judgment_textures.perfect
		GameplayTypes.JudgmentGrade.GOOD: return judgment_textures.good
		GameplayTypes.JudgmentGrade.PASS: return judgment_textures.pass_texture
		GameplayTypes.JudgmentGrade.MISS: return judgment_textures.miss
	return null

func _apply_judgment_layout() -> void:
	if judgment_textures == null: return
	var texture := _judgment_label.texture
	if texture == null: return
	var region: Rect2 = _judgment_regions[texture]
	var glyph_size := Vector2(region.size.x/region.size.y,1.0)*judgment_textures.glyph_height
	var padding := judgment_textures.glow_radius_px*2.0/maxf(judgment_textures.scale,0.01)
	var base_size := glyph_size+Vector2.ONE*padding*2.0
	var source_size := texture.get_size()
	_judgment_material.set_shader_parameter("source_rect",Vector4(region.position.x/source_size.x,region.position.y/source_size.y,region.size.x/source_size.x,region.size.y/source_size.y))
	_judgment_material.set_shader_parameter("glyph_size",glyph_size)
	_judgment_material.set_shader_parameter("padding",padding)
	_judgment_material.set_shader_parameter("radius",judgment_textures.glow_radius_px/maxf(judgment_textures.scale,0.01))
	_judgment_material.set_shader_parameter("strength",judgment_textures.glow_strength)
	_judgment_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_judgment_label.size = base_size
	_judgment_label.pivot_offset = base_size * 0.5
	_judgment_label.scale = Vector2.ONE * maxf(0.01, judgment_textures.scale)
	_judgment_label.position = Vector2(960.0, 540.0) - base_size * 0.5 + judgment_textures.offset

func _prepare_judgment_art() -> void:
	if judgment_textures == null: return
	judgment_textures = judgment_textures.duplicate()
	var report := PlanningParameters.read()
	for key: String in ["glyph_height","opacity","glow_radius_px","glow_strength","perfect_color","good_color","pass_color","miss_color"]:
		var id := "judgment/"+key
		if report.values.has(id):
			judgment_textures.set(key,Color(str(report.values[id])) if key.ends_with("_color") else report.values[id])
	_judgment_material = ShaderMaterial.new()
	_judgment_material.shader = preload("res://shaders/ui/judgment_glow.gdshader")
	_judgment_label.material = _judgment_material
	_judgment_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_judgment_label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_judgment_label.stretch_mode = TextureRect.STRETCH_SCALE
	# 装载时缓存实体笔画的包围盒，命中时不读回图片、不遍历像素。
	for texture: Texture2D in [judgment_textures.perfect,judgment_textures.good,judgment_textures.pass_texture,judgment_textures.miss]:
		if texture == null: continue
		var image := texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		var pixels := image.get_data()
		var width := image.get_width()
		var low := Vector2i(image.get_size())
		var high := Vector2i.ZERO
		for index in range(3,pixels.size(),4):
			if pixels[index] < 128: continue
			var pixel := (index-3)/4
			var point := Vector2i(pixel%width,pixel/width)
			low = low.min(point)
			high = high.max(point)
		_judgment_regions[texture] = Rect2(Vector2(low),Vector2(high-low+Vector2i.ONE))


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child, filter)
