shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D color_ramp : filter_linear;
uniform float age=0.;
uniform float speed=90.;
uniform float random_seed=0.;
uniform float glow_strength=1.;
uniform float flame_height=48.;
varying float opacity;
varying vec4 tint;
float hash(float n){return fract(sin(n*127.1+311.7)*43758.5453);}
void vertex(){
    // 每簇固定六个顶点，编号不占用顶点颜色，避免淡出改变火尖轨迹。
    float id=float(VERTEX_ID/6)+random_seed*41.;
    tint=COLOR;
    float life=1.15+hash(id)*.8;
    float t=fract(age*(speed/90.)/life+hash(id+3.));
    // 每个实例只有短暂的离火阶段，最多八个小火尖，不生成长粒子轨迹。
    opacity=smoothstep(.05,.14,t)*(1.-smoothstep(.35,.60,t));
    VERTEX+=vec2(sin(t*4.+id)*7.,-flame_height*(.45+t*.6));
}
void fragment(){
    vec2 q=UV*2.-1.;
    float d=length(q*vec2(1.2,.9));
    float a=(1.-smoothstep(.12,1.,d))*opacity*min(glow_strength,1.);
    vec3 c=texture(color_ramp,vec2(1.-clamp(d,0.,1.),.5)).rgb;
    COLOR=vec4(c*tint.rgb*a*tint.a*min(glow_strength,1.5),a*tint.a);
}
