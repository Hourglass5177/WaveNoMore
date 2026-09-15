shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_texture : source_color, filter_linear, repeat_disable;
uniform vec4 source_region;
uniform vec2 drawn_size;
uniform float padding_px = 16.0;
uniform float radius_px = 8.0;
uniform vec4 glow_color : source_color;
uniform vec4 edge_color : source_color;
uniform float strength = 0.3;
uniform float halo_softness = 1.0;
float alpha_at(vec2 p) {
	// 明确裁切原图的有效区域，不能采到 Atlas 外的透明留白或邻近内容。
	if (any(lessThan(p,vec2(0.0))) || any(greaterThan(p,vec2(1.0)))) return 0.0;
	return texture(source_texture, source_region.xy + p * source_region.zw).a;
}
void fragment() {
	vec2 p = (UV * (drawn_size + 2.0 * padding_px) - padding_px) / drawn_size;
	float weights[5] = float[5](1.0,4.0,6.0,4.0,1.0);
	float halo = 0.0;
	for (int y=0;y<5;y++) {
		for (int x=0;x<5;x++) {
			halo += alpha_at(p + vec2(float(x-2),float(y-2)) * radius_px * 0.5 / drawn_size) * weights[x] * weights[y];
		}
	}
	float coverage = halo / 256.0;
	vec3 tint = mix(glow_color.rgb, edge_color.rgb, smoothstep(0.25, 0.8, coverage));
	COLOR *= vec4(tint, pow(coverage, halo_softness) * strength * glow_color.a);
}
