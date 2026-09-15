shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform sampler2D fuel_map : filter_linear;
uniform sampler2D color_ramp : filter_linear;
uniform vec2 frame_size=vec2(360.,600.);
uniform float flame_height=48.;
uniform float speed=90.;
uniform float glow_strength=1.;
uniform float random_seed=0.;
uniform float age=0.;
uniform float animated=1.;
varying vec2 pixel;
varying vec4 tint;
float hash(float n){return fract(sin(n*127.1+311.7)*43758.5453);}
float root_curve(float at){return sin(at*.034)*2.5+sin(at*.081+1.3)*1.5;}

// 火根始终固定；两层向上的流场只在离根部后逐渐介入，撕开上部轮廓。
vec2 burning(vec2 p,vec2 root,float id,float clock,float fuel,vec2 size_scale){
    vec2 q=p-root;
    float cluster=smoothstep(.55,.9,hash(id+43.));
    float length=flame_height*mix(.7,1.35,cluster)*mix(.85,1.1,fuel)*size_scale.y;
    float width=mix(11.,23.,cluster)*mix(.85,1.1,fuel)*size_scale.x;
    if(abs(q.x)>width*2.8 || q.y < -length*1.6 || q.y > width*1.3){return vec2(0.);}
    float h=max(-q.y/length,0.);
    vec2 advect=vec2(q.x/160.+id*.137,(q.y+clock*90.)/320.);
    vec3 large=texture(noise_map,advect).rgb;
    vec3 detail=texture(noise_map,advect*vec2(1.71,1.37)+vec2(.31,clock*.065)).rgb;
    float free_flow=smoothstep(.015,.38,h);
    float bend=(large.r-.5)*30.*free_flow;
    // 火焰从窄根连续伸出，焰身再展开，避免底部成为静止的宽三角块。
    float root_width=mix(.42,1.,smoothstep(0.,.24,h));
    float radial=abs(q.x-bend)/(width*root_width);
    float shape=.82-pow(radial,1.55)-h*.9;
    float turbulence=((large.r-.5)*2.1+(detail.g-.5)*.85)*free_flow;
    float field=shape+turbulence;
    float base=exp(-pow(max(q.y,0.)/(width*.32),2.));
    float tip=1.-smoothstep(1.15,1.55,h);
    float body=smoothstep(0.,.16,field)*base*tip;
    float core=pow(smoothstep(.02,.86,field),1.2)*base*tip;
    // 低密度边缘与火芯使用同一个密度场，柔光随当前火形变化。
    float halo=exp(-max(-field,0.)*5.)*.32*base*tip;
    return vec2(max(body,halo*glow_strength),core);
}

void vertex(){pixel=VERTEX;tint=COLOR;}
void fragment(){
    vec2 p=pixel-frame_size*.5;
    vec2 half_size=frame_size*.5;
    float clock=age*(speed/90.)*animated+random_seed*7.13;
    float alpha_field=0.;float heat=0.;
    for(int edge=0;edge<4;edge++){
        // 底部以宽火团为主，拉开火根间隔，让各簇轮廓有舒展空间。
        float spacing=edge==2?84.:52.;
        bool horizontal=edge==0||edge==2;
        float along=horizontal?p.x:p.y;
        float extent=horizontal?half_size.x:half_size.y;
        float across=horizontal?p.y:p.x;
        float base=(edge==0||edge==3)?-(horizontal?half_size.y:half_size.x):(horizontal?half_size.y:half_size.x);
        // 裁剪运算区域而非火形；四角由 max 合并，避免叠亮接缝。
        float band_height=flame_height*2.4;
        if(abs(across-base)<band_height && abs(along)<extent+flame_height*2.4){
            // 每条边独立保护文字区，避免角落互相放开范围或重复压低火尖。
            float inward=(edge==0||edge==3)?across-base:base-across;
            float fade_start=edge==2?min(flame_height*1.5,frame_size.y*.25):flame_height*.88;
            float fade_end=edge==2?min(flame_height*2.35,frame_size.y*.4):flame_height*1.35;
            float edge_fade=1.-smoothstep(fade_start,fade_end,inward);
            // 细窄的连续燃烧根部连接大、小火簇；沿原画式的曲线固定在框边。
            float fuel_line=texture(fuel_map,vec2(clamp((along+extent)/(2.*extent),0.,1.),(float(edge)+.5)/4.)).r;
            float root_distance=abs(across-base-root_curve(along));
            float end_fade=1.-smoothstep(extent-2.,extent+5.,abs(along));
            float wick=exp(-pow(root_distance/(1.+fuel_line*2.),2.))*end_fade;
            alpha_field=max(alpha_field,wick*(.18+fuel_line*fuel_line*.7));
            heat=max(heat,wick*(.2+fuel_line*.55));
            float cell=floor((along+extent)/spacing);
            // 柔晕比火芯宽，需覆盖左侧三个邻区，避免越过分布单元时截断。
            for(int k=-3;k<=4;k++){
                float index=cell+float(k);
                float source=-extent+index*spacing;
                if(source>=-extent&&source<=extent){
                    float id=index+float(edge)*137.+random_seed*41.;
                    // 底边整段持续供火，右侧下段略密，其余边保留疏区。
                    float corner=edge==2?1.:(edge==1?smoothstep(.25,.85,(source+extent)/(2.*extent)):0.);
                    if(hash(id+31.)<.12*(1.-corner) && index>0. && source<extent-spacing) {continue;}
                    float shift=clamp((hash(id+3.)-.5)*spacing*.78,-extent-source,extent-source);
                    float contour=root_curve(source+shift);
                    vec2 root=horizontal?vec2(source+shift,base+contour):vec2(base+contour,source+shift);
                    float fuel=.62+.65*texture(fuel_map,vec2((source+extent)/(2.*extent),(float(edge)+.5)/4.)).r;
                    vec2 flame=burning(p,root,id,clock,fuel,edge==2?vec2(2.35,1.6):vec2(1.));
                    flame*=edge_fade;
                    alpha_field=max(alpha_field,flame.x);
                    heat=max(heat,flame.y);
                    // 只在较大的间隙补一簇矮火，保留主火根和既有运动相位。
                    float next_along=source+spacing+(hash(id+4.)-.5)*spacing*.78;
                    float gap=next_along-source-shift;
                    if(edge==1 && corner>.35 && gap>34. && next_along<extent-6.){
                        float fill_along=source+shift+gap*.55;
                        float fill_curve=root_curve(fill_along);
                        vec2 fill_root=horizontal?vec2(fill_along,base+fill_curve):vec2(base+fill_curve,fill_along);
                        vec2 fill=burning(p,fill_root,id+73.4,clock,fuel,vec2(.68));
                        fill*=edge_fade;
                        alpha_field=max(alpha_field,fill.x);
                        heat=max(heat,fill.y);
                    }
                }
            }
        }
    }
    float alpha=alpha_field;
    vec3 color=texture(color_ramp,vec2(heat,.5)).rgb;
    // 预乘透明度也作用于 RGB，菜单淡出时不能留下加色火光。
    COLOR=vec4(color*tint.rgb*alpha*tint.a,alpha*tint.a);
}
