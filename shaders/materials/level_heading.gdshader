shader_type canvas_item;
render_mode unshaded;

uniform float transparency = 1.0;

void fragment() {
    COLOR = texture(TEXTURE, UV);
    COLOR.a *= transparency;
}
