shader_type canvas_item;
render_mode unshaded;

uniform sampler2D chosen_texture;
uniform sampler2D unchosen_texture;
uniform float k = 1.0;

void fragment() {
    vec4 chosen = texture(chosen_texture, UV);
    chosen.a *= k;
    vec4 unchosen = texture(unchosen_texture, UV);
    unchosen.a *= 1.0 - k;
    float alpha = chosen.a + unchosen.a * (1.0 - chosen.a);
    vec3 rgb = chosen.rgb * chosen.a + unchosen.rgb * unchosen.a * (1.0 - chosen.a);
    COLOR = vec4(rgb / max(alpha, 0.00001), alpha);
}
