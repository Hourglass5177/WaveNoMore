shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform vec2 source_size = vec2(512.0);
uniform float age = 0.0;
uniform float duration = 0.65;
uniform float spread_px = 38.0;
varying float kind;
varying float seed;
varying vec2 sample_uv;
varying float inward;
void vertex() {
	sample_uv = COLOR.rg;
	seed = COLOR.b;
	kind = COLOR.a;
	vec2 center = (sample_uv - 0.5) * source_size;
	inward = 1.0 - clamp(length(sample_uv - 0.5) * 3.0, 0.0, 1.0);
	float t = max(age - inward * 0.10, 0.0);
	float move = smoothstep(0.0, duration, t);
	float angle = sin(seed * 31.7) * move * 0.14;
	vec2 p = VERTEX - center;
	VERTEX = center + mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p;
	VERTEX += vec2(sin(seed * 37.1) * 0.45, -0.70 - seed * 0.20) * move * spread_px;
	COLOR = vec4(1.0);
}
void fragment() {
	vec4 sampled = texture(TEXTURE, sample_uv);
	if (kind > 0.75) {
		float radius = length(UV * 2.0 - 1.0);
		float fade = smoothstep(0.05, 0.18, age) * (1.0 - smoothstep(0.28, duration, age));
		COLOR = vec4(mix(sampled.rgb, vec3(0.64, 0.61, 0.57), 0.30), sampled.a * exp(-radius * radius * 3.5) * fade * 0.48);
	} else if (kind > 0.25) {
		COLOR = vec4(0.0);
	} else {
		vec4 texel = texture(TEXTURE, UV);
		float fade = 1.0 - smoothstep(0.06 + inward * 0.16, 0.44 + inward * 0.21, age);
		COLOR = vec4(mix(texel.rgb, texel.rgb * 0.74, smoothstep(0.0, duration, age)), texel.a * fade);
	}
}
