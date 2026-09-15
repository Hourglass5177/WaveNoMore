shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float amount=0.0;
uniform vec4 tint:source_color=vec4(1.0,.78,.35,1.0);
void fragment(){
	vec2 p=(UV-.5)*2.;
	float a=exp(-dot(p,p)*5.5)*(1.-smoothstep(.65,1.,length(p)));
	COLOR=vec4(tint.rgb,a*amount*.42);
}
