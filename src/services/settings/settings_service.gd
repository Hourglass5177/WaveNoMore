extends Node

## 全局设置服务。负责配置文件读写，立即应用音量和窗口模式，并向关卡提供校准值。

## 设置已写入运行中的音频总线和窗口后发出。
signal settings_changed

## 配置文件保存位置，位于 Godot 用户数据目录。
const SETTINGS_PATH := "user://settings.cfg"
## 相纹视觉强度的允许范围。它只影响明度和辉光，不能删减真实波前。
const MIN_TUNING_WAVE_INTENSITY := 0.35
const MAX_TUNING_WAVE_INTENSITY := 1.0
const DEFAULT_TUNING_WAVE_INTENSITY := 0.85

## BGM 所在 Music 总线的音量，单位为 dB；数值越小声音越轻。
var music_volume_db: float = -4.0
## 敲钟和判定反馈所在 GameplaySFX 总线的音量，单位为 dB。
var gameplay_sfx_volume_db: float = -2.0
## 菜单反馈所在 UI 总线的音量，单位为 dB。
var ui_volume_db: float = -4.0
## 音频输出校准量，单位为毫秒；正值让谱面时钟等待更久再起算。
var audio_output_offset_ms: int = 0
## 输入补偿量，单位为毫秒；正值把较晚收到的按键映射到更早判定时刻。
var input_offset_ms: int = 0
## 画面提前量，单位为毫秒；正值让视觉比真实判定时间更早推进。
var visual_offset_ms: int = 0
## 屏幕震动强度倍率；常用范围 0～1，0 表示关闭。
var screen_shake_scale: float = 1.0
## 闪光强度倍率；常用范围 0～1，0 表示关闭。
var flash_scale: float = 1.0
## 相纹视觉强度；只调整透明度和辉光，不改变载波数量、频率或传播速度。
var tuning_wave_intensity: float = DEFAULT_TUNING_WAVE_INTENSITY
## 是否显示仅供开发使用的关卡调试 HUD。
var debug_hud_enabled: bool = false
## 是否使用独占全屏窗口模式。
var fullscreen: bool = false


func _ready() -> void:
	load_settings()
	apply_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	music_volume_db = float(config.get_value("audio", "music_volume_db", music_volume_db))
	gameplay_sfx_volume_db = float(config.get_value("audio", "gameplay_sfx_volume_db", gameplay_sfx_volume_db))
	ui_volume_db = float(config.get_value("audio", "ui_volume_db", ui_volume_db))
	audio_output_offset_ms = int(config.get_value("calibration", "audio_output_offset_ms", audio_output_offset_ms))
	input_offset_ms = int(config.get_value("calibration", "input_offset_ms", input_offset_ms))
	visual_offset_ms = int(config.get_value("calibration", "visual_offset_ms", visual_offset_ms))
	screen_shake_scale = float(config.get_value("accessibility", "screen_shake_scale", screen_shake_scale))
	flash_scale = float(config.get_value("accessibility", "flash_scale", flash_scale))
	tuning_wave_intensity = _read_tuning_wave_intensity(config)
	debug_hud_enabled = bool(config.get_value("development", "debug_hud_enabled", debug_hud_enabled))
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume_db", music_volume_db)
	config.set_value("audio", "gameplay_sfx_volume_db", gameplay_sfx_volume_db)
	config.set_value("audio", "ui_volume_db", ui_volume_db)
	config.set_value("calibration", "audio_output_offset_ms", audio_output_offset_ms)
	config.set_value("calibration", "input_offset_ms", input_offset_ms)
	config.set_value("calibration", "visual_offset_ms", visual_offset_ms)
	config.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	config.set_value("accessibility", "flash_scale", flash_scale)
	tuning_wave_intensity = clampf(
		tuning_wave_intensity,
		MIN_TUNING_WAVE_INTENSITY,
		MAX_TUNING_WAVE_INTENSITY
	)
	config.set_value("accessibility", "tuning_wave_intensity", tuning_wave_intensity)
	config.set_value("development", "debug_hud_enabled", debug_hud_enabled)
	config.set_value("display", "fullscreen", fullscreen)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("无法保存设置：%s" % error_string(error))
		return false
	apply_settings()
	return true


func apply_settings() -> void:
	tuning_wave_intensity = clampf(
		tuning_wave_intensity,
		MIN_TUNING_WAVE_INTENSITY,
		MAX_TUNING_WAVE_INTENSITY
	)
	_set_bus_volume(&"Music", music_volume_db)
	_set_bus_volume(&"GameplaySFX", gameplay_sfx_volume_db)
	_set_bus_volume(&"UI", ui_volume_db)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	settings_changed.emit()


func total_judgment_offset_us() -> int:
	# 兼容旧调用名：判定补偿只包含输入偏移；音频和画面偏移由 SongClock 分开保存。
	return input_offset_ms * 1000


func input_compensation_sec() -> float:
	return float(input_offset_ms) / 1000.0


func audio_calibration_sec() -> float:
	return float(audio_output_offset_ms) / 1000.0


func visual_lead_sec() -> float:
	return float(visual_offset_ms) / 1000.0


func _read_tuning_wave_intensity(config: ConfigFile) -> float:
	# 旧字段控制的是“删掉多少波圈”，与现在的明度含义并不等价。
	# 只有明确保存过新字段时才沿用玩家选择；仅有旧字段则采用新的可读默认值。
	var stored_intensity: float = DEFAULT_TUNING_WAVE_INTENSITY
	if config.has_section_key("accessibility", "tuning_wave_intensity"):
		stored_intensity = float(config.get_value(
			"accessibility",
			"tuning_wave_intensity",
			DEFAULT_TUNING_WAVE_INTENSITY
		))
	return clampf(
		stored_intensity,
		MIN_TUNING_WAVE_INTENSITY,
		MAX_TUNING_WAVE_INTENSITY
	)


func _set_bus_volume(bus: StringName, value_db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, value_db)
