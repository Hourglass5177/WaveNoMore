shader_type canvas_item;
render_mode unshaded, blend_mix;

// 疾振物理波包 Shader。一次有效敲击对应一个有因果来源的径向波包，
// 保留 wave_launched 给出的时间、波源、速度和碰撞宽度；尾随细纹是同一脉冲的衰减波列，
// 玩家没有敲钟时绝不会凭空出现线条或波纹。
// 每侧最多读取 16 个真实疾振波包；必须与 GDScript 上传容量一致。
const int MAX_WAVEFRONTS = 16;
// 2π，用于把“离波前的距离 / 波长”转换为余弦相位。
const float TAU_VALUE = 6.28318530718;

// 全屏画布宽高，单位为像素；用于把 UV 转成与波源相同的坐标。
uniform vec2 field_size_px = vec2(1920.0, 1080.0);
// 整体开关倍率，0 完全关闭，1 正常显示。
uniform float field_enabled : hint_range(0.0, 1.0, 0.001) = 0.0;
// SongClock 给出的绝对视觉时间，单位为秒。
uniform float visual_time_sec = 0.0;

// 生侧数组当前有效波包数，范围 0～MAX_WAVEFRONTS。
uniform int life_wavefront_count = 0;
// 死侧数组当前有效波包数，范围 0～MAX_WAVEFRONTS。
uniform int death_wavefront_count = 0;
// 生侧每个波包的绝对发射秒数；发出后不再修改。
uniform float life_emission_times[MAX_WAVEFRONTS];
// 死侧每个波包的绝对发射秒数。
uniform float death_emission_times[MAX_WAVEFRONTS];
// 生侧各波包速度，单位为像素/秒；数值越大，波前扩散越快。
uniform float life_wave_speeds[MAX_WAVEFRONTS];
// 死侧各波包速度，单位为像素/秒。
uniform float death_wave_speeds[MAX_WAVEFRONTS];
// 生侧真实碰撞带半宽，单位为像素；这里只匹配外观，不在 Shader 中判定。
uniform float life_half_widths[MAX_WAVEFRONTS];
// 死侧真实碰撞带半宽，单位为像素。
uniform float death_half_widths[MAX_WAVEFRONTS];
// 生侧波包最大可见半径，单位为像素；到达后淡出并由 GDScript 移除。
uniform float life_max_radii[MAX_WAVEFRONTS];
// 死侧波包最大可见半径，单位为像素。
uniform float death_max_radii[MAX_WAVEFRONTS];
// 生侧每个波包的波源坐标，单位为画布像素。
uniform vec2 life_origins[MAX_WAVEFRONTS];
// 死侧每个波包的波源坐标，单位为画布像素。
uniform vec2 death_origins[MAX_WAVEFRONTS];

// 生侧波包颜色。
uniform vec4 life_color : source_color = vec4(0.74, 0.12, 0.10, 1.0);
// 死侧波包颜色。
uniform vec4 death_color : source_color = vec4(0.40, 0.44, 0.55, 1.0);
// 两侧相长叠加区域使用的骨白色。
uniform vec4 overlap_color : source_color = vec4(0.98, 0.94, 0.82, 1.0);
// 主波前后方的波列长度，单位为像素；增大后单次敲击拖尾更长。
uniform float packet_length_px : hint_range(24.0, 140.0, 1.0) = 72.0;
// 波包内部明暗条纹的波长，单位为像素；增大后条纹更疏。
uniform float carrier_wavelength_px : hint_range(10.0, 48.0, 0.5) = 22.0;
// 波包拖尾衰减距离，单位为像素；增大后尾部强度下降更慢。
uniform float packet_decay_px : hint_range(12.0, 120.0, 1.0) = 42.0;
// 尾随细纹强度，范围 0～1；0 只保留主波前。
uniform float trail_strength : hint_range(0.0, 1.0, 0.01) = 0.52;
// 最终颜色和透明度倍率，0 不可见，超过 1 会增强亮度。
uniform float field_strength : hint_range(0.0, 1.5, 0.01) = 1.02;
// 生成骨白相长纹所需的最低强度；增大后白色区域减少。
uniform float overlap_threshold : hint_range(0.0, 1.0, 0.001) = 0.045;
// 骨白网点单元边长，单位为像素；增大后颗粒更粗疏。
uniform float stipple_cell_px : hint_range(3.0, 20.0, 0.5) = 7.0;
// 相长区域外围光晕倍率；0 关闭光晕，增大后更亮。
uniform float glow_strength : hint_range(0.0, 2.0, 0.01) = 0.82;

