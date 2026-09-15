shader_type canvas_item;
render_mode unshaded;

uniform vec4 ink : source_color = vec4(1.0);
uniform vec4 source_rect = vec4(0.0,0.0,1.0,1.0);
uniform vec2 glyph_size = vec2(640.0);
uniform float padding = 96.0;
uniform float radius = 48.0;
uniform float strength = 1.5;
varying vec4 item_color;

void vertex() { item_color = COLOR; }

float coverage(sampler2D source, vec2 p) {
	// 原图已带低透明度旧光晕：只取实体笔触，四级统一重新着色与生成柔光。
	vec2 uv = source_rect.xy + p * source_rect.zw;
	float inside = step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
	return smoothstep(0.08,0.92,texture(source,clamp(uv,vec2(0.0),vec2(1.0))).a)*inside;
}

void fragment() {
	vec2 p = (UV*(glyph_size+vec2(2.0*padding))-vec2(padding))/glyph_size;
	float body = coverage(TEXTURE,p);
	float halo = 0.0;
	// 两层错位环形采样，柔边覆盖笔画附近；整幅只绘制一个有透明边距的四边形。
	for (int i=0; i<16; i++) {
		float angle = float(i)*2.399963;
		float distance = sqrt((float(i)+0.5)/16.0);
		halo += coverage(TEXTURE,p+vec2(cos(angle),sin(angle))*radius*distance/glyph_size)*(1.0-distance*0.65);
	}
	halo = pow(halo/16.0,0.8)*strength;
	// 上限跟随控件的 70% 不透明度，不靠层叠把实体笔画重新堆成不透明。
	COLOR = vec4(ink.rgb, clamp(max(body,halo),0.0,1.0)*item_color.a*ink.a);
}
