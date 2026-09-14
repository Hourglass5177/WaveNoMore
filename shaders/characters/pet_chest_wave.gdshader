shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/characters/pet_world_color.gdshaderinc"
uniform float age = -1.0;
uniform float duration = 0.5;
uniform float radius_from = 5.333333;
uniform float radius_to = 32.0;
uniform float amount = 0.0;
void fragment() {
	float t = clamp(age/duration,0.0,1.0);
	float radius = mix(radius_from,radius_to,1.0-pow(1.0-t,1.5));
	float dist = length((UV-0.5)*78.0);
	float edge = abs(dist-radius);
	float width = mix(1.1,0.35,t);
	float core = 1.0-smoothstep(width*.35,width,edge);
	float halo = exp(-edge*edge/7.0)*.43;
	float life = smoothstep(0.0,.025,age)*(1.0-smoothstep(.16,duration,age));
	float chest = exp(-dist*dist/17.0)*amount*.28;
	vec3 color = mix(vec3(.98,.48,.61),vec3(1.0,.83,.48),1.0-smoothstep(.1,2.0,edge));
	color = mix(color,vec3(1.0,.985,.91),core);
	COLOR = vec4(pet_world_color(color),max((core+halo*(1.0-core))*life,chest));
}
