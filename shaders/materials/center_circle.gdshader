shader_type canvas_item;
render_mode unshaded;

uniform float left_edge_distance = 1.0;
uniform float right_edge_distance = 1.0;
uniform float live_move = 0.0;
uniform float death_move = 0.0;

void vertex() {
    VERTEX.x += live_move + death_move;
}

void fragment() {
    float center_x = UV.x - 0.5;
    float center_y = UV.y - 0.5;
    float r_plus_l = right_edge_distance + left_edge_distance;
    float r_minus_l = right_edge_distance - left_edge_distance;
    float original_x = (0.5 * r_plus_l * center_x) / (1.0 - r_minus_l * center_x);
    float original_y = center_y * (r_minus_l * original_x + 0.5 *r_plus_l);
    COLOR = texture(TEXTURE, vec2(original_x + 0.5, original_y + 0.5));
}
