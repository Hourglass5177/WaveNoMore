shader_type canvas_item;
render_mode unshaded;

// 静态空间噪声决定每处消散时刻，进度由宿主推进，不逐帧重新随机。
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 design_size = vec2(1920.0, 1080.0);
uniform float grain_size_px : hint_range(1.0, 5.0) = 2.2;
uniform float softness : hint_range(0.01, 0.15) = 0.065;
uniform vec4 dust_color : source_color = vec4(0.76, 0.73, 0.70, 1.0);
uniform float dust_strength : hint_range(0.0, 0.5) = 0.16;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 pixel = UV * design_size;
	vec2 cell = floor(pixel / grain_size_px);
	// 多尺度分布避免变成单向扫屏或整屏同时变灰；细颗粒只在消散边缘出现。
	float field = 0.62 * noise(pixel / 165.0) + 0.38 * noise(pixel / 47.0);
	float threshold = 0.14 + field * 0.60 + hash(cell) * 0.12;
	float cover = 1.0 - smoothstep(threshold - softness, threshold + softness, progress);
	float age = progress - threshold;
	float life = smoothstep(-0.055, 0.0, age) * (1.0 - smoothstep(0.0, 0.085, age));
	vec2 center = vec2(0.25 + hash(cell + 19.0) * 0.5, 0.6 - clamp(age * 3.0, -0.15, 0.3));
	float distance_to_dust = length(fract(pixel / grain_size_px) - center);
	float dust = (1.0 - smoothstep(0.08, 0.34, distance_to_dust)) * step(0.94, hash(cell + 37.0)) * life * dust_strength;
	// 黑幕与少量灰白尘点合成，尘点散尽后完全恢复原画，不残留噪声。
	float alpha = cover + (1.0 - cover) * dust;
	COLOR = vec4(dust_color.rgb * dust / max(alpha, 0.0001), alpha);
}
