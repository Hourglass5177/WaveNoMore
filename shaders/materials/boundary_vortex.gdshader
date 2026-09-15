shader_type canvas_item;
render_mode unshaded;
uniform sampler2D root_water : source_color, filter_linear;
uniform sampler2D water_bounds : filter_linear;
uniform sampler2D crest_texture : source_color, filter_linear_mipmap;
uniform float world_sign = 1.0;
uniform float ink_phase = 0.0;
uniform float foam_phase = 0.0;
uniform float crest_phase = 0.0;
uniform float foam_strength = 0.65;
varying vec2 water_position;
varying float path_u;
varying float width_px;

void vertex() {
	// 只压低中央留白以外的纵向高点；内缘、浪根和原 UV 路程不缩放。
	float excess_height=max(abs(VERTEX.y)-96.0,0.0);
	VERTEX.y-=sign(VERTEX.y)*excess_height*.18*smoothstep(0.0,40.0,excess_height);
	water_position=VERTEX;
	path_u=COLOR.r;
	width_px=COLOR.g*256.0;
}
vec4 source_band(float x, float v) {
	vec2 limits=texture(water_bounds,vec2(x,.5)).rg;
	return texture(root_water,vec2(mix(96.0,2500.0,x)/2650.0,mix(limits.y,limits.x,v)));
}
vec4 flowing_band(float x, float v) {
	float p=fract(x);
	return mix(source_band(mix(.08,.43,p),v),source_band(mix(.08,.43,p-1.0),v),smoothstep(.90,1.0,p));
}
vec4 crest(float x,float y) {
	float p=fract(x);
	vec4 a=texture(crest_texture,vec2(p,y));
	vec4 b=texture(crest_texture,vec2(max(p-1.0,0.0),y));
	float blend=smoothstep(.955,1.0,p);
	// 只在低水段的接缝做预乘接合，完整的浪唇轮廓随 UV 真正向前走。
	vec4 result=mix(vec4(a.rgb*a.a,a.a),vec4(b.rgb*b.a,b.a),blend);
	result.rgb/=max(result.a,.0001);
	return result;
}
void fragment() {
	float along=UV.x;
	float v=UV.y;
	float strength=smoothstep(.04,.24,path_u);
	// 水坡稍加厚，浪唇沿横向收拢，避免映射到弧面后被撑成长而直立的枝杈。
	float lip_height=max(v-.56,0.0);
	// 起势斜坡上的薄尖更贴水，逐渐到卷顶才充分展开，避免根部另长出一根高叉。
	float crest_spread=mix(.72,1.0,smoothstep(.24,.56,path_u));
	float tex_y=v<.56 ? mix(.755,.67,v/.56) : .67-lip_height*.68/crest_spread;
	// 越靠薄尖越顺着水势前倾；只改变局部浪形，绝对路程与接替节奏保持不变。
	float forward_lean=72.0*pow(clamp(lip_height/.56,0.0,1.0),1.5);
	vec4 lip=crest((along-forward_lean)/900.0-crest_phase,tex_y);
	vec4 ink=flowing_band(along/640.0-ink_phase,clamp(v,0.0,1.0));
	float source_alpha=smoothstep(.30,.72,lip.a);
	float aa=max(fwidth(v)*width_px,.6);
	float root_alpha=1.0-smoothstep(1.0-aa/max(width_px,1.0),1.0,v);
	// 离开脚部便沿新浪唇的缺口开口，不能留下旧实心外缘的淡灰残影。
	root_alpha*=mix(1.0,source_alpha,smoothstep(.025,.12,path_u));
	float alpha=mix(root_alpha,source_alpha,strength);
	// 原画色带只在下层少量保留流动；浪唇用补绘的完整色块、白边与透明缺口。
	float ink_weight=(1.0-smoothstep(.18,.55,v))*.22;
	vec3 lip_color=mix(lip.rgb,ink.rgb,ink_weight);
	vec3 color=(ink.rgb*root_alpha*(1.0-strength)+lip_color*source_alpha*strength)/max(alpha,.0001);
	float p=fract(along/235.0-foam_phase);
	float filament=smoothstep(.04,.18,p)*(1.0-smoothstep(.48,.68,p));
	float line=1.0-smoothstep(.65,1.8,abs(v-(.22+.15*p))*width_px);
	color=mix(color,vec3(.91,.91,.86),line*filament*foam_strength*.45);
	alpha*=smoothstep(0.0,aa,v*width_px);
	alpha*=smoothstep(0.0,45.0,along)*(1.0-smoothstep(.965,1.0,path_u));
	vec2 source_uv=(vec2(1325.0,720.0)+water_position*world_sign/.7616555803)/vec2(2650.0,1440.0);
	vec4 root=texture(root_water,source_uv);
	float join=(1.0-smoothstep(18.0,125.0,along))*root.a;
	color=mix(color,root.rgb,join);
	COLOR=vec4(color,alpha);
}
