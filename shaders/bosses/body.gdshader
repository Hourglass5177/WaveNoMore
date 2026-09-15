shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float light=0.;
uniform vec4 tint:source_color=vec4(1.,.78,.38,1.);
varying vec4 vertex_tint;
void vertex(){vertex_tint=COLOR;}
void fragment(){
	vec4 tex=texture(TEXTURE,UV)*vertex_tint;
	// 借原画已着色的纹样传递亮势，黑色底纹保留，不整片漂成白色。
	float pattern=smoothstep(.12,.65,max(tex.r,max(tex.g,tex.b)));
	tex.rgb=mix(tex.rgb,tint.rgb,pattern*light*.48);
	COLOR=tex;
}
