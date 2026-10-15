shader_type canvas_item;
render_mode unshaded;

// 起点端帽就是底座。帽面沿物理方向平移，只沿推动轴轻微倾斜，不压扁屏幕 Y 方向。
uniform vec2 recommendation = vec2(0.0);
uniform float base_radius = 52.0;
uniform vec4 body_color : source_color;
uniform vec4 light_color : source_color;
uniform vec4 bone_color : source_color;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }

float ellipse_mask(vec2 q) {
	float d = length(q) - 1.0;
	float aa = max(fwidth(d), 0.012);
	return 1.0 - smoothstep(-aa, aa, d);
}

void fragment() {
	vec2 p = local_position;
	float amount = clamp(length(recommendation), 0.0, 1.0);
	vec2 direction = amount > 0.001 ? recommendation / amount : vec2(0.0, -1.0);
	vec2 cross_axis = vec2(-direction.y, direction.x);
	// 帽面缩至底座的 48%，留出更清晰的沿边转动行程。
	float cap_radius = base_radius * 0.48;
	float radial_radius = cap_radius * mix(1.0, 0.88, amount);
	// 满推时外沿恰好抵住底座外框；斜向与水平/竖直有完全相同的行程。
	vec2 center = direction * (base_radius - radial_radius) * amount;
	vec2 radii = vec2(radial_radius, cap_radius);
	vec2 q = vec2(dot(p - center, direction), dot(p - center, cross_axis)) / radii;
	vec2 side_q = vec2(dot(p - center + direction * amount * 5.0, direction), dot(p - center, cross_axis)) / radii;

	// 补全源泉圆框，不另画悬空小底座。
	float edge = abs(length(p) - base_radius + 1.5);
	float base_edge = 1.0 - smoothstep(0.4, 1.5, edge);
	vec3 color = mix(body_color.rgb, light_color.rgb, 0.5);
	float alpha = base_edge * 0.48;
	float shadow = ellipse_mask(side_q / 1.07) * 0.28;
	color = mix(color, body_color.rgb * 0.30, shadow);
	alpha = max(alpha, shadow);
	float side = ellipse_mask(side_q);
	color = mix(color, mix(body_color.rgb * 0.45, light_color.rgb, 0.16), side);
	alpha = max(alpha, side * 0.84);

	float face = ellipse_mask(q);
	vec2 screen_q = (p - center) / cap_radius;
	float dome = sqrt(max(0.0, 1.0 - dot(q, q)));
	float light = clamp(0.24 + dome * 0.22 - screen_q.y * 0.16 - screen_q.x * 0.10, 0.0, 1.0);
	vec3 face_color = mix(body_color.rgb, light_color.rgb, light);
	// 宽而柔的斜向受光与窄上缘，让近圆帽面读成有厚度的摇杆头。
	float rim = smoothstep(0.92, 0.99, length(q));
	float upper = clamp(0.28 - screen_q.y * 0.6 - screen_q.x * 0.3, 0.0, 1.0);
	face_color = mix(face_color, bone_color.rgb, rim * (0.14 + upper * 0.48));
	float sheen = exp(-dot((screen_q - vec2(-0.28,-0.32)) * vec2(2.8,3.3), (screen_q - vec2(-0.28,-0.32)) * vec2(2.8,3.3)));
	face_color = mix(face_color, bone_color.rgb, sheen * 0.10);
	color = mix(color, face_color, face);
	alpha = max(alpha, face * 0.84);
	COLOR = vec4(color, alpha) * COLOR;
}
