shader_type canvas_item;
render_mode unshaded;

uniform vec2 draw_size = vec2(520.0, 40.0);
uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float trail_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float impact : hint_range(0.0, 1.0) = 0.0;
uniform vec4 jade : source_color = vec4(0.71, 0.80, 0.76, 1.0);
uniform vec4 ivory : source_color = vec4(0.94, 0.91, 0.80, 1.0);
uniform vec4 old_gold : source_color = vec4(0.60, 0.53, 0.39, 1.0);
uniform vec4 cinnabar : source_color = vec4(0.65, 0.25, 0.20, 1.0);
uniform float bar_height : hint_range(6.0, 20.0) = 12.0;
uniform float glow_width : hint_range(2.0, 16.0) = 11.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.46;

// 两端斜收，细微静态颗粒保留墨线的触感；不依赖 TIME 或屏幕取样。
float bar_distance(vec2 p, float length, float height) {
	vec2 q = abs(p) - vec2(length, height) * 0.5;
	return max(max(q.x, q.y), (q.x + q.y + 3.0) * 0.7071);
}
float coverage(float d) { return 1.0 - smoothstep(-0.65, 0.65, d); }
float grain(vec2 p) { return fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453); }
// 局部按预乘色累积，最后还原直通 alpha，父层淡出不会留下光晕。
vec4 over(vec4 base, vec3 ink, float alpha) {
	return vec4(ink * alpha + base.rgb * (1.0-alpha), alpha + base.a * (1.0-alpha));
}
void fragment() {
	vec2 p = UV * draw_size;
	float length = draw_size.x - 38.0;
	vec2 local = p - vec2(draw_size.x * 0.5, draw_size.y * 0.5);
	float d = bar_distance(local, length, bar_height);
	float x = local.x + length * 0.5;
	float end = length * health_ratio;
	float live = step(0.0001, health_ratio);
	float filled_d = max(d + 1.5, x - end);
	float danger = 1.0 - smoothstep(0.08, 0.27, health_ratio);
	vec3 fill_ink = mix(jade.rgb, ivory.rgb, 0.55 + 0.35 * cos(local.y * 0.33));
	fill_ink = mix(fill_ink, mix(cinnabar.rgb, ivory.rgb, 0.36), danger * 0.65);
	float halo = pow(1.0 - smoothstep(0.0, glow_width, max(filled_d, 0.0)), 2.0);
	vec4 result = vec4(0.0);
	result = over(result, mix(jade.rgb, ivory.rgb, 0.3), halo * glow_strength * live);
	result = over(result, vec3(0.035, 0.032, 0.045), coverage(d - 1.5) * 0.75);
	result = over(result, old_gold.rgb, coverage(d) * 0.86);
	result = over(result, vec3(0.075, 0.068, 0.082), coverage(d + 1.1) * 0.98);
	float trail = coverage(d + 1.5) * (1.0 - smoothstep(-0.65, 0.65, x - length * trail_ratio));
	result = over(result, cinnabar.rgb, trail * 0.82 * step(0.0001, trail_ratio));
	float ink_texture = 0.94 + grain(p * 1.7) * 0.06;
	result = over(result, fill_ink * ink_texture, coverage(filled_d) * live);
	// 当前血量末端留一线玉白，受伤只短促提亮，不闪整个 HUD。
	float edge = (1.0 - smoothstep(0.0, 2.2, abs(x-end))) * coverage(d + 1.7) * live;
	result = over(result, ivory.rgb, edge * (0.5 + 0.3 * impact));
	float ridge = (1.0-smoothstep(0.0, 0.85, abs(local.y + bar_height*0.5 - 2.0))) * coverage(filled_d) * live;
	result = over(result, ivory.rgb, ridge * 0.62);
	// 左侧菱形结与右侧短收笔：只保留小尺度器物感，不堆装饰框。
	float seal = abs(p.x - 9.0) * 0.70 + abs(local.y) - 4.2;
	float seal_line = 1.0 - smoothstep(0.35, 1.10, abs(seal));
	result = over(result, old_gold.rgb, seal_line * 0.8);
	float tip = abs(local.y) + max(0.0, abs(p.x - (draw_size.x-10.0)) - 5.0);
	result = over(result, old_gold.rgb, (1.0-smoothstep(0.2, 1.0, tip)) * 0.72);
	COLOR = vec4(result.rgb / max(result.a, 0.0001), result.a) * COLOR;
}
