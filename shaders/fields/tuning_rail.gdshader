shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/fields/tuning_arc_distance.gdshaderinc"
uniform vec4 rail_color : source_color;
uniform vec4 fill_color : source_color;
uniform vec4 outline_color : source_color;
uniform float outline_width = 3.0;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 delta = local_position - arc_center;
	float radial = length(delta);
	float angle = atan(delta.y, delta.x);
	float edge = rail_distance(delta, radial, angle, 0.0, 1.0);
	float aa = max(fwidth(edge), 0.001);
	float rail = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, edge);
	float fill_edge = rail_distance(delta, radial, angle, fill_from, fill_to);
	float fill = (fill_to > fill_from ? 1.0 : 0.0) * (1.0 - smoothstep(-aa * 0.5, aa * 0.5, fill_edge));
	float outline = 1.0 - smoothstep(outline_width * 0.5 - aa * 0.5, outline_width * 0.5 + aa * 0.5, abs(edge));
	// 与旧底轨→填充→描边的透明合成一致，接合处不叠画端帽。
	float alpha = rail * rail_color.a;
	vec3 rgb = rail_color.rgb * alpha;
	float a = fill * fill_color.a;
	rgb = fill_color.rgb * a + rgb * (1.0 - a); alpha = a + alpha * (1.0 - a);
	a = outline * outline_color.a;
	rgb = outline_color.rgb * a + rgb * (1.0 - a); alpha = a + alpha * (1.0 - a);
	COLOR = vec4(rgb / max(alpha, 0.00001), alpha) * COLOR;
}
