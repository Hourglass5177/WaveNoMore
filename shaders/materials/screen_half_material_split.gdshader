shader_type canvas_item;
render_mode unshaded, blend_mix;

// 按屏幕位置选择两张材质纹理。SCREEN_UV 只用于选择上下半屏，
// 不作为纹理坐标，因此不会把对象纹理拉伸到整个屏幕。
uniform sampler2D upper_material : source_color, filter_linear, repeat_disable;
uniform sampler2D lower_material : source_color, filter_linear, repeat_disable;


void fragment() {
	if (SCREEN_UV.y < 0.5) {
		COLOR = texture(upper_material, UV);
	} else {
		COLOR = texture(lower_material, UV);
	}
}