// 根据像素到主波前的有符号距离求 0～1 能量，并在边缘平滑抗锯齿。
float front_energy(float signed_distance_px, float half_width_px) {
	float antialias_px = 2.0;
	return 1.0 - smoothstep(
		max(half_width_px - antialias_px, 0.0),
		half_width_px + antialias_px,
		abs(signed_distance_px)
	);
}

// 波包靠近最大半径时逐渐淡出，避免突然消失。
float distance_fade(float radius_px, float max_radius_px) {
	float radius = max(max_radius_px, 1.0);
	return 1.0 - smoothstep(radius * 0.72, radius, radius_px);
}

// 汇总所有生波包。x 保存带正负号的波峰/波谷贡献，用来判断相长或相消；
// y 保存当前像素的波纹强度，用来把图案限制在波包可见范围内。
vec2 sample_life_train(vec2 pixel) {
	float amplitude = 0.0;
	float energy = 0.0;
	for (int index = 0; index < MAX_WAVEFRONTS; index++) {
		if (index < life_wavefront_count) {
			float age_sec = visual_time_sec - life_emission_times[index];
			float speed = max(life_wave_speeds[index], 0.001);
			float radius_px = max(age_sec, 0.0) * speed;
			float max_radius_px = max(life_max_radii[index], 1.0);
			float active = step(0.0, age_sec) * step(radius_px, max_radius_px);
			float distance_px = distance(pixel, life_origins[index]);
			// 正值表示主波前已经扫过此像素；只在它后方的有限长度内保留拖尾。
			float behind_front_px = radius_px - distance_px;
			float packet_gate = step(0.0, behind_front_px)
				* (1.0 - smoothstep(packet_length_px - 10.0, packet_length_px, behind_front_px));
			float envelope = (1.0 - smoothstep(0.0, max(packet_decay_px, 1.0), max(behind_front_px, 0.0)))
				* packet_gate * active * distance_fade(radius_px, max_radius_px);
			// 距离除以波长得到周期数，再乘 2π 得到余弦相位。
			float phase = TAU_VALUE * behind_front_px / max(carrier_wavelength_px, 1.0);
			float carrier = cos(phase);
			float main_front = front_energy(behind_front_px, life_half_widths[index])
				* active * distance_fade(radius_px, max_radius_px);
			amplitude += carrier * envelope;
			energy = max(energy, max(main_front * 0.58, abs(carrier) * envelope * trail_strength));
		}
	}
	amplitude = amplitude / (1.0 + abs(amplitude) * 0.65);
	return vec2(amplitude, clamp(energy, 0.0, 1.0));
}

