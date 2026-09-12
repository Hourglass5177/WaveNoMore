shader_type canvas_item;
render_mode unshaded, blend_mix;

// 生侧背景直接使用精灵原图，只保留上半屏；不需要额外的材质贴图参数。


void fragment() {
	if (SCREEN_UV.y < 0.5) {
		COLOR = texture(TEXTURE, UV);
	} else {
		COLOR.a = 0.0;
	}
}
