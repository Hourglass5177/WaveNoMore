// 共用漆色映射。保留原明度起伏；浅色眼白单独保留，避免红色盖住瞳孔。
uniform bool life_tint = false;
uniform bool effects_enabled = true;
uniform vec4 lacquer_shadow : source_color = vec4(0.27, 0.125, 0.122, 1.0);
uniform vec4 lacquer_base : source_color = vec4(0.53, 0.22, 0.18, 1.0);
uniform vec4 lacquer_highlight : source_color = vec4(0.73, 0.345, 0.255, 1.0);
uniform vec4 surface_color : source_color = vec4(0.25, 0.39, 0.40, 1.0);
uniform vec4 white_color : source_color = vec4(0.90, 0.867, 0.788, 1.0);
uniform float surface_strength = 0.18;
uniform float white_strength = 0.48;
uniform float condition_light = 0.0;
uniform float body_brightness = 1.0;
uniform float aura_amount = 1.0;

vec3 note_surface(vec3 original, float eye_mask) {
	if (!effects_enabled) return original * body_brightness;
	float lum = dot(original, vec3(0.2126, 0.7152, 0.0722));
	vec3 lacquer = mix(lacquer_shadow.rgb, lacquer_base.rgb, smoothstep(0.0, 0.34, lum));
	lacquer = mix(lacquer, lacquer_highlight.rgb, smoothstep(0.34, 1.0, lum));
	// 黑纹仍较深，但不直接乘红色导致青黑素材完全发黑。
	lacquer *= mix(0.63, 1.0, smoothstep(0.0, 0.13, lum));
	vec3 color = life_tint ? mix(lacquer, original, eye_mask) : original;
	color = mix(color, max(color, surface_color.rgb), surface_strength * aura_amount * (1.0 - eye_mask * 0.8));
	color = mix(color, white_color.rgb, condition_light * white_strength);
	return color * body_brightness;
}
