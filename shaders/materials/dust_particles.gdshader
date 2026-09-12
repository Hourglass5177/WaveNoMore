shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 dust_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float alpha_strength : hint_range(0.0, 2.0, 0.01) = 0.72;
uniform float twinkle_amount : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float frequency_min_hz : hint_range(0.001, 2.0, 0.001) = 0.16;
uniform float frequency_max_hz : hint_range(0.001, 2.0, 0.001) = 0.48;
uniform float halo_radius_px : hint_range(0.0, 32.0, 0.5) = 5.0;
uniform float halo_strength : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform vec4 halo_color : source_color = vec4(1.0);
// 与对象使用同一粒子图，圆盘采样跨平铺边界连续。
uniform sampler2D dust_texture : source_color, filter_linear, repeat_enable;
uniform vec2 random_grid = vec2(80.0, 45.0);
uniform bool is_live = true;

float hash12(vec2 value) {
	value = fract(value * vec2(123.34, 456.21));
	value += dot(value, value + 45.32);
	return fract(value.x * value.y);
}

void fragment() {
	if ((is_live && SCREEN_UV.y >= 0.5) || (!is_live && SCREEN_UV.y < 0.5)) {
		COLOR = vec4(0.0);
	}
	else {
        vec4 source = texture(TEXTURE, UV);
        float source_alpha = source.a;
        // 同一分块内共享随机参数，避免单个粒子内部出现高频闪烁条纹。
        vec2 particle_cell = floor(UV * random_grid);
        float seed = hash12(particle_cell);
        float phase = seed * TAU;
        float frequency = mix(frequency_min_hz, frequency_max_hz, hash12(particle_cell + 17.13));
        float wave = 0.5 + 0.5 * sin(TIME * TAU * frequency + phase);
        float twinkle = mix(1.0 - twinkle_amount, 1.0 + twinkle_amount, wave);
        float core_alpha = clamp(source_alpha * alpha_strength * twinkle, 0.0, 1.0);
        // 逐纹素覆盖整个圆盘，避免稀疏偏移采样产生重复亮点。
        float radius = clamp(halo_radius_px, 0.0, 32.0);
        float halo_alpha = 0.0;
        int bound = int(ceil(radius));
        for (int y = -bound; y <= bound; y++) {
            for (int x = -bound; x <= bound; x++) {
                vec2 offset = vec2(float(x), float(y));
                float radius_squared = dot(offset, offset) / max(radius * radius, 0.0001);
                if (radius_squared < 1.0) {
                    float weight = exp(-4.5 * radius_squared) * (1.0 - smoothstep(0.75, 1.0, radius_squared));
                    float sample_alpha = clamp(texture(dust_texture, UV + offset * TEXTURE_PIXEL_SIZE).a * weight, 0.0, 1.0);
                    halo_alpha += sample_alpha;
                }
            }
        }
        halo_alpha = clamp(halo_alpha * halo_strength * twinkle, 0.0, 1.0);
        if (radius <= 0.0) { halo_alpha = 0.0; }
        float core = core_alpha * dust_color.a;
        float halo = halo_alpha * halo_color.a;
        // 核心覆盖光晕，只叠加覆盖透明度，不重复叠加相交区域的亮度。
        float visible_halo = halo * (1.0 - core);
        float alpha = core + visible_halo;
        vec3 color = (dust_color.rgb * core + halo_color.rgb * visible_halo) / max(alpha, 0.00001);
        COLOR = vec4(color, alpha);
    }
}
