shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float strength = 0.0;
uniform float radius_px = 22.0;
uniform vec4 glow_color : source_color = vec4(1.0);
// 常驻主题光只画轮廓外侧；判定白光保留原有面光。
uniform bool edge_only = false;

void fragment() {
	// UV.x 为跨身体的有符号比例，UV.y 为该截面的原半宽。
	float distance_px = abs(UV.x) * (UV.y + radius_px) - UV.y;
	// 使用较宽的衰减曲线，确保深色主题在透明混合后仍然清晰可见。
	float rim = exp(-distance_px * distance_px / 10.0) * 0.92;
	float halo = exp(-pow(max(distance_px, 0.0) / (radius_px * 0.72), 2.0)) * 0.96;
	float surface_light = 0.30 + 0.06 * exp(-pow(distance_px / radius_px, 2.0));
	float coverage = edge_only ? (distance_px < 0.0 ? 0.0 : rim + halo)
		: (distance_px < 0.0 ? surface_light + rim : rim + halo);
	float glow_alpha = clamp(coverage * strength * glow_color.a * COLOR.a, 0.0, 0.92);
	COLOR = vec4(glow_color.rgb, glow_alpha);
}
