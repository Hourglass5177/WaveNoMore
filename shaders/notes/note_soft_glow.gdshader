shader_type canvas_item;
render_mode unshaded, blend_mix;

// 光效使用音符局部坐标，外扩绘制区域让柔光完整落在原轮廓之外。
uniform float strength = 0.0;
uniform float radius_px = 12.0;
uniform int point_count = 0;
uniform vec2 points[16];
uniform bool textured = false;
uniform sampler2D silhouette : filter_linear, repeat_disable;
uniform vec4 texture_rect;
// 头尾接入身体处隐藏内部亮边，只保留外轮廓，避免分件叠出白色接缝。
uniform bool attached = false;
uniform vec2 attachment_origin;
uniform vec2 attachment_direction;
uniform float attachment_width = 0.0;
varying vec2 local_position;

void vertex() { local_position = VERTEX; }

float mask_at(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 0.0;
	return texture(silhouette, uv).a;
}

void fragment() {
	float coverage;
	if (textured) {
		vec2 uv = (local_position - texture_rect.xy) / texture_rect.zw;
		float center = mask_at(uv);
		float near_mask = 0.0;
		float far_mask = 0.0;
		float inner_mask = 1.0;
		for (int i = 0; i < 12; i++) {
			float angle = float(i) * 6.2831853 / 12.0;
			vec2 step_uv = vec2(cos(angle), sin(angle)) / texture_rect.zw;
			float near_sample = mask_at(uv + step_uv * 1.5);
			near_mask += near_sample / 12.0;
			inner_mask = min(inner_mask, near_sample);
			far_mask += mask_at(uv + step_uv * radius_px * 0.45) / 12.0;
		}
		coverage = center * 0.30 + (center - inner_mask) * 0.25
			+ (1.0 - center) * (near_mask * 0.55 + far_mask * 0.48);
	} else {
		float distance_px = 100000.0;
		bool inside = false;
		for (int i = 0; i < 16; i++) {
			if (i >= point_count) break;
			vec2 a = points[i];
			vec2 b = points[(i + 1) % point_count];
			vec2 segment = b - a;
			vec2 closest = a + segment * clamp(dot(local_position - a, segment) / dot(segment, segment), 0.0, 1.0);
			distance_px = min(distance_px, length(local_position - closest));
			if ((a.y > local_position.y) != (b.y > local_position.y)) {
				if (local_position.x < (b.x - a.x) * (local_position.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
			}
		}
		float rim = exp(-distance_px * distance_px / 4.5) * 0.34;
		float halo = exp(-pow(distance_px / (radius_px * 0.48), 2.0)) * 0.38;
		vec2 join_offset = local_position - attachment_origin;
		float along = dot(join_offset, attachment_direction);
		float across = abs(dot(join_offset, vec2(-attachment_direction.y, attachment_direction.x)));
		float join_mask = attached ? smoothstep(-1.5, 1.5, along)
			* (1.0 - smoothstep(attachment_width - 1.0, attachment_width + 1.0, across)) : 0.0;
		// 面光与边缘有连续的亮度层次，纹理仍透出，避免只剩一圈硬描边。
		float surface_light = 0.30 + 0.06 * exp(-pow(distance_px / radius_px, 2.0));
		coverage = (inside ? surface_light : 0.0) + (inside ? rim : rim + halo) * (1.0 - join_mask);
	}
	COLOR = vec4(vec3(1.0), coverage * strength * COLOR.a);
}
