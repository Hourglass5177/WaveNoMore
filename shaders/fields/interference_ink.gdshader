shader_type canvas_item;
render_mode unshaded, blend_mix;

// 双钟持续载波相纹 Shader。数组由领域层的权威载波历史转换而来，保存每圈不会再更改的
// 视觉发射时间；频率不进入 Shader，已经发出的每一圈始终保持同一传播速度。
// 每侧最多读取 16 个波前；固定上限让不同显卡都能编译同一长度的数组循环。
const int MAX_WAVEFRONTS = 16;

// 画布宽高，单位为像素；把 0～1 的 UV 转成与 GDScript 相同的坐标。
uniform vec2 field_size_px = vec2(1920.0, 1080.0);
// 生钟波源坐标，单位为画布像素。
uniform vec2 life_source_px = vec2(350.0, 280.0);
// 死钟波源坐标，单位为画布像素；默认与生钟关于画布中心对称。
uniform vec2 death_source_px = vec2(1570.0, 800.0);

// 整个效果的开关倍率，0 完全关闭，1 正常显示。
uniform float field_enabled : hint_range(0.0, 1.0, 0.001) = 0.0;
// SongClock 给出的绝对视觉时间，单位为秒；半径由它减去发射时间得到。
uniform float visual_time_sec = 0.0;
// 固定传播速度，单位为像素/秒；增大后圆环扩散更快，但发圈频率不变。
uniform float wave_speed_px_sec : hint_range(100.0, 4000.0, 1.0) = 2400.0;
// 波前最大可见半径，单位为像素；增大后圆环保留到更远处。
uniform float max_visible_radius_px : hint_range(100.0, 4000.0, 1.0) = 2300.0;
// 生侧发射时间数组当前有效元素数，范围 0～MAX_WAVEFRONTS。
uniform int life_wavefront_count = 0;
// 死侧发射时间数组当前有效元素数，范围 0～MAX_WAVEFRONTS。
uniform int death_wavefront_count = 0;
// 每条生波前的绝对发射秒数；元素加入后不再随调频修改。
uniform float life_emission_times[MAX_WAVEFRONTS];
// 每条死波前的绝对发射秒数；与生侧数组独立。
uniform float death_emission_times[MAX_WAVEFRONTS];
// 单条波带半宽，单位为像素；增大后完整波带更厚，也更容易与另一侧重叠。
uniform float band_half_width_px : hint_range(2.0, 80.0, 0.5) = 30.0;
// 两侧游标是否正处于自己的有效引导带；只增强显示，不参与领域判定。
uniform float life_guide_aligned : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float death_guide_aligned : hint_range(0.0, 1.0, 1.0) = 0.0;
// 贴合时的波带宽度和亮度倍率。
uniform float aligned_band_scale : hint_range(1.0, 1.8, 0.01) = 1.22;
uniform float aligned_brightness_scale : hint_range(1.0, 1.8, 0.01) = 1.24;

// 生波颜色，对应右键 / J 的有效敲击。
uniform vec4 life_color : source_color = vec4(0.74, 0.12, 0.10, 1.0);
// 死波颜色，对应左键 / F 的有效敲击。
uniform vec4 death_color : source_color = vec4(0.40, 0.44, 0.55, 1.0);
// 生死波带真正重叠时使用的骨白色；单侧成波不会凭空出现白纹。
uniform vec4 overlap_color : source_color = vec4(0.98, 0.94, 0.82, 1.0);
// 最终颜色和透明度倍率，0 不可见，超过 1 会增强亮度。
uniform float field_strength : hint_range(0.0, 1.5, 0.001) = 1.02;
// 显示骨白重叠纹的最低强度；增大后白色区域缩小。
uniform float overlap_threshold : hint_range(0.0, 1.0, 0.001) = 0.055;
// 骨白网点单元边长，单位为像素；增大后颗粒更粗、更疏。
uniform float stipple_cell_px : hint_range(3.0, 20.0, 0.5) = 7.0;
// 重叠区域外围光晕倍率，0 关闭光晕，增大后边缘更亮。
uniform float glow_strength : hint_range(0.0, 2.0, 0.01) = 1.20;

// 把像素到波前中心线的距离换成 0～1 能量，并留出抗锯齿过渡。
float front_energy(float distance_to_front_px, float half_width_px) {
	float antialias_px = 2.0;
	return 1.0 - smoothstep(
		max(half_width_px - antialias_px, 0.0),
		half_width_px + antialias_px,
		distance_to_front_px
	);
}

// 波离开主要画面后逐渐淡出，避免到最大半径时突然消失。
float source_distance_fade(float distance_px) {
	float radius = max(max_visible_radius_px, 1.0);
	return 1.0 - smoothstep(radius * 0.70, radius, distance_px);
}

