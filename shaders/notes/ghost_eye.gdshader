shader_type canvas_item;
render_mode unshaded;

uniform sampler2D closed_eye : source_color, filter_linear, repeat_disable;
uniform sampler2D open_eye : source_color, filter_linear, repeat_disable;
uniform sampler2D closed_distance : filter_linear, repeat_disable;
uniform sampler2D open_distance : filter_linear, repeat_disable;
uniform vec4 bone_color : source_color = vec4(0.902, 0.867, 0.788, 1.0);
uniform vec2 eye_anchor = vec2(0.48, 0.35);
// x 睁眼进度、y 总透明度、z 柔光强度、w 结果进度；宿主按绝对时钟一次上传。
uniform vec4 phase = vec4(0.0, 0.0, 0.13, 0.0);
uniform float result_kind = 0.0;
uniform float body_width = 112.0;
uniform float halo_width = 36.0;
uniform vec2 surface_light = vec2(0.08, 0.62);
uniform vec2 mask_content_size = vec2(192.0, 167.0);

vec4 eye_sample(sampler2D source, vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec4(0.0);
	return texture(source, uv);
}

void fragment() {
	float shrink = result_kind > 0.5 ? mix(1.0, 0.74, phase.w) : 1.0;
	vec2 uv = (UV - eye_anchor) / shrink + eye_anchor;
	vec4 a = eye_sample(closed_eye, uv);
	vec4 b = eye_sample(open_eye, uv);
	// 预乘透明度混合避免两张图透明边缘带入黑色，保持睫毛、颗粒与眼眶完整。
	float coverage = mix(a.a, b.a, phase.x);
	vec3 base = mix(a.rgb * a.a, b.rgb * b.a, phase.x) / max(coverage, 0.0001);
	float light = mix(surface_light.x, surface_light.y, phase.x);
	vec3 white = mix(bone_color.rgb, vec3(1.0), phase.x * 0.8);
	if (result_kind > 0.5) light = mix(light, 0.88, 1.0 - phase.w);
	if (result_kind < -0.5) { light = 0.0; white = vec3(0.55, 0.53, 0.56); base = mix(base, white, 0.55); }
	base = mix(base, white, light);
	// 与正式音符一致：读取离线距离遮罩，外晕不做逐像素大半径模糊。
	vec2 mask_uv = (uv * mask_content_size + vec2(128.0)) / (mask_content_size + vec2(256.0));
	float unit_px = body_width / (mask_content_size.x * 0.5);
	float da = (texture(closed_distance, mask_uv).r - 0.5) * 128.0 * unit_px;
	float db = (texture(open_distance, mask_uv).r - 0.5) * 128.0 * unit_px;
	float d = mix(da, db, phase.x) * shrink;
	float outside = smoothstep(-1.0, 1.2, d);
	float rim = exp(-pow(d / 2.2, 2.0)) * 0.38;
	float halo = exp(-pow(max(d, 0.0) / (halo_width * 0.48), 2.0)) * 0.72;
	float glow = (rim + halo) * outside * (1.0 - smoothstep(halo_width * 0.8, halo_width, d)) * phase.z;
	float alpha = coverage + glow * (1.0 - coverage);
	vec3 rgb = (base * coverage + white * glow * (1.0 - coverage)) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha * phase.y);
}
