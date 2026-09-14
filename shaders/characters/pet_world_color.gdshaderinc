// 三种随从材质共用死界去色；保留原透明度，参数只属于当前实例。
uniform float world_gray = 0.0;
uniform float world_brightness = 1.0;
vec3 pet_world_color(vec3 rgb) {
	float gray = dot(rgb,vec3(0.299,0.587,0.114));
	return mix(rgb,vec3(gray),world_gray)*world_brightness;
}
