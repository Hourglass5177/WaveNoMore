shader_type canvas_item;
render_mode unshaded, blend_mix;

// 线性距离遮罩含 64 px 透明留边，仅需一次采样，宽度可以全局调节。
uniform sampler2D glow_mask : filter_linear, repeat_disable;
uniform vec4 halo_color : source_color;
uniform vec4 rim_color : source_color;
uniform float strength = 0.8;
uniform float radius_px = 36.0;
uniform float rim_px = 3.0;
uniform vec4 mask_rect;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 uv = (local_position - mask_rect.xy) / mask_rect.zw;
	float distance_px = (texture(glow_mask, uv).r - 0.5) * 128.0;
	float rim = exp(-pow(distance_px / rim_px, 2.0)) * 0.70;
	float halo = exp(-pow(max(distance_px, 0.0) / (radius_px * 0.50), 2.0)) * 0.65;
	float exterior = smoothstep(-1.0, 1.0, distance_px);
	COLOR = vec4(mix(halo_color.rgb, rim_color.rgb, rim / max(rim + halo, 0.001)),
		clamp((rim + halo) * strength * exterior, 0.0, 0.82)) * COLOR;
}
