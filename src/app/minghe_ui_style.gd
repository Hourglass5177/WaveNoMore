class_name MingheUiStyle
extends RefCounted

## 当前程序界面的共用色板和控件样式。正式 UI 美术接入前，各页面用它保持基本一致。

## 最深的墨黑色，用作页面底色。
const INK := Color("090b12")
## 稍亮的墨黑色，供面板或次级深色区域使用。
const INK_LIGHT := Color("121620")
## 主朱红色，用于生界色块和重点控件边框。
const VERMILION := Color("a72c25")
## 高亮朱红色，用于悬停、强调与强反馈。
const VERMILION_BRIGHT := Color("d34837")
## 骨白色，用于标题和主要可读文字。
const BONE := Color("e8e0cc")
## 灰色，用于说明文字和次要信息。
const ASH := Color("8b8990")
## 素音的暖白色，用于最亮的文字与视觉强调。
const SU := Color("f4edcf")


static func add_backdrop(parent: Control) -> void:
	var background := ColorRect.new()
	background.name = "Backdrop"
	background.color = INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)
	parent.move_child(background, 0)
	var life_field := Polygon2D.new()
	life_field.name = "LifeField"
	life_field.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(1420, 0), Vector2(470, 1080), Vector2(0, 1080)
	])
	life_field.color = Color(0.28, 0.035, 0.03, 0.82)
	background.add_child(life_field)
	var boundary := ColorRect.new()
	boundary.name = "Boundary"
	boundary.color = Color(0.92, 0.82, 0.62, 0.16)
	boundary.position = Vector2(500, 538)
	boundary.size = Vector2(920, 2)
	boundary.rotation = -0.65
	boundary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(boundary)


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.07, 0.94)
	style.border_color = Color(0.77, 0.66, 0.48, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 42.0
	style.content_margin_right = 42.0
	style.content_margin_top = 34.0
	style.content_margin_bottom = 34.0
	return style


static func style_button(button: Button, accent: bool = false) -> void:
	button.custom_minimum_size = Vector2(360, 58)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", BONE)
	button.add_theme_color_override("font_hover_color", SU)
	button.add_theme_color_override("font_pressed_color", SU)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.44, 0.45, 1))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.115, 0.15, 0.92)
	normal.border_color = VERMILION if accent else Color(0.42, 0.39, 0.36, 0.75)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.055, 0.05, 0.96) if accent else Color(0.16, 0.17, 0.20, 0.98)
	hover.border_color = VERMILION_BRIGHT if accent else Color(0.87, 0.77, 0.57, 0.8)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.32, 0.06, 0.045, 1)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = SU
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)


static func style_title(label: Label, size: int = 54) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", BONE)
	label.add_theme_color_override("font_shadow_color", Color(0.6, 0.03, 0.02, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)


static func style_body(label: Label, size: int = 20) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ASH)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
