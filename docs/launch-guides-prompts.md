# 开屏图样生成记录

2026-09-15，使用 OpenAI 内置 `image_gen` 工具。最终耳机按用户最新选择使用第一次生成版本；两次简化候选不用于游戏。手柄图样与耳机分别生成，中文、字母、引线及完整黑底页面由 Godot 排版。

## 耳机最终提示词

Create a refined game UI illustration asset, one solitary over-ear HEADPHONES emblem centered on a perfectly pure solid BLACK #000000 square canvas. Bone-white / warm ivory very fine engraved ink outlines, restrained ancient Chinese Chu culture aesthetic, subtle dry-brush breaks and delicate concentric resonant curves engraved into the two ear cups, understated elegance and precise symmetric silhouette. A recognizable contemporary over-ear headphone headband and two softly rounded earcups, frontal elevation, no perspective, no cable. The emblem occupies the middle 65% of canvas width and height with generous perfectly black margins. The craftsmanship should feel like a beautiful etched ritual instrument diagram, not a fantasy helmet, no skulls. Almost monochrome, fine luminous ivory strokes with faint desaturated gray-purple secondary lines, NO glow cloud. Crisp high resolution illustration suitable for a 4K game launch information screen. NO text, NO lettering, NO watermark, NO surrounding ornaments, NO rectangular border, NO gradients or background texture. Output one square image.

## 控制器最终提示词

Create a premium game controller reference illustration asset for a Chinese dark-fantasy rhythm game. One large symmetrical outline of a modern Xbox-style gamepad, precise front elevation with a slightly top-visible shoulder edge so both triggers LT RT behind bumpers LB RB are distinctly visible. Correct asymmetric analog layout: left analog stick upper left, plus-shaped D-pad lower left, four circular face buttons upper right in diamond Y top / X left / B right / A bottom (circles EMPTY, NO letters), right analog stick lower right. In the center three small distinct round buttons: left View, center Home, right Menu, with simple pictogram symbols only. Two downward handles, continuous clean elegant shell silhouette, realistic proportions. Warm bone-white thin engraved line art on PERFECT solid black #000000 background, subtle dry-brush detail and faint gray-purple secondary construction lines, nearly monochrome and restrained. Borrow the legibility of an antique technical engraving, no ornate distracting decoration, no perspective skew, no colored buttons, no photoreal plastic render, no glow. Controller occupies 86% width of a 1536x1024 landscape canvas, fully visible including handles/triggers, ample black margins. NO annotations, NO leader lines, NO text, NO labels, NO logos, NO watermark. This diagram will receive accurate labels and leaders in the engine. Return a single high-resolution image.

## 最终文件

- `assets/ui/art/boot/guides/headphones.png`
- `assets/ui/art/boot/guides/controller.png`
- 两张完整排版大图：`outputs/launch-guides/headphones-3840.png`、`outputs/launch-guides/controller-3840.png`。
