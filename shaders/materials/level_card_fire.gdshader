shader_type canvas_item;
render_mode unshaded;

uniform float k = 0.0;

void fragment() {
    COLOR = texture(TEXTURE, UV) * k;
}
