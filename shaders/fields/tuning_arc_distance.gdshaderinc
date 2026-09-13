uniform vec2 arc_center;
uniform float arc_radius;
uniform float start_angle;
uniform float arc_sweep;
uniform float direction = 1.0;
uniform float half_width = 52.0;
uniform float fill_from = 0.0;
uniform float fill_to = 0.0;
uniform bool straight_path = false;
uniform vec2 line_start;
uniform vec2 line_end;
float rail_distance(vec2 delta, float radial, float angle, float from, float to) {
	if (straight_path) {
		vec2 p = delta + arc_center; vec2 a = mix(line_start, line_end, from); vec2 b = mix(line_start, line_end, to);
		vec2 ab = b - a; return length(p - a - ab * clamp(dot(p - a, ab) / max(dot(ab, ab), 0.00001), 0.0, 1.0)) - half_width;
	}
	float begin = start_angle + direction * arc_sweep * from;
	float sweep = arc_sweep * (to - from);
	float relative = mod(direction * (angle - begin) + 6.28318530718, 6.28318530718);
	if (relative <= sweep) return abs(radial - arc_radius) - half_width;
	vec2 a = vec2(cos(begin), sin(begin)) * arc_radius;
	float end = begin + direction * sweep;
	vec2 b = vec2(cos(end), sin(end)) * arc_radius;
	return min(length(delta - a), length(delta - b)) - half_width;
}
