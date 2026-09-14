shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/characters/pet_world_color.gdshaderinc"
uniform float age = -1.0;
uniform float duration = 0.75;
uniform float length_px = 21.333333;
uniform float width_px = 7.333333;
uniform float phase = 0.0;

// 短而弯曲的火舌，几何边缘稍软，主体保持原画式的清晰色块。
float tongue(vec2 p, float reach, float width, float bend) {
	float u = clamp(p.x / reach, 0.0, 1.0);
	float center = bend*u*u + sin(u*8.0-age*21.0+phase)*u*0.20;
	float radius = width*(0.18 + pow(max(sin(u*3.14159265),0.0),0.8))*(1.0-u*0.45);
	return max(abs(p.y-center)-radius, max(-p.x, p.x-reach));
}

void fragment() {
	vec2 p = vec2(UV.x*38.0-4.0, (UV.y-0.5)*24.0);
	float t = clamp(age/duration,0.0,1.0);
	// 保持点火、展开和熄灭的速度，只延长中间稳定喷吐的时间。
	float life = smoothstep(0.0,0.034,age)*(1.0-smoothstep(duration-0.125,duration,age));
	float reach = length_px*(0.32+0.68*smoothstep(0.0,0.108,age));
	p.x -= smoothstep(duration-0.108,duration,age)*1.8;
	// 三条错开的弯曲火舌形成清晰层次，柔晕只围绕火舌，不扩成圆形光斑。
	float width = width_px*.42*life;
	float outer = min(tongue(p,reach,width,-1.1),tongue(p+vec2(-1.0,-.9),reach*.77,width*.7,2.0));
	outer = min(outer,tongue(p+vec2(-.7,.8),reach*.88,width*.62,-2.2));
	float solid = 1.0-smoothstep(-0.12,0.3,outer);
	float halo = exp(-pow(max(outer,0.0),2.0)/5.0)*.4;
	float alpha = (solid+halo*(1.0-solid))*life;
	float core = 1.0-smoothstep(-0.12,0.25,tongue(p,reach*.72,width*.40,-.35));
	vec3 color = mix(vec3(0.92,0.25,0.07),vec3(1.0,0.73,0.29),smoothstep(.0,1.1,-outer));
	color = mix(color,vec3(1.0,0.90,0.61),core*.85);
	// 少量余烬由显式年龄定位，暂停和回拖无需重新模拟粒子。
	float ember = 0.0;
	for (int i=0; i<4; i++) {
		float n = float(i);
		float travel = fract(t*1.8+n*.27);
		vec2 center = vec2(length_px*(.65+travel*.48), sin(n*2.4+phase)*(1.4+travel*3.0));
		ember = max(ember,(1.0-smoothstep(.15,.65,length(p-center)))*sin(travel*3.14159265));
	}
	float ember_alpha = ember*smoothstep(.28,.52,t)*(1.0-smoothstep(.66,1.0,t))*.65;
	color = mix(color,vec3(1.0,.65,.22),ember_alpha);
	alpha = max(alpha,ember_alpha);
	if (age<0.0 || age>=duration) alpha=0.0;
	COLOR = vec4(pet_world_color(color),alpha);
}
