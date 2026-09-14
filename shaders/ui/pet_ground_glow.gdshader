shader_type canvas_item;
render_mode unshaded;
uniform vec4 glow_color : source_color = vec4(0.78,0.19,0.31,1.0);
uniform float strength : hint_range(0.0,1.5) = 0.85;
void fragment() {
	// 扁椭圆的色光与接触暗芯连续收束，边界归零；不用灯光、模糊或循环噪声。
	vec2 p = (UV-0.5)*2.0;
	float r = length(p);
	float fade = 1.0-smoothstep(0.55,1.0,r);
	float glow = exp(-4.5*dot(p,p))*fade;
	float core = exp(-24.0*dot(p,p));
	vec3 tint = mix(glow_color.rgb,glow_color.rgb*0.18,core*0.65);
	COLOR = vec4(tint,glow*strength)*COLOR;
}