// 与生侧相同，但读取死侧波包数组；分开计算后才能比较两侧相位。
vec2 sample_death_train(vec2 pixel) {
	float amplitude = 0.0;
	float energy = 0.0;
	for (int index = 0; index < MAX_WAVEFRONTS; index++) {
		if (index < death_wavefront_count) {
			float age_sec = visual_time_sec - death_emission_times[index];
			float speed = max(death_wave_speeds[index], 0.001);
			float radius_px = max(age_sec, 0.0) * speed;
			float max_radius_px = max(death_max_radii[index], 1.0);
			float active = step(0.0, age_sec) * step(radius_px, max_radius_px);
			float distance_px = distance(pixel, death_origins[index]);
			float behind_front_px = radius_px - distance_px;
			float packet_gate = step(0.0, behind_front_px)
				* (1.0 - smoothstep(packet_length_px - 10.0, packet_length_px, behind_front_px));
			float envelope = (1.0 - smoothstep(0.0, max(packet_decay_px, 1.0), max(behind_front_px, 0.0)))
				* packet_gate * active * distance_fade(radius_px, max_radius_px);
			float phase = TAU_VALUE * behind_front_px / max(carrier_wavelength_px, 1.0);
			float carrier = cos(phase);
			float main_front = front_energy(behind_front_px, death_half_widths[index])
				* active * distance_fade(radius_px, max_radius_px);
			amplitude += carrier * envelope;
			energy = max(energy, max(main_front * 0.58, abs(carrier) * envelope * trail_strength));
		}
	}
	amplitude = amplitude / (1.0 + abs(amplitude) * 0.65);
	return vec2(amplitude, clamp(energy, 0.0, 1.0));
}

// 把连续相长强度变成规则网点；强度越高，单元中的白点越大。
float dot_lattice(vec2 pixel, float intensity) {
	vec2 cell = fract(pixel / max(stipple_cell_px, 1.0)) - vec2(0.5);
	float radius = mix(0.06, 0.38, smoothstep(overlap_threshold, 1.0, intensity));
	return 1.0 - smoothstep(radius, radius + 0.08, length(cell));
}

void fragment() {
	// 第一阶段：分别取得此像素受到的生、死有符号振幅和可见强度。
	vec2 pixel = UV * field_size_px;
	vec2 life_sample = sample_life_train(pixel);
	vec2 death_sample = sample_death_train(pixel);

	// 第二阶段：两侧包络都存在时才会干涉；振幅同号偏向相长，异号偏向相消。
	float life_energy = clamp(max(life_sample.y, abs(life_sample.x) * 0.30), 0.0, 1.0);
	float death_energy = clamp(max(death_sample.y, abs(death_sample.x) * 0.30), 0.0, 1.0);
	float envelope_overlap = life_energy * death_energy;
	float phase_product = life_sample.x * death_sample.x;
	float phase_alignment = 0.5 + 0.5 * clamp(phase_product * 1.4, -1.0, 1.0);
	float constructive = envelope_overlap * mix(0.44, 1.0, phase_alignment);
	float destructive = envelope_overlap * max(-phase_product, 0.0);
	float overlap_gate = smoothstep(overlap_threshold, overlap_threshold + 0.12, constructive);
	float dark_gap = smoothstep(overlap_threshold, overlap_threshold + 0.14, destructive);
	float stipple = dot_lattice(pixel, constructive);
	float white_core = overlap_gate * mix(0.56, 1.0, stipple);
	float white_glow = overlap_gate * constructive * 0.36 * glow_strength;

	// 第三阶段：相长处加入骨白并压低红黑，相消处整体变暗，形成加强带和减弱带。
	float life_only = life_energy * (1.0 - overlap_gate * 0.76);
	float death_only = death_energy * (1.0 - overlap_gate * 0.76);
	vec3 color = life_color.rgb * life_only * 0.56;
	color += death_color.rgb * death_only * 0.56;
	color += overlap_color.rgb * (white_core + white_glow);
	color *= 1.0 - dark_gap * 0.42;

	// 最后合并透明度；field_enabled 为 0 时整张全屏效果不可见。
	float alpha = max(life_only * 0.56, death_only * 0.56);
	alpha = max(alpha, white_core * 0.88 + white_glow);
	alpha *= 1.0 - dark_gap * 0.30;
	alpha = clamp(alpha * field_strength * field_enabled, 0.0, 1.0);
	COLOR = vec4(color * field_strength, alpha);
}
