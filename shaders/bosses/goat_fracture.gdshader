shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float age=0.0;
uniform float strength=1.0;
uniform float spread=1.0;
uniform float body_visible=1.0;
uniform sampler2D cracks_texture;
uniform sampler2D eyes_texture;
varying vec2 source_uv;
varying float seed;
void vertex(){
    source_uv=UV;seed=COLOR.b;
    vec2 center=COLOR.rg*1024.-512.;
    vec2 direction=normalize(center-vec2(0.,-72.));
    float part=smoothstep(2.1,3.8,age);
    float split=smoothstep(3.8,4.8,age);
    float burst=smoothstep(4.8,5.4,age);
    float angle=sin(seed*37.)*(split*.30+burst*.65);
    vec2 p=VERTEX-center;
    VERTEX=center+mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p;
    VERTEX+=direction*(12.*part+58.*split+300.*burst)*spread;
    VERTEX.y+=70.*(1.-smoothstep(.7,2.1,age));
    COLOR=vec4(1.);
}
void fragment(){
    vec4 tex=texture(TEXTURE,source_uv);
    vec4 crack=texture(cracks_texture,source_uv);
    float reveal=smoothstep(.9+crack.r*.7,1.2+crack.r*.7,age);
    float fade=1.-smoothstep(5.05+seed*.12,5.65,age);
    float edge=crack.a*reveal*strength*(.25+.75*smoothstep(1.5,3.8,age));
    float body=step(2.1,age)*body_visible;
    vec3 rgb=mix(tex.rgb,vec3(1.,.94,.76),clamp(edge,0.,1.));
    // 眼光与骨片一起裂开、消退，不能在交接后恢复成原画黑眼。
    vec2 eye=texture(eyes_texture,source_uv).rg*strength*step(2.1,age);
    rgb=mix(rgb,vec3(1.),clamp(eye.r+eye.g*.65,0.,1.));
    COLOR=vec4(rgb,max(max(tex.a*body,edge),clamp(eye.r+eye.g*.5,0.,1.))*fade);
}
