# 中央卷流补绘源

当前采用 `rising-profile-green.png`，使用内置 imagegen 的编辑模式，以用户手绘轮廓、上一版单股动作与原 `edge.png` 为参照。历史源图保留，不覆盖原始素材。

八格均为单股上侧水臂，另一侧在运行时中心对称旋转 180°，不另画一个容易闭合的下侧轮廓。下缘从水带平顺向上，厚度增加在上缘；右上游离浪尖与另一股浪根保留开口。细节沿用原画的粉灰、浅紫与骨白细线。

设计画布 576×384，帧纹理 384×256。所有格共用缩放和入口基准；生成图的入口偏低，归一化统一上移 26 纹理像素（粘贴位置 4,-22）。八个关键形态全部采用，补间后才生成根部接合渐变。运行材质以原画不透明颜色分位值校准色阶，并沿卷臂映射少量原水带细纹。

## 最终生成提示词

Edit FIRST image (8 single upper wave animation poses, 4 columns x 2 rows, 3:1 total sheet). SECOND image is the user's hand-drawn required silhouette, and is the highest priority for the root profile. THIRD image is the original game's mandatory palette/brush reference. Keep the same green background, 8-cell grid, fixed (288,192) center in each 576x384 design cell. Repaint the single wave in every cell to follow the sketch: a broad flowing ribbon rising from the left, with TWO smoothly continuous contours. The LOWER contour must stay nearly level coming in, then curve smoothly upward into the underside of the arch, with no hanging belly, no downward lobe, no blunt vertical shoulder or corner. Keep thickness by raising the UPPER contour, not by lowering the bottom contour. Approximate lower contour coordinates in design pixels: (0,215), (80,213), (135,205), (175,183), (210,125), (250,98), (320,91), then a thin free curling tip around (430,132). Upper contour rises earlier, around (80,160), (140,126), (195,61), (265,35), (340,45), tapering into that free tip. All transitions smooth, lively and hand-drawn, not cubic corner bends or a geometric frame. The sketch is a silhouette reference only; do not copy its paper, lines or black ink. Single UPPER wave only, NO lower partner, no right water root. Empty center radius at least 82 design pixels. Preserve broad root thickness (50 px entrance, 75-90 rising shoulder), and preserve open upper-right free tip. Eight stages can vary lip curling and crest flecks but ALL retain this stable smooth up-sweeping lower root profile. Use lighter powder lavender, pink-gray, bone-white long streaks and small muted blue facets, matching third reference. Refined original hand-painted flat planes and fine flowing strokes, no dark blue shading, no glossy 3D shine. No text or labels.
