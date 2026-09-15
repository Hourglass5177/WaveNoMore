# 菜单环境与交互音效

2026-09-15。正式游戏沿用 `MenuAudioService`、Music 与 UI 总线；不增加玩家设置入口，不改变关卡音乐、编钟判定音或 Replay。

工程音频总线使用 Godot 4 的 `audio/buses/default_bus_layout`，Music、GameplaySFX 和 UI 按已有设置分别生效。

## 素材

| 素材／角色 | 接入位置 | 当前效果 |
| --- | --- | --- |
| `provided/Ambient1.ogg` | 标题画面开始显现时的菜单环境 | 原包素材，约 34.5 秒，循环播放 |
| `provided/Button1.ogg`、`Button2.ogg`、`Button3.ogg` | 备选 | 原包素材，保留供替换 |
| `crafted/focus.wav` | 移入、键盘／手柄换项、选关与随从切换 | 布料轻触，105 ms，峰值 -33 dBFS |
| `crafted/confirm.wav` | 确认、打开按钮、开始关卡、装备 | 稍实的柔软接触，190 ms，峰值 -27 dBFS |
| `crafted/cancel.wav` | 返回、关闭、未解锁反馈 | 略低、略轻的闷触感，180 ms，峰值 -29 dBFS |
| `crafted/adjust.wav` | 设置滑块与下拉选择 | 极轻短触，85 ms，峰值 -35 dBFS |
| `crafted/open.wav` | 首次点击任意处开始 | 短暂轻触，230 ms，峰值 -29 dBFS |

路径相对 `assets/audio/menu/`。默认五个按钮声统一采用 lipalearning 的 [soft impact.wav](https://freesound.org/people/lipalearning/sounds/427973/)（CC0），录制对象为布团落在沙发、地毯、枕头上。古琴与木鱼候选退出默认播放；原采样在制作目录中保留来源记录。

`tools/audio/generate_menu_sounds.py` 从保存的短段制作五个角色，仅去除接触前空白、调整响度、以 3 ms 起点和最多 65 ms 尾部平滑切口。没有乐器合成、变调或附加混响。输出 48 kHz / PCM16 / 双声道 WAV，制作依赖 NumPy，运行时无额外依赖。生成 `builds/audio-review/menu-cues-fabric.wav` 全套试听、`confirm-return-fabric.wav` 确认／返回对照及峰值/RMS 报告。

每种角色保留原声，再增加 `_2.wav`、`_3.wav` 两种独立布料落点，共 15 个文件。新变体与该角色原声匹配 RMS 和时长，峰值最多高出原声 2 dB。`menu_sound_set.tres` 为每种角色装配一个等权 `AudioStreamRandomizer`，使用不连续重复模式；不额外随机改变音高或音量，保持克制的质感。`builds/audio-review/fabric-varied-clicks.wav` 为连续确认试听。

## 播放关系

- 工作室开屏结束、标题画面开始显现时即播放 Ambient1，早于点击提示出现；等待任意键及点击展开菜单时持续播放，不重头播放。跳过开屏或直接返回标题也沿用同一环境音。标题、选关、本地谱面与结算页间连续播放。
- 加载时约 0.3 秒淡出，关卡开始前静音；返回菜单继续环境音。
- 歌曲试听与 Ambient1 互斥，试听结束恢复环境音。校准期间暂停环境与按钮音，结束或取消后恢复。
- 固定播放器复用，每种最多两声；选择和微调最短间隔 65 ms，确认／返回最短间隔 35 ms。自动恢复焦点、禁用按钮不发声。
- 音量沿用设置中的音乐与 UI，不改玩家保存值。新增音效不参与音游时钟与判定。

## 更换素材与分发

在 `content/presentation/menu_sound_set.tres` 展开对应角色的随机音频资源，替换其中三个 Stream。也可以直接换为一个 AudioStream 恢复单声。按钮可用 `ui_sound` 元数据指定 `focus`、`confirm`、`cancel`、`adjust`、`open` 或 `none`；换页箭头关闭默认确认声，由实际换页入口发声，避免重复。

短 WAV 导入保持 Disabled 压缩（`compress/mode=0`），不自动归一化。原 Ambient 与 Button 保持 OGG。来源说明 `assets/audio/menu/ATTRIBUTION.txt` 已纳入三个导出预设，本轮不导出应用。策划判定与伤害参数没有变化。

## 验证

`tests/integration/app_flow/run_menu_audio_tests.gd` 覆盖启动静音、标题唤醒、循环、菜单路由、试听、校准互斥、重复接线、焦点恢复、复音限速，并在 Compatibility 下捕获实际 UI 总线输出。声音风格仍以用户试听为准。

布料版本重新导入后，29 项检查全部通过；五个素材首尾为零，未削波。

环境音提前到主界面显现后，47 项检查通过，包含开屏静音、提示出现前开始播放、等待点击期间持续播放，以及点击后不重播。

加入随机变体后共 44 项检查通过：逐角色对照实际混出的 PCM，验证三份内容不同、连续 32 次随机播放不重复相邻录音，并保留 UI 总线真实输出检查。15 个文件首尾为零，同角色三种录音的 RMS 差小于 0.01 dB；新增文件均禁用导入压缩。运行时仍只有五个固定播放器。
