shader_type canvas_item;
render_mode unshaded, blend_add;

uniform bool ring_mode = false;
uniform float sweep_direction = 1.0;
uniform vec4 ring_data; // 固定半径、缩圈半径、进度、缩圈 alpha。
uniform vec4 glow_data; // 两条光带半宽、两条光带强度。
uniform vec4 halo_color : source_color;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

float band(float distance, float width) {
	float value = max(0.0, 1.0 - distance * distance / (width * width));
	return value * value * value;
}

// UV.y 是横向归一化距离；UV.x 在裁切端部收束，闭合圆环始终为 1。
void fragment() {
	if (ring_mode) {
		// 普通圆环只更新进度 uniform，不逐帧重建圆弧顶点与 GPU 缓冲。
		float radius = length(local_position);
		float angle = mod((atan(local_position.y, local_position.x) + 1.570796327) * sweep_direction + 6.283185307, 6.283185307);
		float sweep = 6.283185307 * ring_data.z;
		float along = min(angle, sweep - angle) * ring_data.x;
		float cap = ring_data.z >= 0.99999 ? 1.0 : smoothstep(0.0, glow_data.x, along);
		float progress = band(radius - ring_data.x, glow_data.x) * cap * glow_data.z;
		float approach = band(radius - ring_data.y, glow_data.y) * glow_data.w * ring_data.w;
		COLOR = vec4(halo_color.rgb, (progress + approach) * COLOR.a);
	} else {
		float cross_fade = max(0.0, 1.0 - UV.y * UV.y);
		float end_fade = smoothstep(0.0, 1.0, UV.x);
		COLOR.a *= cross_fade * cross_fade * cross_fade * end_fade;
	}
}
