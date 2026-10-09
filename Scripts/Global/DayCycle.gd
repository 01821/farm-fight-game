class_name DayCycle extends Node

## 昼夜循环：一整天 day_length 秒，前 day_ratio 是白天，其余是夜晚。
##
## 入夜时把画面压暗（预建的 NightTint / CanvasModulate），并广播信号让刷新器放野猪。
## HUD 是 CanvasLayer，属于另一块画布，不会被 CanvasModulate 压暗，所以始终清晰。
##
## 节点顺序无关紧要：消费者开局自己查 is_night，不依赖 _ready 里的信号广播
##（兄弟节点的 _ready 顺序会让开局那次广播丢掉）。

signal day_started(day: int)
signal night_started(day: int)

const DAY_COLOR := Color(1, 1, 1, 1)
const NIGHT_COLOR := Color(0.42, 0.48, 0.72, 1)
const FADE_TIME: float = 2.0

@export var day_length: float = 45.0
@export var day_ratio: float = 0.6
@export var base_wave_size: int = 2
@export var max_wave_size: int = 6
## 关掉就不推进时间（测试里冻结时间用）
@export var running: bool = true

@onready var night_tint: CanvasModulate = $"../NightTint"
## 天气是可选的：没有这个节点也不会出错（测试场景可能只挂一部分）
@onready var weather: Weather = get_node_or_null("../Weather") as Weather

var day: int = 1
var elapsed: float = 0.0
var is_night: bool = false

var _tint: float = 0.0

func _ready() -> void:
	add_to_group("day_cycle")
	night_tint.color = DAY_COLOR

func phase_name() -> String:
	return "夜晚" if is_night else "白天"

## 本夜的波次规模，随天数增长
func wave_size() -> int:
	return mini(base_wave_size + day - 1, max_wave_size)

## 当前时段还剩多少秒
func phase_time_left() -> float:
	if is_night:
		return day_length - elapsed
	return day_length * day_ratio - elapsed

func _process(delta: float) -> void:
	if running:
		_advance(delta)
	_update_tint(delta)

func _advance(delta: float) -> void:
	elapsed += delta
	if elapsed >= day_length:
		elapsed -= day_length
		day += 1
	var night_now: bool = elapsed >= day_length * day_ratio
	if night_now != is_night:
		is_night = night_now
		if is_night:
			print("[时间] 第 ", day, " 天入夜了，野猪要来了（每波 ", wave_size(), " 只）")
			Sfx.play("nightfall")
			night_started.emit(day)
		else:
			print("[时间] 第 ", day, " 天天亮了")
			Sfx.play("dawn")
			day_started.emit(day)

func _update_tint(delta: float) -> void:
	var target: float = 1.0 if is_night else 0.0
	_tint = move_toward(_tint, target, delta / FADE_TIME)
	var col: Color = DAY_COLOR.lerp(NIGHT_COLOR, _tint)
	# 雨天色调叠在昼夜之上 —— 同一块画布只能有一个 CanvasModulate，所以在这里合算
	if weather != null and is_instance_valid(weather):
		col = col.lerp(weather.tint_color(), weather.rain_amount())
	night_tint.color = col

func to_save_data() -> Dictionary:
	return {"day": day, "elapsed": elapsed}

func apply_save_data(d: Dictionary) -> void:
	day = maxi(1, int(d.get("day", 1)))
	elapsed = clampf(float(d.get("elapsed", 0.0)), 0.0, maxf(0.0, day_length - 0.001))
	# 时段以 elapsed 为准重新推导，不存 is_night —— 免得存档里出现自相矛盾的组合
	is_night = elapsed >= day_length * day_ratio
	_tint = 1.0 if is_night else 0.0
	night_tint.color = DAY_COLOR.lerp(NIGHT_COLOR, _tint)
