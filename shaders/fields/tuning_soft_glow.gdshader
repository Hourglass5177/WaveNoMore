shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/fields/tuning_arc_distance.gdshaderinc"
uniform vec4 outline_color : source_color = vec4(0.902, 0.867, 0.788, 1.0);
uniform vec4 fill_color : source_color;
uniform float outline_strength = 0.65;
uniform float fill_strength = 0.65;
uniform float outline_radius = 18.0;
uniform float fill_radius = 24.0;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }

// 轨道是同心圆弧；直接求圆弧胶囊距离，圆帽与条身天然连续，无逐像素采样点循环。
float soft_band(float distance, float radius) {
	float t = clamp(abs(distance) / radius, 0.0, 1.0);
	float shape = 1.0 - t * t;
	return shape * shape * shape;
}
void fragment() {
	vec2 delta = local_position - arc_center;
	float radial = length(delta);
	float angle = atan(delta.y, delta.x);
	float edge = rail_distance(delta, radial, angle, 0.0, 1.0);
	float white = (soft_band(edge, outline_radius) * 0.28 + soft_band(edge, 3.0) * 0.45) * outline_strength;
	float colored = 0.0;
	if (fill_to > fill_from) {
		float fill_edge = rail_distance(delta, radial, angle, fill_from, fill_to);
		// 轻微面光与较柔的外晕共用阵营色，保留半透明填充的背景透视。
		colored = (0.11 * (1.0 - smoothstep(-2.0, 2.0, fill_edge)) + 0.28 * soft_band(fill_edge, fill_radius)) * fill_strength;
	}
	// 直接输出加色能量，避免亮光变成另一层不透明的色块。
	float coverage = clamp(white + colored, 0.0, 1.0);
	COLOR = vec4((outline_color.rgb * white + fill_color.rgb * colored) / max(coverage, 0.0001), coverage * COLOR.a);
}
