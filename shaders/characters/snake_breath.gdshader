shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float age = -1.0;
uniform float duration = 0.44;
uniform float length_px = 10.0;
uniform float phase = 0.0;

// 短而弯曲的火舌，几何边缘稍软，主体保持原画式的清晰色块。
float tongue(vec2 p, float reach, float width, float bend) {
	float u = clamp(p.x / reach, 0.0, 1.0);
	float center = bend*u*u + sin(u*8.0-age*21.0+phase)*u*0.20;
	float radius = width*(0.18 + pow(max(sin(u*3.14159265),0.0),0.8))*(1.0-u*0.45);
	return max(abs(p.y-center)-radius, max(-p.x, p.x-reach));
}

void fragment() {
	vec2 p = vec2(UV.x*18.0-1.0, (UV.y-0.5)*12.0);
	float t = clamp(age/duration,0.0,1.0);
	// 保持点火、展开和熄灭的速度，只延长中间稳定喷吐的时间。
	float life = smoothstep(0.0,0.034,age)*(1.0-smoothstep(duration-0.125,duration,age));
	float reach = length_px*(0.32+0.68*smoothstep(0.0,0.108,age));
	p.x -= smoothstep(duration-0.108,duration,age)*1.8;
	float outer = min(tongue(p,reach,1.8*life,-1.2),tongue(p+vec2(-.6,-.45),reach*.68,1.2*life,1.3));
	float alpha = (1.0-smoothstep(-0.12,0.22,outer))*life;
	float core = 1.0-smoothstep(-0.12,0.20,tongue(p,reach*.70,0.85*life,-.35));
	vec3 color = mix(vec3(0.92,0.25,0.07),vec3(1.0,0.73,0.29),smoothstep(.0,1.1,-outer));
	color = mix(color,vec3(1.0,0.90,0.61),core*.85);
	// 两粒余烬由显式年龄定位，暂停和回拖无需重新模拟粒子。
	float ember = 0.0;
	for (int i=0; i<2; i++) {
		float n = float(i);
		vec2 center = vec2(length_px*(.55+t*.62)+n*1.8, -1.0-n*.9-t);
		ember = max(ember,1.0-smoothstep(.12,.40,length(p-center)));
	}
	float ember_alpha = ember*smoothstep(.28,.52,t)*(1.0-smoothstep(.66,1.0,t))*.65;
	color = mix(color,vec3(1.0,.65,.22),ember_alpha);
	alpha = max(alpha,ember_alpha);
	if (age<0.0 || age>=duration) alpha=0.0;
	COLOR = vec4(color,alpha);
}
