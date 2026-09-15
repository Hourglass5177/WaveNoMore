shader_type canvas_item;
render_mode unshaded;
uniform vec4 halo_color : source_color;
uniform vec4 rim_color : source_color;
uniform float strength = 0.42;
uniform float distance_unit_px = 1.0;
uniform float radius_px = 22.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	float d = (texture(TEXTURE, UV).r - 0.5) * 128.0 * distance_unit_px;
	float outside = smoothstep(-1.5, 1.0, d);
	float rim = exp(-pow(d / 2.2, 2.0)) * 0.30;
	float halo = exp(-pow(max(d, 0.0) / (radius_px * 0.5), 2.0)) * 0.64;
	float edge = 1.0 - smoothstep(radius_px * 0.8, radius_px, d);
	// 距离场灰度不是透明度，不能再次乘默认纹理采样。
	COLOR = tint * vec4(mix(halo_color.rgb, rim_color.rgb, rim / max(rim + halo, 0.001)),
		min((rim + halo) * outside * edge * strength, 0.85));
}
