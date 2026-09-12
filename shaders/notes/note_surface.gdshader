shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/notes/note_surface.gdshaderinc"
varying vec4 item_color;
void vertex() { item_color = COLOR; }

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float eye = smoothstep(0.72, 0.92, min(texel.r, min(texel.g, texel.b)));
	COLOR = item_color * vec4(note_surface(texel.rgb, eye), texel.a);
}
