shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/characters/pet_world_color.gdshaderinc"
uniform float amount = 0.0;
void fragment() {
	// R 是三眼原始轮廓，G 是生成阶段预滤的柔晕，运行时无需多次模糊采样。
	// QuadMesh 的纵向 UV 与 PNG 图像坐标相反；位置仍沿用头骨的原图坐标。
	vec2 mask = texture(TEXTURE,vec2(UV.x,1.0-UV.y)).rg;
	float alpha = max(mask.r,mask.g*1.35)*amount;
	COLOR = vec4(pet_world_color(vec3(.985,.99,1.0)),alpha);
}
