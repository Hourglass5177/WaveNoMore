shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float age=0.0;
uniform float amount=0.0;
uniform float reach=650.0;
uniform float width=60.0;
uniform float phase=0.0;
void fragment(){
    float x=UV.x*1100.;
    float y=(UV.y-.5)*500.;
    float along=clamp(x/reach,0.,1.);
    float half_width=width*(.06+along*.7);
    float bend=sin(along*2.4+phase+age*.35)*along*width*.08;
    float distance=abs(y-bend)/max(half_width,1.);
    float soft=exp(-distance*distance*2.5);
    float core=exp(-distance*distance*22.);
    float tip=1.-smoothstep(.62,1.,along);
    float base=smoothstep(0.,12.,x);
    vec3 color=mix(vec3(.86,.28,.38),vec3(1.,.80,.38),soft);
    color=mix(color,vec3(1.,.98,.90),core);
    COLOR=vec4(color,(soft*.45+core*.7)*tip*base*amount);
}
