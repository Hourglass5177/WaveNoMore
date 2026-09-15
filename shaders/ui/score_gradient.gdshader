shader_type canvas_item;
render_mode unshaded;
uniform sampler2D color_ramp : source_color, filter_linear, repeat_disable;
uniform vec2 text_extent = vec2(0.0,312.0);
uniform float optical_shift = 0.0;
varying float text_x;
void vertex() {
	// 使用整段文字的局部坐标，不用字形图集 UV，避免每个数字重复一遍渐变。
	VERTEX.x += optical_shift;
	text_x = VERTEX.x;
}
void fragment() {
	float x = clamp((text_x-text_extent.x)/max(text_extent.y,1.0),0.0,1.0);
	vec3 tint = texture(color_ramp,vec2(x,0.5)).rgb;
	COLOR = vec4(tint,COLOR.a);
}
