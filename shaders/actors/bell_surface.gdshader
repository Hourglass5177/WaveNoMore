shader_type canvas_item;
render_mode unshaded;
uniform vec4 faction_color : source_color;
uniform vec4 white_color : source_color;
uniform float strike = 0.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float value = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	// 保留金属底色与细颗粒，敲击提亮纹理而非覆盖成纯白剪影。
	vec3 metal = mix(source.rgb, faction_color.rgb * (0.55 + value * 0.8), 0.24);
	metal += mix(faction_color.rgb, white_color.rgb, 0.64) * strike * (0.16 + value * 0.34);
	COLOR = tint * vec4(metal, source.a);
}
