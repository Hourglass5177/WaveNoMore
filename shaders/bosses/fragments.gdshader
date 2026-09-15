shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float age=0.0;
uniform float duration=1.75;
uniform float spread=180.0;
uniform float strength=1.0;
uniform int kind_id=0;
varying vec2 source_uv;
varying float seed;
varying float layer;
void vertex(){
	source_uv=COLOR.rg;seed=COLOR.b;layer=COLOR.a;
	vec2 center=(source_uv-.5)*1024.;
	float delay=kind_id==1 ? clamp(source_uv.y-.2,0.,.6)*.48 : (1.-abs(source_uv.x-.5)*2.)*.14;
	float t=max(age-delay,0.);
	float progress=1.-exp(-t*2.0);
	float a=sin(seed*47.)*progress*(kind_id==2 ? 1.1:1.8);
	vec2 local=VERTEX-center;
	float shrink=1.-smoothstep(duration*.3,duration,t)*.65;
	VERTEX=center+mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*local*shrink;
	vec2 dir=normalize(center+vec2(sin(seed*79.)*70.,-50.));
	if(kind_id==0)dir.x*=1.4;
	VERTEX+=dir*spread*progress+vec2(0.,(kind_id==1 ? 48.:32.)*t*t);
	COLOR=vec4(1.);
}
void fragment(){
	float fade=1.-smoothstep(duration*.38+seed*.18,duration,age);
	vec3 hot=kind_id==0 ? vec3(1.,.32,.44) : vec3(1.,.72,.23);
	if(layer>.75){
		vec4 tex=texture(TEXTURE,source_uv);
		float a=tex.a*exp(-dot(UV*2.-1.,UV*2.-1.)*3.5)*smoothstep(0.,.1,age)*fade;
		COLOR=vec4(mix(tex.rgb,hot,.65),a*strength);
	}else{
		vec4 tex=texture(TEXTURE,UV);
		float glow=(1.-smoothstep(0.,.38,age))*strength;
		if(layer>.25)COLOR=vec4(hot,tex.a*glow*.6);
		else COLOR=vec4(mix(tex.rgb,hot,glow*.22),tex.a*fade);
	}
}
