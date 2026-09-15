# 分叉浪唇纹理

2026-09-15。使用内置 image_gen 工具，以 `../../edge.png` 为风格参考补绘，保留生成的透明度。输出原样保存为 `../crest_flow.png`（2172×724）。运行时以透明轮廓随 UV 前进；没有将它铺在整块不透明底色上。

生成提示词：

```text
Create ONE production 2D game VFX TEXTURE, using the attached original water art as the strict palette and brushwork reference. This is a SOURCE TEXTURE for a scrolling curved ribbon mesh, NOT a composed vortex illustration.

Canvas 1536 x 512, genuine transparent alpha background. A single horizontal water stream flows LEFT TO RIGHT across the full width, touching both left/right canvas borders. Bottom continuous water backbone occupies y=370..490, bottom roughly horizontal with slight natural unevenness. Upper portions are successive irregular rolling wave lips, rising from this backbone into y=90..370. Four unequally sized crests with elongated forward-hooking thin tips, irregular forked bone-white fringes, pale lavender underfolds and translucent little openings beneath the overhanging lips. Each crest has 2-4 delicate layered fingers. The largest crest near 35 percent width, smaller followers near 60 and 85 percent; no repeated identical comb teeth. Leave clearly transparent broad valleys between the crest clusters. Crests have weight and volume at their bases but taper into elegant long forward-running wisps; a few small detached slivers are allowed close to their tips. Water surface should look actively rolling, pulled and torn into delicate thin lips, NOT one smooth solid blob, feather, flame, wing, hair, wood grain, or smooth plastic ribbon. Avoid perfectly continuous smooth top boundary.

Style: meticulously match reference flat hand-painted angular color planes, dusty pale mauve, chalky powder-blue, pale pink-gray, bone-white sharp rims; mostly light/desaturated colors, sparse muted blue-violet recess accents. No black outlines, no glossy rendering, no gradients of glow, no photorealism, no neon, no speckled glitter. Flow lines follow the longitudinal motion with thoughtful curved turns inside each crest. Keep brushwork quite fine and clean without blur. Open transparent spacing and layered pointed silhouettes are crucial. Left and right edges must form a seamless horizontal repeat: a low water segment with matching height, color layers and direction at both borders. No text, labels, grid, shadows or scenery. Only this one horizontal repeatable water sprite on real transparent background.
```
