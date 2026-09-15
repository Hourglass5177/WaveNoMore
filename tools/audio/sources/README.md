# 菜单采样来源

## 当前：布料软接触（全部五个菜单角色）

- 作品：soft impact.wav
- 作者：lipalearning
- 来源：https://freesound.org/people/lipalearning/sounds/427973/
- 许可：CC0，https://creativecommons.org/publicdomain/zero/1.0/
- 录制内容：打结成团的连帽衫落在沙发、地毯和枕头上。
- 下载：https://cdn.freesound.org/previews/427/427973_4687265-hq.mp3
- 获取日期：2026-09-15

保留作者公开的高质量 MP3 预听 `soft-fabric-impact-hq.mp3`。通过 miniaudio 解码为 48 kHz 单声道 PCM16 后截取三个短段：`fabric-touch.wav` 为 23.245～23.645 秒，`fabric-low.wav` 为 12.880～13.260 秒，`fabric-tap.wav` 为 16.915～17.295 秒。这些是预听解码后的片段，并非原始无损文件。

生成脚本从短段中去掉接触前空白，调整响度，以 3 ms 平滑起点、最多 65 ms 平滑结束。确认 190 ms、返回 180 ms、切换 105 ms、微调 85 ms、入场 230 ms。不添加合成层、音高处理或混响。Minecraft 羊毛放置仅作用户指定的质感参考，未使用其游戏音频。

随机变体增加两个原录音短段：`fabric-touch-2.wav` 为 19.305～19.705 秒，`fabric-touch-3.wav` 为 35.550～35.950 秒，同样保存为 48 kHz 单声道 PCM16。生成时分别从 5 ms、20 ms 开始，制作各角色的 `_2.wav`、`_3.wav`，匹配原角色能量和时长，保留真实落点差别。

## 旧候选：古琴（已退出默认装配）

- 作品：Guqin-open-strings.wav
- 作者：RafaelCaro
- 原始页面：https://freesound.org/people/RafaelCaro/sounds/176266/
- 许可：Creative Commons Attribution 4.0 International（CC BY 4.0）
- 许可文本：https://creativecommons.org/licenses/by/4.0/
- 获取日期：2026-09-15
- 下载：作者页面公开的高质量预听 `https://cdn.freesound.org/previews/176/176266_3274730-hq.mp3`。

此处保留下载的 MP3，以及使用 miniaudio 解码为 48 kHz / 双声道 / PCM16 的 WAV，供离线加工复现。这里的 WAV 是预听文件的解码版本，不是作者上传的无损原件。无需运行时解码库。

`../generate_menu_sounds.py` 截取独立拨弦，低通、调整包络与响度，生成三个菜单角色。未使用原曲演奏片段，也未增加合成乐器层。所有古琴衍生文件沿用署名；源文件与制作工具不作为游戏播放资源导出。

## 旧候选：木鱼组（已退出默认装配）

- 作品：Ethan's Temple Blocks
- 作者：Ethan Winer
- 原始页面：https://ethanwiner.com/ewsf2.html
- 下载：https://ethanwiner.com/temple_blocks.zip
- 获取日期：2026-09-15
- 作者原文：These files are made available for you to use in any way you'd like, royalty free, including for commercial projects, with no attribution required.
- SF2 的 ICMT：Copyrighted, but placed into the public domain April 23, 2002.

保留原始 `temple_blocks.sf2`。选取最轻的 p 力度层：确认使用 `Temple Block 3 p(L/R)`（sample ID 16、17），返回使用 `Temple Block 2 p(L/R)`（sample ID 24、25）。对应的双声道 PCM 原样提取到 `temple-block-3-soft.wav` 和 `temple-block-2-soft.wav`，44100 Hz / 16 bit。它们是不同大小的木鱼组实录，并非同一录音变调，也不使用 SF2 播放器的合成包络。

生成脚本仅将两声转换为 48 kHz、调整响度，首端 0.5 ms 和尾端 40 ms 平滑收束；主体保留录音的自然敲击与衰减，不低通、不额外压缩、不叠加混响。

随游戏分发的署名在 `assets/audio/menu/ATTRIBUTION.txt`，发布时应保留该文本。
