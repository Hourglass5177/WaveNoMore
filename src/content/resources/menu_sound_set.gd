class_name MenuSoundSet
extends Resource

## 菜单声音素材集中装配，玩家音量沿用 Music / UI 总线设置。
## 默认各按钮角色使用 AudioStreamRandomizer：三种实录随机播放，避免连续重复。
@export var ambient: AudioStream
@export var focus: AudioStream
@export var confirm: AudioStream
@export var cancel: AudioStream
@export var adjust: AudioStream
@export var open: AudioStream
