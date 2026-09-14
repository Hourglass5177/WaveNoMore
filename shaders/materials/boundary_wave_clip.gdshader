shader_type canvas_item;
render_mode unshaded;
// 两类浪都保持首帧 UV，按绝对年龄采样同一张图集中的相邻轮廓。
uniform float wave_frame = 0.0;
varying vec4 vertex_color;
void vertex() { vertex_color=COLOR; }
void fragment() {
	// 保留完整浪花，遮挡由前方判定界面的真实绘制层级处理。
	vec2 local_uv = (UV * 4096.0 - vec2(4.0)) / vec2(384.0, 256.0);
	float frame_a = floor(clamp(wave_frame, 0.0, 127.0));
	float frame_b = min(frame_a + 1.0, 127.0);
	vec2 origin_a = vec2(mod(frame_a, 10.0) * 400.0, floor(frame_a / 10.0) * 272.0) + 4.0;
	vec2 origin_b = vec2(mod(frame_b, 10.0) * 400.0, floor(frame_b / 10.0) * 272.0) + 4.0;
	vec4 a = texture(TEXTURE, (origin_a + local_uv * vec2(384.0,256.0)) / 4096.0);
	vec4 b = texture(TEXTURE, (origin_b + local_uv * vec2(384.0,256.0)) / 4096.0);
	float blend = fract(clamp(wave_frame, 0.0, 127.0));
	// 只补相邻密集帧；预乘混合避免透明像素染黑浪缘。
	float alpha = mix(a.a, b.a, blend);
	vec3 rgb = mix(a.rgb * a.a, b.rgb * b.a, blend) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha) * vertex_color;
}
