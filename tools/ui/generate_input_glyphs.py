from pathlib import Path
# 手工矢量笔画，避免 SVG 文本依赖电脑字体；素材与生成器一并保留。
letters = {
 'j':'M7 -10 V4 C7 13 -8 13 -8 3', 'f':'M7 -10 H-7 V10 M-7 -1 H5',
 'a':'M-8 9 L0 -10 L8 9 M-5 3 H5', 'b':'M-7 9 V-10 H0 C11 -10 11 0 0 0 H-7 M0 0 C12 0 12 9 0 9 H-7',
 'x':'M-8 -9 L8 9 M8 -9 L-8 9', 'y':'M-8 -9 L0 0 L8 -9 M0 0 V9',
 'l':'M-7 -10 V9 H7','r':'M-7 9 V-10 H0 C11 -10 11 0 0 0 H-7 M0 0 L9 9',
 'p':'M-7 9 V-10 H1 C12 -10 12 1 1 1 H-7', 'o':'M0 -10 C-12 -10 -12 10 0 10 C12 10 12 -10 0 -10 Z',
 'q':'M0 -10 C-12 -10 -12 10 0 10 C12 10 12 -10 0 -10 Z M3 5 L11 13',
 'e':'M7 -10 H-7 V9 H7 M-7 0 H5', 's':'M7 -8 C-10 -17 -14 -1 0 0 C14 1 10 16 -8 8',
 'c':'M7 -8 C-13 -17 -13 17 7 8', '1':'M-4 -6 L1 -10 V10 M-5 10 H7'
}
shapes={'triangle':'M0 -12 L12 10 H-12 Z','square':'M-10 -10 H10 V10 H-10 Z','cross':letters['x'],'circle':'M0 -11 A11 11 0 1 0 0 11 A11 11 0 1 0 0 -11','enter':'M10 -8 V2 H-10 M-4 -4 L-10 2 L-4 8'}
keys=['a','b','x','y','triangle','square','cross','circle','lb','rb','l1','r1','l','r','p','o','q','e','esc','enter','north','south','east','west','shoulder_left','shoulder_right','j','f','stick_left','stick_right']
destination=Path(__file__).resolve().parents[2]/'assets/ui/input'
destination.mkdir(parents=True,exist_ok=True)
# 摇杆使用低对比平涂，帽与底座贴近同一平面；保留独立位移以表达方向。
def stick_svg(key):
 header = '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="80" viewBox="0 0 96 80">'
 if key == 'stick_glow':
  return header + '''<defs><radialGradient id="halo">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0"/>
  <stop offset=".45" stop-color="#ffffff" stop-opacity=".04"/>
  <stop offset=".68" stop-color="#ffffff" stop-opacity=".75"/>
  <stop offset=".8" stop-color="#ffffff" stop-opacity=".28"/>
  <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
  </radialGradient></defs><ellipse cx="48" cy="40" rx="48" ry="40" fill="url(#halo)"/></svg>'''
 if key == 'stick_base':
  return header + '''<ellipse cx="48" cy="42" rx="36" ry="17" fill="#302b39" stroke="#8b7f8d" stroke-opacity=".45" stroke-width="1"/></svg>'''
 letter = letters['l' if key == 'stick_left' else 'r']
 return header + '''<ellipse cx="48" cy="32" rx="33" ry="18" fill="#655b6c" stroke="#b5a6af" stroke-opacity=".65" stroke-width="1.2"/>
 ''' + f'<path transform="translate(48 32) scale(.6)" d="{letter}" fill="none" stroke="#e6ddc9" stroke-opacity=".82" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'

keys.extend(['stick_base', 'stick_glow'])
for key in keys:
 if key.startswith('stick_'):
  (destination/f'{key}.svg').write_text(stick_svg(key),encoding='utf-8')
  continue
 wide=key in ['lb','rb','l1','r1','l','r','esc','enter','shoulder_left','shoulder_right']
 keyboard=key in ['p','o','q','e','esc','enter','j','f']
 width=72 if wide else 48
 cx=width/2
 outline=f'<rect x="3" y="7" width="{width-6}" height="34" rx="{5 if keyboard else 11}"/>' if wide or keyboard else '<circle cx="24" cy="24" r="20"/>'
 # 灰紫漆底，骨白细边，内缘一笔暖灰。所有图标共享同一视觉重量。
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="48" viewBox="0 0 {width} 48"><g fill="#26212e" fill-opacity="0.92" stroke="#c8bbad" stroke-width="1.4">{outline}</g>'
 svg+=f'<path d="M{cx-6} 5 H{cx+6}" fill="none" stroke="#e6ddc9" stroke-opacity=".55" stroke-width="1"/>'
 svg+='<g fill="none" stroke="#e6ddc9" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
 if key in ['north','south','east','west']:
  for position,(dx,dy) in {'north':(0,-10),'south':(0,10),'east':(10,0),'west':(-10,0)}.items():
   svg+=f'<circle cx="{cx+dx}" cy="{24+dy}" r="3.1" fill="'+('#e6ddc9' if position==key else '#544859')+'" stroke="none"/>'
 elif key in ['shoulder_left','shoulder_right']:
  flip=1 if key=='shoulder_left' else -1
  svg+=f'<path transform="translate({cx} 24) scale({flip} 1)" d="M7 -9 L-4 0 L7 9 M-11 -9 V9"/>'
 elif key in shapes:
  svg+=f'<path transform="translate({cx} 24)" d="{shapes[key]}"/>'
 else:
  word=key
  spacing=16 if len(word)>1 else 0
  for i,char in enumerate(word):
   scale=.66 if len(word)>1 else .87
   svg+=f'<path transform="translate({cx+(i-(len(word)-1)/2)*spacing} 24) scale({scale})" d="{letters[char]}"/>'
 svg+='</g></svg>'
 (destination/f'{key}.svg').write_text(svg,encoding='utf-8')
print(f'{len(keys)} UI glyphs generated')

# 运行时使用同源内嵌 SVG，导出包无需保留导入前的原始图片文件。
import json
sources={key:(destination/f'{key}.svg').read_text(encoding='utf-8') for key in keys}
data=destination.parents[2]/'src/app/ui/input_glyph_data.gd'
data.write_text('extends RefCounted\n## 由 tools/ui/generate_input_glyphs.py 生成，与 assets/ui/input 的矢量源一致。\nconst SVG_SOURCES = '+json.dumps(sources,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
