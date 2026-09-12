shader_type canvas_item;
render_mode unshaded;
uniform sampler2D next_texture : repeat_disable, filter_nearest;
uniform vec2 inverse_x = vec2(1.0, 0.0);
uniform vec2 inverse_y = vec2(0.0, 1.0);
uniform vec2 inverse_origin = vec2(0.0);
uniform vec2 direction = vec2(1.0, 0.0);
uniform vec4 limits = vec4(-1e12, 1e12, 0.0, 0.0);
uniform vec4 next_limits = vec4(-1e12, 1e12, 0.0, 0.0);
uniform float opacity = 1.0;
uniform float next_opacity = 0.0;
float weight(float point, vec4 boundary) {
	float a = boundary.z > 0.0 ? smoothstep(boundary.x - boundary.z * 0.5, boundary.x + boundary.z * 0.5, point) : step(boundary.x, point);
	float b = boundary.w > 0.0 ? 1.0 - smoothstep(boundary.y - boundary.w * 0.5, boundary.y + boundary.w * 0.5, point) : 1.0 - step(boundary.y, point);
	return a * b;
}
void fragment() {
	vec2 design = inverse_x * FRAGCOORD.x + inverse_y * FRAGCOORD.y + inverse_origin;
	float point = dot(design, direction);
	// 离屏来源为预乘透明度；先按空间权重相加，再还原一次，避免交叠处变暗。
	vec4 sum = texture(TEXTURE, UV) * weight(point, limits) * opacity;
	sum += texture(next_texture, UV) * weight(point, next_limits) * next_opacity;
	if (sum.a > 0.00001) { sum.rgb /= sum.a; }
	COLOR = sum;
}
