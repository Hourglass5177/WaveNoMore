## 一关共用的玩法规则表。判定层与表现层都从这里取数，避免画面提示和实际判定使用两套参数。
@tool
class_name GameplayRuleSet
extends Resource

@export_group("Tap / Hold Windows (ms)")
## PERFECT 的最大绝对时间误差，单位毫秒；越大越宽松，且应不大于 GOOD 窗。
@export_range(1, 500, 1) var perfect_window_ms: int = 45
## GOOD 的最大绝对时间误差，单位毫秒；越大越宽松，且应夹在 PERFECT 与 PASS 之间。
@export_range(1, 500, 1) var good_window_ms: int = 90
## 主动按键仍能命中音符的最大绝对误差，单位毫秒；越大越宽松。
@export_range(1, 500, 1) var pass_window_ms: int = 135
## 无人命中时自动判 MISS 的晚侧边界，单位毫秒；越大，音符等待越久才过期。
@export_range(1, 1000, 1) var miss_window_ms: int = 180
## Hold 尾部获 PERFECT 的最大松键误差，单位毫秒；越大越宽松。
@export_range(1, 500, 1) var hold_release_perfect_ms: int = 60
## Hold 尾部获 GOOD 的最大松键误差，单位毫秒；越大越宽松。
@export_range(1, 500, 1) var hold_release_good_ms: int = 110
## Hold 尾部仍能获 PASS 的最大松键误差，单位毫秒；越大越宽松。
@export_range(1, 500, 1) var hold_release_pass_ms: int = 170
## Hold 中途断按后允许续按的宽限，单位毫秒；越大越不易因短暂松手 MISS。
@export_range(1, 500, 1) var hold_sustain_grace_ms: int = 100
## 同组双押两次按下允许相差的毫秒数；越大双押越宽松。
@export_range(1, 500, 1) var chord_tolerance_ms: int = 75

@export_group("Tuning")
## 连续跟随的确定性采样间隔，单位 tick；只影响判定采样，不在画面上生成离散点。
@export_range(1, 240, 1) var tuning_sample_interval_ticks: int = 30
## 判定引导允许的前后时间余量，单位毫秒；可见引导带必须与此数值使用同一计算。
@export_range(0, 500, 1) var tuning_guide_time_window_ms: int = 180
## 除时间余量外再加入的归一化空间余量；0.08 表示频率轴总长的 8%。
@export_range(0.0, 0.5, 0.001) var tuning_spatial_margin: float = 0.08
## 连续有效采样占比达到该值时获得 PERFECT。
@export_range(0.0, 1.0, 0.001) var tuning_perfect_coverage: float = 0.90
## 连续有效采样占比达到该值时获得 GOOD。
@export_range(0.0, 1.0, 0.001) var tuning_good_coverage: float = 0.75
## 连续有效采样占比达到该值时至少获得 PASS；低于它为 MISS。
@export_range(0.0, 1.0, 0.001) var tuning_pass_coverage: float = 0.60
## 普通段及每个调频段开始时采用的统一基准频率，单位 Hz。
@export_range(0.1, 30.0, 0.01) var tuning_base_frequency_hz: float = 4.35
## 玩家可调到的最低载波频率，单位 Hz。
@export_range(0.1, 30.0, 0.01) var tuning_min_frequency_hz: float = 1.8
## 玩家可调到的最高载波频率，单位 Hz。
@export_range(0.1, 30.0, 0.01) var tuning_max_frequency_hz: float = 6.9
## 频率变化 1 Hz 对应的滑条设计长度，单位像素；保证不同滑条使用相同调频粒度。
@export_range(1.0, 1000.0, 1.0) var tuning_pixels_per_hz: float = 160.0
## 手柄摇杆满幅时，虚拟游标每秒移动的设计像素数。
@export_range(1.0, 3000.0, 1.0) var tuning_cursor_speed_px_sec: float = 720.0
## 左右摇杆用于调频时的死区；小于此幅度的漂移视为回中。
@export_range(0.0, 0.95, 0.01) var tuning_stick_deadzone: float = 0.18

