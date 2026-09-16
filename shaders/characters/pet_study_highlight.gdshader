shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/characters/pet_world_color.gdshaderinc"
uniform bool locked_preview = false;
uniform float amount = 0.0;
uniform int pet_kind = 0;
uniform vec4 detail_region = vec4(0.5, 0.5, 1.0, 1.0);
varying vec4 vertex_color;
void vertex() {
	vertex_color = COLOR;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV) * vertex_color;
	// 只提亮原画中的暖色细节，黑色身体与面部轮廓保持原色。
	float warm = smoothstep(0.35, 0.70, base.r) * smoothstep(0.25, 0.65, base.g);
	// 蝠的辅助亮度仅落在胸口圆纹，眼睛与翅膀花纹不随技能发亮。
	if (pet_kind == 0) warm *= 1.0 - smoothstep(0.72, 1.0, length((UV-detail_region.xy)/detail_region.zw));
	if (pet_kind == 2) warm = 0.0;
	base.rgb = mix(base.rgb, vec3(1.0, 0.98, 0.88), amount * warm * (pet_kind == 0 ? 0.72 : 0.26));
	COLOR = vec4(locked_preview ? vec3(0.0) : pet_world_color(base.rgb),base.a);
}
