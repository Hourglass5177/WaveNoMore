shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D musk_texture : filter_linear, repeat_disable;
uniform sampler2D eye_ball_texture : source_color, filter_linear, repeat_disable;
uniform float eye_offset_px : hint_range(0.0, 32.0, 0.1) = 10.0;
uniform float eye_falloff_radius_px : hint_range(1.0, 1000.0, 1.0) = 128.0;

varying vec2 center_screen_uv;
varying vec4 item_color;

void vertex() {
	vec4 center = SCREEN_MATRIX * CANVAS_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	center_screen_uv = center.xy / center.w * 0.5 + 0.5;
	item_color = COLOR;
}

void fragment() {
	vec2 to_center = (vec2(0.5) - center_screen_uv) / SCREEN_PIXEL_SIZE;
	float distance_px = length(to_center);
	// 仅在屏幕中心附近平滑减小半径；超过作用范围后保持默认固定值。
	float falloff = smoothstep(0.0, eye_falloff_radius_px, distance_px);
	vec2 offset_px = distance_px > 0.0001 ? to_center / distance_px * eye_offset_px * falloff : vec2(0.0);
	// Reverse sampling moves the eye toward the center in screen space.
	vec2 eye_uv = UV - dFdx(UV) * offset_px.x - dFdy(UV) * offset_px.y;
	vec4 base = texture(TEXTURE, UV);
	vec4 eye = texture(eye_ball_texture, eye_uv);
	float inside = step(0.0, eye_uv.x) * step(eye_uv.x, 1.0) * step(0.0, eye_uv.y) * step(eye_uv.y, 1.0);
	// Mask stays on the base: black preserves base; white composites the moving eye over it.
	float eye_alpha = eye.a * texture(musk_texture, UV).r * inside;
	float alpha = eye_alpha + base.a * (1.0 - eye_alpha);
	vec3 premultiplied = eye.rgb * eye_alpha + base.rgb * base.a * (1.0 - eye_alpha);
	COLOR = vec4(alpha > 0.0 ? premultiplied / alpha : vec3(0.0), alpha) * item_color;
}
