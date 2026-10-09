class_name Weather extends Node

## 天气系统（借鉴 Stardew / 牧场物语那一类的「雨天」设计）。
##
## 每天天亮时掷一次骰子决定今天晴还是雨。下雨时每隔 RAIN_TICK 秒给所有
## **还没浇过水的作物免费浇一遍** —— 等于当天可以省下浇水的功夫去干别的（比如备战夜晚）。
##
## 画面表现不是自己做 CanvasModulate，而是把「雨天色调」交给 DayCycle 一起算：
## 同一块画布只能有一个 CanvasModulate 生效，两个会互相覆盖。

signal weather_changed(is_rainy: bool)

const RAIN_TINT := Color(0.55, 0.62, 0.82, 1.0)
const RAIN_TINT_STRENGTH: float = 0.45
const RAIN_TICK: float = 1.0

@export var rain_chance: float = 0.3

var is_rainy: bool = false

var _cycle: DayCycle
var _land: FarmLand
var _tick: float = 0.0
var _resolved: bool = false

func _ready() -> void:
	add_to_group("weather")

## DayCycle / FarmLand 可能排在后面，_ready 时分组还没注册，所以允许之后再补查
func _try_resolve() -> bool:
	if not _resolved:
		_cycle = get_tree().get_first_node_in_group("day_cycle") as DayCycle
		if _cycle != null:
			_cycle.day_started.connect(_on_day_started)
		_land = get_tree().get_first_node_in_group("farm_land") as FarmLand
		if _cycle != null and _land != null:
			_resolved = true
	return _resolved

func _on_day_started(day: int) -> void:
	roll_for_day(day)

## 掷今天的天气，返回是否下雨。测试可以直接调，也可以先改 rain_chance。
func roll_for_day(day: int) -> bool:
	is_rainy = randf() < rain_chance
	weather_changed.emit(is_rainy)
	print("[天气] 第 ", day, " 天：", "雨天 —— 作物会自动浇水" if is_rainy else "晴天")
	return is_rainy

## 强制设定天气（测试 / 调试用）
func set_rainy(value: bool) -> void:
	if is_rainy == value:
		return
	is_rainy = value
	weather_changed.emit(is_rainy)
	print("[天气] 现在是", "雨天" if is_rainy else "晴天")

func sky_name() -> String:
	return "雨天" if is_rainy else "晴天"

func tint_color() -> Color:
	return RAIN_TINT

## 给 DayCycle 用的混色强度
func rain_amount() -> float:
	return RAIN_TINT_STRENGTH if is_rainy else 0.0

func _process(delta: float) -> void:
	if not _try_resolve():
		return
	if not is_rainy:
		return
	_tick += delta
	if _tick < RAIN_TICK:
		return
	_tick = 0.0
	if _land != null and is_instance_valid(_land):
		var n: int = _land.water_all()
		if n > 0:
			print("[天气] 雨水浇了 ", n, " 株作物")
