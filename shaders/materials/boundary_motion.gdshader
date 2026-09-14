shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform sampler2D motion_controls : filter_linear, repeat_disable;
uniform bool motion_enabled = true;
uniform float period_sec = 6.0;
uniform float stream_amplitude_px = 3.0;
uniform float curl_amplitude_px = 12.0;
uniform bool beat_enabled = true;
uniform float beat_amplitude_px = 1.2;
uniform float design_scale = 0.76165558;
uniform float boundary_time = 0.0;
uniform float boundary_beat = 0.0;
varying vec4 tint;
void vertex() { tint=COLOR; }

float ease(float x) { return x*x*x*(x*(x*6.0-15.0)+10.0); }
float between(float a,float b,float x) { return ease(clamp((x-a)/(b-a),0.0,1.0)); }

vec2 displacement(vec2 uv) {
	vec2 p=(uv-vec2(.5))*vec2(2650.0,1440.0);
	vec3 control=texture(motion_controls,uv).rgb;
	// 连接带固定；中央内缘保留在原位，形变逐渐传给外侧浪身。
	float connection=between(6.0,30.0,abs(p.y));
	float center_lock=between(108.0,175.0,length(p));
	float pin=connection*center_lock;
	float side=p.x/sqrt(p.x*p.x+80.0*80.0);
	float travel=(1.0-clamp(abs(p.x)/1325.0,0.0,1.0))*1.5;
	float time=mod(boundary_time,period_sec)-control.b*.2;
	float stream=sin(TAU*(time-travel)/period_sec);
	vec2 offset=vec2(-side*.22,side)*stream*stream_amplitude_px*(1.0+control.r*.65)*(1.0-control.g*.72);
	// 六秒内先抬浪、再卷送、最后舒展。五次曲线保持端点速度与加速度连续。
	float phase=mod(time,period_sec)/period_sec*6.0;
	float lift=between(0.0,2.2,phase)*(1.0-between(3.6,6.0,phase));
	float roll=between(2.2,3.6,phase)*(1.0-between(3.6,6.0,phase));
	vec2 radial=p/max(length(p),1.0);
	vec2 tangent=vec2(-radial.y,radial.x);
	// 浪卷从宽缓的根部过渡到浪尖，不能把十余像素行程挤进狭窄的连接带。
	float curl_root=between(24.0,130.0,abs(p.y));
	offset+=(radial*lift*.48+tangent*roll*.88)*curl_amplitude_px*control.g*curl_root;
	float beat=fract(boundary_beat);
	float pulse=between(0.0,.18,beat)*(1.0-between(.18,.80,beat));
	if (beat_enabled) offset+=mix(vec2(0.0,side),radial,control.g)*pulse*beat_amplitude_px*(1.0+control.b*.5);
	// 编辑器把素材缩成小图时，行程跟着缩小，避免局部网纹被过度撑开。
	return offset*pin/max(design_scale,0.76165558);
}

void fragment() {
	vec2 uv=UV;
	// 原画的不透明部分在 y=552～896；空白画布不用计算两次控制图采样。
	if (motion_enabled && UV.y>.34 && UV.y<.66) {
		// 求逆位移后只采样一次原画，颜色与透明边缘始终一起运动。
		vec2 source_size=vec2(2650.0,1440.0);
		uv=UV-displacement(UV)/source_size;
		uv=UV-displacement(uv)/source_size;
	}
	COLOR=texture(TEXTURE,uv)*tint;
}
