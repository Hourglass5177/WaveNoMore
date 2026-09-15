shader_type canvas_item;
render_mode unshaded;

uniform sampler2D title_texture : source_color, filter_linear, repeat_disable;
uniform vec2 title_size = vec2(750.0,200.0507);
uniform float padding_px = 20.0;
uniform float radius_px : hint_range(0.0,20.0) = 12.0;
uniform float strength : hint_range(0.0,1.0) = 0.18;
uniform vec4 glow_color : source_color = vec4(0.902,0.867,0.788,1.0);

float alpha_at(vec2 uv) {
	// 原图在边缘仍有笔触；越界采样透明，避免把边缘像素拉成长线。
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return 0.0;
	return texture(title_texture,uv).a;
}

void fragment() {
	vec2 uv = (UV*(title_size+vec2(2.0*padding_px))-vec2(padding_px))/title_size;
	vec2 step_uv = vec2(radius_px*0.5)/title_size;
	float weights[5] = float[5](1.0,4.0,6.0,4.0,1.0);
	float halo = 0.0;
	// 固定局部核只覆盖标题；原字图单独绘制，保留灰白笔触与缺口。
	for (int y=0; y<5; y++) {
		for (int x=0; x<5; x++) {
			halo += alpha_at(uv+vec2(float(x-2),float(y-2))*step_uv)*weights[x]*weights[y];
		}
	}
	COLOR *= vec4(glow_color.rgb,halo/256.0*strength*glow_color.a);
}
