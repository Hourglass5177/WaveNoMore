// 本体与漆片共用眼球合成，避免击碎瞬间恢复原眼球或给睫毛重新染色。
uniform sampler2D musk_texture : filter_linear, repeat_disable;
uniform sampler2D lash_texture : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D eye_ball_texture : source_color, filter_linear, repeat_disable;
uniform float eye_hit_progress = 0.0;
uniform float eye_enlarge = 1.2;

vec4 note_eye(vec4 base, vec2 uv, vec2 moving_uv) {
	vec2 eye_uv = (moving_uv - vec2(0.5)) / mix(1.0, eye_enlarge, eye_hit_progress) + vec2(0.5);
	vec4 eye = texture(eye_ball_texture, eye_uv);
	float inside = step(0.0, eye_uv.x) * step(eye_uv.x, 1.0) * step(0.0, eye_uv.y) * step(eye_uv.y, 1.0);
	float mask = texture(musk_texture, uv).r;
	float coverage = eye.a * mask * inside;
	float alpha = coverage + base.a * (1.0 - coverage);
	vec3 composed = (eye.rgb * coverage + base.rgb * base.a * (1.0 - coverage)) / max(alpha, 0.00001);
	float lashes = texture(lash_texture, uv).r;
	float protected_detail = max(mask, lashes);
	vec3 color = note_surface(composed, protected_detail);
	// 原色保护不等于避光：眼眶与可动瞳孔一起接受条件白光，睫毛仍保持中性。
	// 只提亮，避免将原本浅色的眼白压暗；沿用本体强度以保留瞳孔层次。
	if (effects_enabled) {
		float eye_light = mask * (1.0 - lashes) * condition_light * white_strength;
		color = mix(color, max(color, white_color.rgb * body_brightness), eye_light);
	}
	// 已命中的本体保持暗淡，眼球单独褪白，不能被 45% 的本体亮度压成灰色。
	color = mix(color, white_color.rgb, coverage * eye_hit_progress);
	return vec4(color, alpha);
}
