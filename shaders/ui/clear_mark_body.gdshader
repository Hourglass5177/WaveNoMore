shader_type canvas_item;
render_mode unshaded;
uniform vec4 light_color : source_color;
uniform float lift = 0.08;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
void fragment() {
	vec4 ink = texture(TEXTURE,UV);
	// 仅向浅金轻微靠近，保留原有明暗和透明边缘。
	COLOR = vertex_tint * vec4(mix(ink.rgb, max(ink.rgb,light_color.rgb),lift),ink.a);
}