// 汇总此像素受到的所有生波；x 是宽波带能量，y 是窄亮前沿能量。
vec2 sample_life_train(float distance_px) {
	float broad = 0.0;
	float narrow = 0.0;
	float width_scale = mix(1.0, aligned_band_scale, life_guide_aligned);
	for (int index = 0; index < MAX_WAVEFRONTS; index++) {
		if (index < life_wavefront_count) {
			float age_sec = visual_time_sec - life_emission_times[index];
			float radius_px = max(age_sec, 0.0) * wave_speed_px_sec;
			float active = step(0.0, age_sec) * step(radius_px, max_visible_radius_px);
			float distance_to_front_px = abs(distance_px - radius_px);
			broad = max(broad, front_energy(distance_to_front_px, band_half_width_px * width_scale) * active);
			narrow = max(narrow, front_energy(distance_to_front_px, 3.2 * width_scale) * active);
		}
	}
	float fade = source_distance_fade(distance_px);
	return vec2(broad * fade, narrow * fade);
}

// 与生侧相同，但读取死波发射时间数组。
vec2 sample_death_train(float distance_px) {
	float broad = 0.0;
	float narrow = 0.0;
	float width_scale = mix(1.0, aligned_band_scale, death_guide_aligned);
	for (int index = 0; index < MAX_WAVEFRONTS; index++) {
		if (index < death_wavefront_count) {
			float age_sec = visual_time_sec - death_emission_times[index];
			float radius_px = max(age_sec, 0.0) * wave_speed_px_sec;
			float active = step(0.0, age_sec) * step(radius_px, max_visible_radius_px);
			float distance_to_front_px = abs(distance_px - radius_px);
			broad = max(broad, front_energy(distance_to_front_px, band_half_width_px * width_scale) * active);
			narrow = max(narrow, front_energy(distance_to_front_px, 3.2 * width_scale) * active);
		}
	}
	float fade = source_distance_fade(distance_px);
	return vec2(broad * fade, narrow * fade);
}

// 将连续重叠强度变成规则网点；强度越高，单元中的白点越大。
float dot_lattice(vec2 pixel, float intensity) {
	vec2 cell = fract(pixel / max(stipple_cell_px, 1.0)) - vec2(0.5);
	float radius = mix(0.06, 0.38, smoothstep(overlap_threshold, 1.0, intensity));
	return 1.0 - smoothstep(radius, radius + 0.08, length(cell));
}

void fragment() {
	// 第一阶段：把 UV 换成像素坐标，再计算它到两口钟的距离和波带能量。
	vec2 pixel = UV * field_size_px;
	float life_distance = distance(pixel, life_source_px);
	float death_distance = distance(pixel, death_source_px);
	vec2 life_sample = sample_life_train(life_distance);
	vec2 death_sample = sample_death_train(death_distance);

	// 第二阶段：只有生、死两条波带的可见范围真正重叠，才生成骨白相纹。
	float overlap = life_sample.x * death_sample.x;
	float overlap_gate = smoothstep(overlap_threshold, overlap_threshold + 0.10, overlap);
	float stipple = dot_lattice(pixel, overlap);
	// 网点只负责纹理变化，不能把网点间的真实叠加区挖空。
	float dual_alignment = min(life_guide_aligned, death_guide_aligned);
	float overlap_emphasis = mix(1.0, 1.25, dual_alignment);
	float white_core = overlap_gate * mix(0.52, 1.0, stipple) * overlap_emphasis;
	float white_glow = overlap_gate * overlap * 0.34 * glow_strength * overlap_emphasis;

	// 第三阶段：保留各自的窄亮前沿，并在骨白区域压低红黑，避免三色糊在一起。
	float life_emphasis = mix(1.0, aligned_brightness_scale, life_guide_aligned);
	float death_emphasis = mix(1.0, aligned_brightness_scale, death_guide_aligned);
	float life_only = (life_sample.y * 0.92 + life_sample.x * 0.08) * (1.0 - overlap_gate * 0.84) * life_emphasis;
	float death_only = (death_sample.y * 0.92 + death_sample.x * 0.08) * (1.0 - overlap_gate * 0.84) * death_emphasis;
	vec3 color = life_color.rgb * life_only * 0.72;
	color += death_color.rgb * death_only * 0.72;
	color += overlap_color.rgb * (white_core + white_glow);

	// 最后合并透明度；场强只在最终透明度乘一次，避免颜色与透明度同时缩放造成平方衰减。
	float alpha = max(life_only * 0.72, death_only * 0.72);
	alpha = max(alpha, white_core * 0.92 + white_glow);
	alpha = clamp(alpha * field_strength * field_enabled, 0.0, 1.0);
	COLOR = vec4(color, alpha);
}
