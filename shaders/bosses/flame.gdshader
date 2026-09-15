shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float age=0.0;
uniform float amount=0.0;
uniform float strength=1.0;
uniform float reach=320.0;
uniform float width=90.0;
uniform float phase=0.0;
// 各层火舌的行波从嘴向外传播；年龄连续跨过骨骼循环边界。
float tongue(vec2 p,float len,float w,float phase_offset){
	float u=clamp(p.x/len,0.,1.);
	float bend=(sin(u*9.-age*8.+phase+phase_offset)*.45+sin(u*17.-age*13.+phase_offset)*.2)*w*u;
	float thickness=w*(.15+.65*pow(max(sin(u*3.14159),0.),.8))*(1.-.55*u);
	return max(abs(p.y-bend)-thickness,max(-p.x,p.x-len));
}
void fragment(){
	vec2 p=vec2(UV.x*600.-40.,(UV.y-.5)*320.);
	float l=reach*(.84+.07*sin(age*10.+phase)+.09*sin(age*6.+phase));
	float w=width*amount;
	float d=min(tongue(p,l,w,.0),tongue(p+vec2(-20.,w*.22),l*.84,w*.75,2.3));
	d=min(d,tongue(p+vec2(-12.,-w*.23),l*.94,w*.6,4.8));
	float solid=1.-smoothstep(-.7,1.7,d);
	float halo=exp(-pow(max(d,0.),2.)/190.)*.35;
	float mid=1.-smoothstep(-.8,1.6,tongue(p,l*.84,w*.61,1.));
	float core=1.-smoothstep(-.5,1.4,tongue(p,l*.58,w*.25,0.));
	vec3 col=mix(vec3(.85,.09,.015),vec3(1.,.57,.045),mid);
	col=mix(col,vec3(1.,.93,.56),core);
	float sparks=0.;
	for(int i=0;i<9;i++){
		float n=float(i);float u=fract(age*(.7+n*.025)+n*.618+phase);
		vec2 at=vec2(reach*(.4+u*.9),sin(n*13.+phase)*width*(.25+u*.9));
		sparks=max(sparks,(1.-smoothstep(.9,3.4,length(p-at)))*sin(u*3.14159));
	}
	float alpha=max(solid+halo*(1.-solid),sparks*.75)*amount;
	col=mix(col,vec3(1.,.77,.26),sparks);
	COLOR=vec4(col*mix(.85,1.,clamp(strength,0.,1.)),alpha*strength);
}
