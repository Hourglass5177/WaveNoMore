@tool
extends Label
## 分数共用整行渐变；按字形实际边界校正，不用固定的“向左几像素”。
var ink_extent := Vector2.ZERO
var optical_shift := 0.0

func _ready() -> void:
	material = preload("res://content/ui/score_gradient.tres").duplicate(false)
	resized.connect(refresh_style)
	refresh_style()

func set_score(value: int) -> void:
	text = "%06d" % maxi(0, value)
	refresh_style()

func refresh_style() -> void:
	if not is_node_ready(): return
	var font: Font = label_settings.font if label_settings != null else get_theme_font("font")
	var font_size: int = label_settings.font_size if label_settings != null else get_theme_font_size("font_size")
	var server := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var advance := 0.0
	var left := INF
	var right := -INF
	# 分数只有数字，逐字读取同一字体的边界即可，不需要每帧生成图片。
	for i in text.length():
		var glyph := server.font_get_glyph_index(rid, font_size, text.unicode_at(i), 0)
		var origin := server.font_get_glyph_offset(rid, Vector2i(font_size, 0), glyph).x
		var width := server.font_get_glyph_size(rid, Vector2i(font_size, 0), glyph).x
		left = minf(left, advance + origin)
		right = maxf(right, advance + origin + width)
		advance += server.font_get_glyph_advance(rid, font_size, glyph).x
	if text.is_empty(): return
	optical_shift = (advance - left - right) * 0.5
	ink_extent = Vector2((size.x - (right-left))*0.5, right-left)
	material.set_shader_parameter("optical_shift", optical_shift)
	material.set_shader_parameter("text_extent", ink_extent)
