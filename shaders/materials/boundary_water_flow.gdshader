shader_type canvas_item;
render_mode unshaded;

uniform sampler2D flow_control : filter_linear, repeat_disable;
uniform sampler2D flow_streaks : source_color, filter_linear, repeat_enable;
uniform bool flow_enabled = true;
uniform float flow_seconds = 0.0;
uniform float flow_speed_px_sec = 60.0;
uniform float flow_strength = 0.80;
uniform float streak_strength = 0.24;
const float DESIGN_SCALE = 0.7616555803103707;
varying vec4 vertex_color;

void vertex() { vertex_color=COLOR; }

void fragment() {
	vec4 base=texture(TEXTURE,UV);
	vec3 rgb=base.rgb;
	if (flow_enabled && base.a>0.0) {
		vec4 control=texture(flow_control,UV);
		vec2 velocity=(control.rg*2.0-1.0)*flow_speed_px_sec;
		float phase_a=fract(flow_seconds/2.0+control.a);
		float phase_b=fract(phase_a+0.5);
		float weight_a=1.0-abs(phase_a*2.0-1.0);
		float weight_b=1.0-weight_a;
		// 让一组水纹占主导，避免线性等权将宽色带的相反偏移抵消。
		weight_a=weight_a*weight_a/(weight_a*weight_a+weight_b*weight_b);
		weight_b=1.0-weight_a;
		vec2 pixel_uv=TEXTURE_PIXEL_SIZE/DESIGN_SCALE;
		// 两个短行程在不可见时重置；偏移保持在初始姿态两侧，避免持续拉长。
		vec4 a=texture(TEXTURE,UV-velocity*(phase_a-0.5)*2.0*pixel_uv);
		vec4 b=texture(TEXTURE,UV-velocity*(phase_b-0.5)*2.0*pixel_uv);
		// 取样落到透明区时沿用当前位置颜色，不将透明黑带回水带。
		vec3 flowing=mix(base.rgb,a.rgb,a.a)*weight_a+mix(base.rgb,b.rgb,b.a)*weight_b;
		rgb=mix(base.rgb,flowing,flow_strength*control.b);
		vec2 position=(UV/TEXTURE_PIXEL_SIZE-vec2(1325.0,720.0))*DESIGN_SCALE;
		// 细纹也共用双阶段搬运；右半绕中心翻转，保留两界对称关系。
		float side=position.x<0.0?1.0:-1.0;
		vec2 tile=vec2(512.0,96.0);
		vec4 line_a=texture(flow_streaks,(position-velocity*(phase_a-0.5)*2.6)*side/tile);
		vec4 line_b=texture(flow_streaks,(position-velocity*(phase_b-0.5)*2.6)*side/tile);
		float line_alpha=line_a.a*weight_a+line_b.a*weight_b;
		vec3 line_rgb=(line_a.rgb*line_a.a*weight_a+line_b.rgb*line_b.a*weight_b)/max(line_alpha,0.0001);
		rgb=mix(rgb,line_rgb,line_alpha*streak_strength*control.b);
	}
	// 无论流动开关、年龄或强度，覆盖范围都由原画的同一像素决定。
	COLOR=vec4(rgb,base.a)*vertex_color;
}
