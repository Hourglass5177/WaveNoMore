shader_type canvas_item;
render_mode unshaded;

uniform float stength = 0.0;
uniform vec4 target_color : source_color;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    vec4 final_color = vec4(mix(tex_color.rgb, target_color.rgb, stength), tex_color.a);
    COLOR = final_color;
}
