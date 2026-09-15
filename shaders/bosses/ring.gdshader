shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float age = -1.0;
uniform float duration = 0.75;
uniform float radius = 230.0;
uniform float strength = 1.0;
uniform float burst = 0.0;
void fragment() {
	vec2 p=(UV-.5)*800.0;
	float t=clamp(age/duration,0.0,1.0);
	float r=mix(18.0,radius,1.0-pow(1.0-t,1.5));
	float d=abs(length(p)-r);
	float edge=mix(3.0,1.2,t);
	float core=1.0-smoothstep(edge,edge+1.5,d);
	float halo=exp(-d*d/(85.0+burst*100.0));
	float fade=smoothstep(0.0,.055,age)*(1.0-smoothstep(.30,1.0,t));
	float broken=mix(1.0,smoothstep(-.9,-.1,sin(atan(p.y,p.x)*7.0+t*3.0)),burst*smoothstep(.2,.8,t));
	vec3 col=mix(vec3(.83,.08,.30),vec3(1.,.91,.59),core);
	COLOR=vec4(col,(core*.85+halo*.25)*fade*broken*strength);
	if(age<0.0 || age>=duration)COLOR.a=0.;
}
