# Ghost 游戏图标

2026-09-15：以用户提供的 `Assets/Ghost/A12B39340822B30C8D02985C052C68E8等2项文件/A12B39340822B30C8D02985C052C68E8.png` 为输入，使用内置 imagegen 编辑下缘白色柔光。原始素材未覆盖，局内 Ghost 贴图未更换。

- `assets/ui/art/app_icon/ghost_logo.png`：保留生成结果的 1254×1254 RGBA 成品，可作为独立标识使用。
- `assets/ui/art/app_icon/ghost_icon.png`：256×256 窗口图标，由成品等比缩小。
- `assets/ui/art/app_icon/ghost_icon.ico`：Windows 图标，包含 16、24、32、48、64、128、256 px 七档。

`project.godot` 的 `config/icon` 使用 PNG；游戏 Windows 导出预设的 `application/icon` 和 `application/console_wrapper_icon` 使用 ICO。未修改两个编辑器的导出覆盖项，未重新构建现有程序。

## 图像提示词

第一轮，输入为原画：

> Edit the supplied existing Ghost eye sprite for use as the game application icon. Preserve the exact original silhouette, asymmetrical tilt, maroon spiral, pale cyan eye, blue-gray pigment texture, hand painted irregular edges, and all hanging drips. This is a very small lighting edit, not a redesign. Add a restrained soft WHITE rim glow only along the LOWER outer edge of the eye and the bottom edges/tips of its hanging drips, softly fading into transparency; a narrow luminous edge with a small diffuse white halo, enough to read on a dark desktop but no overexposure. Keep upper contours and internal eye unchanged. No new symbols, text, particles, badges, icon tile, frame, shadows, or colored background. Output one centered square 1024x1024 PNG with a genuinely transparent alpha background, preserving aspect ratio, eye filling approximately 85% of the square with enough transparent margin for all glow. Do not include a checkerboard as image pixels. Keep original artwork as faithfully as possible.

第二轮，输入为第一轮结果，收细过亮的下缘：

> Refine this exact application icon image with ONE CHANGE ONLY: substantially reduce the white bottom glow. It currently looks like thick overexposed neon tubing. Reduce luminous rim thickness to about ONE QUARTER of current width, and diffuse halo brightness to about ONE THIRD of current intensity. A little elegant soft offwhite light clinging to the lower edges and drip tips only, uneven and painterly, not a thick white outline, preserve the bluegrey lower body. Preserve ALL remaining details, exact shape, original painterly pigment, texture, spiral, colors and placement. Keep true transparent alpha background. Keep square image with transparent margins. No other changes.

实际输出为 1254×1254；PNG 图标和 ICO 仅作尺寸及封装转换，不再次绘制。素材来源与使用权沿用项目原画归档。
