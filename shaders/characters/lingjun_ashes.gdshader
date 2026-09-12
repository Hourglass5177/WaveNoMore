shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 source_size;
uniform float age = 0.0;
uniform float duration = 0.65;
uniform float spread_px = 95.0;
uniform vec4 ash_color : source_color = vec4(0.78, 0.75, 0.69, 1.0);
varying float kind;
varying float seed;
varying vec2 source_uv;

void vertex() {
	// 沿用音符碎片网格中的中心、编号与类型编码；运动沿角色自己的上方轻轻飘散。
	source_uv = COLOR.rg;
	vec2 center = (source_uv - 0.5) * source_size;
	seed = COLOR.b;
	kind = COLOR.a;
	float t = max(age - seed * 0.07, 0.0);
	float progress = 1.0 - exp(-t * 3.5);
	float angle = sin(seed * 31.7) * progress * 0.24;
	vec2 relative = VERTEX - center;
	VERTEX = center + mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * relative;
	vec2 drift = vec2(sin(seed * 37.1) * 0.65, -0.65 - seed * 0.55);
	VERTEX += drift * progress * spread_px * (kind > 0.75 ? 1.4 : 1.0);
	COLOR = vec4(1.0);
}

void fragment() {
	float progress = clamp(age / duration, 0.0, 1.0);
	if (kind > 0.75) {
		float coverage = texture(TEXTURE, source_uv).a;
		float radius = length(UV * 2.0 - 1.0);
		float fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.22, duration, age));
		COLOR = vec4(ash_color.rgb, coverage * exp(-radius * radius * 3.8) * fade * 0.65);
	} else {
		vec4 texel = texture(TEXTURE, UV);
		float fade = 1.0 - smoothstep(0.13 + seed * 0.10, duration - 0.06 + seed * 0.06, age);
		if (kind > 0.25) {
			float edge = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.08, 0.23, age));
			COLOR = vec4(ash_color.rgb, texel.a * edge * 0.25);
		} else {
			vec3 color = mix(texel.rgb, ash_color.rgb * dot(texel.rgb, vec3(0.25, 0.55, 0.20)), progress * 0.35);
			COLOR = vec4(color, texel.a * fade);
		}
	}
}
