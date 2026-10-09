class_name Achievements extends Node

## 成就系统（借鉴同类游戏的长期目标设计）。
##
## 每隔一段时间被问一次「还差什么」，条件满足就解锁：打一条日志、放个音、
## 在 HUD 底部弹一条 2.5 秒的提示。解锁记录会进存档。
##
## 条件全部从**已有状态**推导（玩家生涯计数 / 天数 / 目标），不额外维护一套统计。

signal unlocked(id: String, title: String)

const TOAST_TIME: float = 2.5

const LIST: Array[Dictionary] = [
	{"id": "first_harvest", "name": "初次丰收", "desc": "收获第一个作物"},
	{"id": "first_kill", "name": "初次交锋", "desc": "赶跑第一只害兽"},
	{"id": "harvest_10", "name": "绿手指", "desc": "累计收获 10 个作物"},
	{"id": "kill_25", "name": "农场卫士", "desc": "累计赶跑 25 只害兽"},
	{"id": "day_3", "name": "熬过三夜", "desc": "活到第 4 天"},
	{"id": "barn", "name": "谷仓建成", "desc": "攒够 300 金"},
]

@export var enabled: bool = true

var unlocked_ids: Dictionary = {}

var _toast_time: float = 0.0
var _toast_text: String = ""

@onready var player: Player = get_node_or_null("../level/Player") as Player
@onready var cycle: DayCycle = get_node_or_null("../DayCycle") as DayCycle
@onready var controller: FarmController = get_node_or_null("../FarmController") as FarmController

func total() -> int:
	return LIST.size()

func count() -> int:
	return unlocked_ids.size()

func has(id: String) -> bool:
	return unlocked_ids.has(id)

func toast_visible() -> bool:
	return _toast_time > 0.0

func toast_text() -> String:
	return _toast_text

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(0.0, _toast_time - delta)
	if not enabled:
		return
	if player == null or cycle == null or controller == null:
		return
	for entry in LIST:
		var id: String = String(entry.get("id", ""))
		if id.is_empty() or unlocked_ids.has(id):
			continue
		if _condition_met(id):
			_unlock(entry)

## id -> 是否达成。全部从已有状态推导，不额外记数。
func _condition_met(id: String) -> bool:
	match id:
		"first_harvest":
			return player.total_harvested >= 1
		"first_kill":
			return player.total_kills >= 1
		"harvest_10":
			return player.total_harvested >= 10
		"kill_25":
			return player.total_kills >= 25
		"day_3":
			return cycle.day >= 4
		"barn":
			return controller.goal_reached
	return false

func _unlock(entry: Dictionary) -> void:
	var id: String = String(entry.get("id", ""))
	var title: String = String(entry.get("name", id))
	unlocked_ids[id] = true
	_toast_text = "成就达成：%s" % title
	_toast_time = TOAST_TIME
	print("[成就] ", title, " —— ", entry.get("desc", ""), "（", count(), "/", total(), "）")
	Sfx.play("goal")
	unlocked.emit(id, title)

## 直接解锁（调试用）
func force_unlock(id: String) -> bool:
	for entry in LIST:
		if String(entry.get("id", "")) == id:
			if unlocked_ids.has(id):
				return false
			_unlock(entry)
			return true
	return false

func to_save_data() -> Dictionary:
	return {"unlocked": unlocked_ids.keys()}

func apply_save_data(d: Dictionary) -> void:
	unlocked_ids.clear()
	for id in d.get("unlocked", []):
		unlocked_ids[String(id)] = true