@export_group("Rapid")
## PERFECT 所需“有效次数/目标次数”比例，范围 0～2；越大越难。
@export_range(0.0, 2.0, 0.01) var rapid_perfect_ratio: float = 1.0
## GOOD 所需次数比例，范围 0～2；越大越难。
@export_range(0.0, 2.0, 0.01) var rapid_good_ratio: float = 0.85
## PASS 所需次数比例，范围 0～2；越大越难。
@export_range(0.0, 2.0, 0.01) var rapid_pass_ratio: float = 0.65

@export_group("Score")
## 单个 PERFECT 的基础分；数值越大，此档判定权重越高。
@export_range(0, 100000, 1) var perfect_score: int = 1000
## 单个 GOOD 的基础分；数值越大，此档判定权重越高。
@export_range(0, 100000, 1) var good_score: int = 700
## 单个 PASS 的基础分；数值越大，此档判定权重越高。
@export_range(1, 100000, 1) var pass_score: int = 400
## 单个 MISS 的基础分；通常为 0，增大会让漏击仍得分。
@export_range(0, 100000, 1) var miss_score: int = 0
## 连击奖励的倍率上限；越大，高连击额外得分越多。
@export_range(0.0, 10.0, 0.01) var max_combo_multiplier: float = 2.0
## 从无连击爬升到倍率上限所需步数；越大，倍率增长越慢。
@export_range(1, 500, 1) var combo_steps_to_max: int = 100

@export_group("Health / Stray Input")
## 满魂火上限与开局值；越大，可承受的固定伤害次数越多。
@export_range(1, 1000, 1) var max_soul_fire: int = 100
## 每个新伤害组发生 MISS 时扣除的魂火；越大，失败惩罚越重。
@export_range(0, 1000, 1) var miss_damage: int = 20
## 开启时，没有被任何机制消费的乱按会中断 Combo。
@export var stray_input_breaks_combo: bool = false
## 开启时，乱按除断 Combo 外还会按一次 MISS 伤害扣魂火。
@export var stray_input_damages: bool = false

@export_group("Presentation Timing")
## 普通音符从生成点到判定点的飞行秒数；越大，音符出现越早、移动越慢。
@export_range(0.1, 10.0, 0.01) var approach_duration_sec: float = 2.25
## 正式歌曲时间零点前的预备秒数；越大，玩家获得的开场准备越久。
@export_range(0.0, 5.0, 0.01) var preroll_sec: float = 2.0
## 失败后仍让在途表现收尾的秒数；越大，进入结算越晚。
@export_range(0.0, 5.0, 0.01) var fail_settle_sec: float = 0.7

@export_group("Physical Wave Field")
## 物理交互采用的设计画布尺寸，单位像素；X 向右、Y 向下，改变后所有坐标需同步调整。
@export var wave_canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 生钟波源中心的设计坐标，单位像素；X/Y 增大分别向右/向下移动。
@export var life_wave_origin: Vector2 = Vector2(350.0, 280.0)
## 死钟波源中心的设计坐标，单位像素；X/Y 增大分别向右/向下移动。
@export var death_wave_origin: Vector2 = Vector2(1570.0, 800.0)
## 生音符生成坐标，单位像素；通常在画布右上外侧。
@export var life_note_spawn: Vector2 = Vector2(2040.0, 220.0)
## 死音符生成坐标，单位像素；通常在画布左下外侧。
@export var death_note_spawn: Vector2 = Vector2(-120.0, 860.0)
## 生音符的中央提示/判定坐标，单位像素。
@export var life_note_cue: Vector2 = Vector2(960.0, 540.0)
## 死音符的中央提示/判定坐标，单位像素；当前与生音符共用中心。
@export var death_note_cue: Vector2 = Vector2(960.0, 540.0)
## 路径外侧控制点的弯曲量，单位像素；越大，入场弧线向外鼓得越明显。
@export_range(0.0, 600.0, 1.0) var note_curve_outer_bend_px: float = 220.0
## 靠近中心的曲线控制柄长度，单位像素；越大，音符切入中心时转弯更舒缓。
@export_range(0.0, 800.0, 1.0) var note_curve_center_handle_px: float = 360.0
## 波前传播速度，单位像素/秒；越大，按键后更快接触在途音符。
@export_range(10.0, 4000.0, 1.0) var wave_speed_px_sec: float = 2400.0
## 可发生接触的波前半宽，单位像素；越大，物理相交的空间容差越宽。
@export_range(1.0, 120.0, 1.0) var wave_front_half_width_px: float = 25.0
