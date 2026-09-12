shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/notes/note_surface.gdshaderinc"
#include "res://shaders/notes/note_eye.gdshaderinc"

uniform vec2 source_size = vec2(96.0);
uniform float age = 0.0;
uniform float crack_sec = 0.03;
uniform float shard_sec = 0.26;
uniform float dust_sec = 0.34;
uniform float spread_px = 66.0;
uniform vec2 impact_direction = vec2(1.0, 0.0);
uniform float variation = 0.0;
uniform bool has_texture = true;
uniform bool has_eye = false;
uniform vec2 eye_offset_uv;
uniform float shake_sec = 0.06;
uniform float shake_px = 0.0;
varying float is_dust;
varying float piece_age;

void vertex() {
	// 顶点颜色保存片中心、稳定编号和类型；运动按事件年龄解析求值。
	vec2 center = (COLOR.rg - 0.5) * source_size;
	float phase = COLOR.b * 6.2831853 + variation;
	is_dust = COLOR.a;
	piece_age = max(age - crack_sec, 0.0);
	vec2 direction = normalize(center / source_size + impact_direction * 0.30 + vec2(cos(phase), sin(phase)) * 0.16);
	float motion = 1.0 - exp(-piece_age * (is_dust > 0.75 ? 8.0 : 14.0));
	float distance_px = spread_px * (0.55 + 0.45 * abs(sin(phase * 2.3)));
	float angle = sin(phase * 3.1) * motion * 0.48;
	vec2 relative = VERTEX - center;
	VERTEX = center + mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * relative;
	VERTEX += direction * motion * distance_px;
	// 同一事件共用一次衰减震颤，坐标锚点不动，也不依赖逐帧随机数。
	float shake_age = clamp(age / shake_sec, 0.0, 1.0);
	float shake = sin(shake_age * 18.849556 + variation) * (1.0 - shake_age) * (1.0 - shake_age);
	VERTEX += impact_direction * shake * shake_px;
	COLOR = vec4(1.0);
}

void fragment() {
	if (is_dust > 0.75) {
		float r = length(UV * 2.0 - 1.0);
		float fade = 1.0 - smoothstep(dust_sec * 0.20, dust_sec, age);
		COLOR = vec4(mix(surface_color.rgb, white_color.rgb, 0.38), exp(-r * r * 3.5) * fade * 0.60);
	} else if (is_dust > 0.25) {
		float fade = (1.0 - smoothstep(crack_sec, crack_sec + 0.045, age));
		COLOR = vec4(mix(surface_color.rgb, white_color.rgb, 0.55), fade * (has_texture ? texture(TEXTURE, UV).a : 1.0) * 0.85);
	} else {
		vec4 texel = has_texture ? texture(TEXTURE, UV) : vec4(surface_color.rgb, 1.0);
		float eye_mask = smoothstep(0.72, 0.92, min(texel.r, min(texel.g, texel.b)));
		vec3 color = note_surface(texel.rgb, eye_mask);
		if (has_eye) {
			texel = note_eye(texel, UV, UV - eye_offset_uv);
			color = texel.rgb;
		}
		float flash = 1.0 - smoothstep(0.0, crack_sec + 0.035, age);
		color = mix(color, white_color.rgb, flash * 0.45);
		float fade = 1.0 - smoothstep(shard_sec * 0.35, shard_sec, age);
		COLOR = vec4(color, texel.a * fade);
	}
}
