shader_type canvas_item;
render_mode unshaded;

uniform vec2 shadow_offset = vec2(-50.0, 50.0);
uniform float image_transparency = 1.0;
uniform sampler2D shadow_texture;

void fragment() {
    vec4 source = texture(TEXTURE, UV);
    // vec4 shadow = vec4(vec3(0.0), texture(TEXTURE, UV - shadow_offset * TEXTURE_PIXEL_SIZE).a);
    vec4 shadow = vec4(vec3(0.0),
                texture(TEXTURE, UV - shadow_offset * TEXTURE_PIXEL_SIZE).a * min(sqrt(texture(shadow_texture, UV).r), 1.0));
    // vec4 shadow = vec4(vec3(0.0),
    //             texture(TEXTURE, UV - shadow_offset * TEXTURE_PIXEL_SIZE).a * min(texture(shadow_texture, UV).r, 1.0));
    source.a *= image_transparency;
    float alpha = source.a + shadow.a * (1.0 - source.a);
    vec3 rgb = source.rgb * source.a + shadow.rgb * shadow.a * (1.0 - source.a);
    COLOR = vec4(rgb / max(alpha, 0.00001), alpha);
}