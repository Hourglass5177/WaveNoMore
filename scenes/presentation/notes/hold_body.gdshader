shader_type canvas_item;

// UV.x 是从头部开始的累计弧长 / 重复间距，不随当前总长重新归一化。
uniform sampler2D body_texture : source_color, repeat_enable, filter_linear;
uniform float hold_progress = 0.0;
uniform float remaining_ratio = 1.0;
uniform float body_flow_speed = 0.0;
uniform float body_edge_softness = 0.08;
// 暂时保留原染色实现，默认关闭；场景灯光和外部调制仍然生效。
uniform bool body_tint_enabled = false;
uniform vec4 affinity_color : source_color = vec4(1.0);
// 只抵消 Hold 根节点自身反馈的 RGB，不抵消任何 Alpha 或上级调制。
uniform vec4 hold_self_modulate : source_color = vec4(1.0);
uniform float visual_time_sec = 0.0;
// 仅用于在实际网格末端柔化，不裁剪几何或反推 Gameplay 状态。
uniform float body_uv_length = 0.0;
varying vec4 item_color;

void vertex() {
	// 保存累计调制色；fragment 中仅移除 Hold 自身的 RGB 因子。
	item_color = COLOR;
}

void fragment() {
	// 纵向重复，横向贴图边缘夹到首末像素中心，避免采样到另一侧。
	vec2 half_texel = 0.5 / vec2(textureSize(body_texture, 0));
	vec2 sample_uv = vec2(
		UV.x + visual_time_sec * body_flow_speed,
		clamp(UV.y, half_texel.y, 1.0 - half_texel.y)
	);
	vec4 texel = texture(body_texture, sample_uv);
	float edge = 1.0;
	float tail = 1.0;
	if (body_edge_softness > 0.0) {
		edge = smoothstep(0.0, body_edge_softness, UV.y)
			* smoothstep(0.0, body_edge_softness, 1.0 - UV.y);
		tail = smoothstep(0.0, body_edge_softness, body_uv_length - UV.x);
	}
	vec3 body_rgb = texel.rgb;
	if (body_tint_enabled) {
		// 原阵营、判定染色和中轴高光保留，只有显式开启时使用。
		float center_light = pow(max(1.0 - abs(UV.y * 2.0 - 1.0), 0.0), 4.0);
		vec3 tint = affinity_color.rgb * (1.0 + center_light * (0.08 + 0.04 * hold_progress));
		body_rgb *= tint;
	}
	// 当前根节点反馈的 RGB 均非零。环境调制保留，灯光使用默认 CanvasItem 路径。
	vec3 environment_rgb = item_color.rgb / hold_self_modulate.rgb;
	float finish_fade = smoothstep(0.0, 0.04, remaining_ratio);
	COLOR = vec4(body_rgb * environment_rgb, texel.a * affinity_color.a * edge * tail * finish_fade * item_color.a);
}
