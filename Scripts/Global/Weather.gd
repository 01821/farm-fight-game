class_name Weather extends Node

## 天气系统（借鉴 Stardew / 牧场物语那一类的「雨天」设计）。
##
## 每天天亮时掷一次骰子决定今天晴还是雨。下雨时每隔 RAIN_TICK 秒给所有
## **还没浇过水的作物免费浇一遍** —— 等于当天可以省下浇水的功夫去干别的（比如备战夜晚）。
##
## 画面表现不是自己做 CanvasModulate，而是把「雨天色调」交给 DayCycle 一起算：
## 同一块画布只能有一个 CanvasModulate 生效，两个会互相覆盖。

signal weather_changed(is_rainy: bool)

## 天气种类。
## **干旱**是这一版新加的：那天作物要浇**两遍**才透 ——
## 一遍只湿表面，浇完不长。这是"天气真的影响玩法"，而不只是换个色调。
enum Kind { SUNNY, RAIN, DROUGHT }

const RAIN_TINT := Color(0.55, 0.62, 0.82, 1.0)
const RAIN_TINT_STRENGTH: float = 0.45
const RAIN_TICK: float = 1.0
## 干旱天的色调：偏黄，一眼看得出今天不对劲
const DROUGHT_TINT := Color(1.0, 0.86, 0.6, 1.0)
const DROUGHT_TINT_STRENGTH: float = 0.3

@export var rain_chance: float = 0.3
## 在"没下雨"的那部分里，再分一部分给干旱
@export var drought_chance: float = 0.25

var kind: int = Kind.SUNNY
var is_rainy: bool = false

## 当前场景里的天气实例。
## 作物需要知道"今天要浇几遍"，但天气是个**场景节点不是自动加载单例**，
## 所以留一个静态引用给它查（否则作物只能去遍历分组，每株每次浇水都要查一遍）。
static var instance: Weather

var _cycle: DayCycle
var _land: FarmLand
var _tick: float = 0.0
var _resolved: bool = false

func _ready() -> void:
	add_to_group("weather")
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

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
	var r: float = randf()
	if rain_chance >= 1.0:
		_set_kind(Kind.RAIN)
	elif rain_chance <= 0.0:
		# rain_chance = 0 的语义就是"必然晴天"，那就**不要再掷干旱** ——
		# 否则老测试里"必然晴天"那一条会变成偶发失败（真踩过这种坑）。
		_set_kind(Kind.SUNNY)
	elif r < rain_chance:
		_set_kind(Kind.RAIN)
	elif r < rain_chance + drought_chance:
		_set_kind(Kind.DROUGHT)
	else:
		_set_kind(Kind.SUNNY)
	print("[天气] 第 ", day, " 天：", sky_name(), _day_hint())
	return is_rainy

func _day_hint() -> String:
	match kind:
		Kind.RAIN:
			return " —— 作物会自动浇水"
		Kind.DROUGHT:
			return " —— 干旱！每株要浇两遍才透"
	return ""

func _set_kind(k: int) -> void:
	kind = k
	is_rainy = (k == Kind.RAIN)
	weather_changed.emit(is_rainy)

## 今天把一株作物浇透需要几遍
func water_passes_needed() -> int:
	return 2 if kind == Kind.DROUGHT else 1

func is_drought() -> bool:
	return kind == Kind.DROUGHT

## 强制设定天气（测试 / 调试用）
func set_rainy(value: bool) -> void:
	_set_kind(Kind.RAIN if value else Kind.SUNNY)
	print("[天气] 现在是", sky_name())

## 强制设成干旱（测试 / 调试用）
func set_drought() -> void:
	_set_kind(Kind.DROUGHT)
	print("[天气] 现在是", sky_name())

func sky_name() -> String:
	match kind:
		Kind.RAIN:
			return "雨天"
		Kind.DROUGHT:
			return "干旱"
	return "晴天"

func tint_color() -> Color:
	return DROUGHT_TINT if kind == Kind.DROUGHT else RAIN_TINT

## 给 DayCycle 用的混色强度
func rain_amount() -> float:
	match kind:
		Kind.RAIN:
			return RAIN_TINT_STRENGTH
		Kind.DROUGHT:
			return DROUGHT_TINT_STRENGTH
	return 0.0

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
