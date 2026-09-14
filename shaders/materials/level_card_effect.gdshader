shader_type canvas_item;
render_mode unshaded;

uniform float k = 0.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	color.a *= clamp(k, 0.0, 1.0);
	COLOR = color;
}
