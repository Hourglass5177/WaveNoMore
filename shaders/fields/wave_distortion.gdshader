shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 canvas_size = vec2(1920.0, 1080.0);
uniform vec2 pixel_x = vec2(1.0, 0.0);
uniform vec2 pixel_y = vec2(0.0, 1.0);
uniform vec2 life_source;
uniform vec2 death_source;
uniform float wave_speed_px_sec = 2400.0;
uniform float max_radius_px = 2400.0;
uniform float visual_time_sec = 0.0;
uniform int life_wavefront_count = 0;
uniform int death_wavefront_count = 0;
uniform float life_emission_times[16];
uniform float death_emission_times[16];
uniform float displacement_px = 2.0;
uniform float band_half_width_px = 24.0;
uniform float total_limit_px = 3.0;
uniform float source_fade_px = 48.0;
uniform float far_strength = 0.35;
uniform float edge_fade_px = 24.0;
varying vec2 design_position;

void vertex() { design_position = VERTEX; }

float front(float distance_px, float emitted) {
	float radius = (visual_time_sec - emitted) * wave_speed_px_sec;
	float u = clamp((distance_px - radius) / band_half_width_px, -1.0, 1.0);
	// 有限波带内压缩—回弹；边界上的值和一阶导数均为零。
	float envelope = 1.0 - u * u;
	float profile = 3.493856 * u * envelope * envelope;
	float birth = smoothstep(0.0, source_fade_px, radius);
	float travel = mix(1.0, far_strength, smoothstep(0.0, max_radius_px, radius));
	return profile * birth * travel;
}

void fragment() {
	vec2 life_delta = design_position - life_source;
	vec2 death_delta = design_position - death_source;
	float life_distance = length(life_delta);
	float death_distance = length(death_delta);
	float life = 0.0;
	float death = 0.0;
	for (int i = 0; i < life_wavefront_count; i++) life += front(life_distance, life_emission_times[i]);
	for (int i = 0; i < death_wavefront_count; i++) death += front(death_distance, death_emission_times[i]);
	vec2 offset = (life_delta / max(life_distance, 0.001) * life + death_delta / max(death_distance, 0.001) * death) * displacement_px;
	offset *= min(1.0, total_limit_px / max(length(offset), 0.001));
	vec2 edge = min(design_position, canvas_size - design_position);
	offset *= smoothstep(0.0, edge_fade_px, min(edge.x, edge.y));
	vec2 screen_edge = min(SCREEN_UV, vec2(1.0) - SCREEN_UV) / SCREEN_PIXEL_SIZE;
	offset *= smoothstep(0.0, edge_fade_px, min(screen_edge.x, screen_edge.y));
	vec2 sample_uv = SCREEN_UV + (pixel_x * offset.x + pixel_y * offset.y) * SCREEN_PIXEL_SIZE;
	COLOR = textureLod(screen_texture, clamp(sample_uv, SCREEN_PIXEL_SIZE * 0.5, vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5), 0.0);
}
