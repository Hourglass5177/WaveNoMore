shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float strength = 0.0;
uniform float radius_px = 12.0;
uniform vec4 glow_color : source_color = vec4(1.0);
// 常驻主题光只画轮廓外侧；判定白光保留原有面光。
uniform bool edge_only = false;

void fragment() {
	// UV.x 为跨身体的有符号比例，UV.y 为该截面的原半宽。
	float distance_px = abs(UV.x) * (UV.y + radius_px) - UV.y;
	float rim = exp(-distance_px * distance_px / 4.5) * 0.34;
	float halo = exp(-pow(max(distance_px, 0.0) / (radius_px * 0.48), 2.0)) * 0.38;
	float surface_light = 0.30 + 0.06 * exp(-pow(distance_px / radius_px, 2.0));
	float coverage = edge_only ? (distance_px < 0.0 ? 0.0 : rim + halo)
		: (distance_px < 0.0 ? surface_light + rim : rim + halo);
	COLOR = vec4(glow_color.rgb, coverage * strength * glow_color.a * COLOR.a);
}
