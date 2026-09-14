shader_type canvas_item;
render_mode unshaded;

uniform float k = 1.0;
uniform sampler2D unchosen_texture;

void fragment() {
    vec4 source = texture(TEXTURE, UV);
    source.a *= k;
    vec4 unchosen = texture(unchosen_texture, UV);
    unchosen.a *= 1.0 - k;
    float alpha = source.a + unchosen.a * (1.0 - source.a);
    vec3 rgb = source.rgb * source.a + unchosen.rgb * unchosen.a * (1.0 - source.a);
    COLOR = vec4(rgb / max(alpha, 0.00001), alpha);
}
