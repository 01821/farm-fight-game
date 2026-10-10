extends Node

## 目标引导链（自动加载单例，全局名字 Guide）——「一环接一环」。
##
## 玩家应该**永远知道下一步干嘛**。这一串目标按顺序推进：
## 每完成一个就弹一条提示，HUD 上常驻显示当前那一条，做完了自动换下一条。
##
## 两个刻意的设计决定：
##   1. **条件全部从已有状态推导**（生涯计数 / 矿洞累计 / 升级等级），
##      和成就系统一个路子 —— 不额外维护一套"任务进度"。
##   2. **链子刻意把农场和矿洞串起来**。之前两条线是各玩各的：
##      农场赚钱买种子、矿洞赚钱也只能买种子，两边都不产出"让另一边变强的东西"。
##      这条链子至少让玩家知道"哦，原来下矿是这个用处"。

signal step_done(id: String, text: String, next_text: String)

const LIST: Array[Dictionary] = [
	{"id": "plant_3", "text": "在耕地上种下 3 株作物", "hint": "手持种子袋，站在褐色耕地上按 F"},
	{"id": "water_1", "text": "给作物浇一次水", "hint": "先到水缸边按 F 装满水壶，再对着作物按 F"},
	{"id": "harvest_1", "text": "收获第一个成熟作物", "hint": "拿着收获篮，对着成熟的作物按 F"},
	{"id": "sell_1", "text": "去商店把收获卖掉", "hint": "拿着收获篮站进商店按 F"},
	{"id": "goal_300", "text": "攒够 300 金", "hint": "多种多卖，顺便防一下夜里的害兽"},
	{"id": "mine_1", "text": "从右边的矿洞口下一趟矿", "hint": "走到洞口按 F。火把烧完会自动带你回来"},
	{"id": "boss_1", "text": "在矿洞深处拆掉关底", "hint": "先下到第 3 层，深处那台机械就是要拆的"},
	{"id": "goods_1", "text": "收一次动物产的蛋", "hint": "每天早上动物会在脚边下一个"},
	{"id": "process_1", "text": "把作物拿到加工坊做成成品", "hint": "加工坊在地图左上，按 F 价值翻倍"},
	{"id": "upgrade_1", "text": "买第一个土地升级", "hint": "把道具切到「工具箱」，站在商店按 F"},
]

var done: Dictionary = {}
var _toast_time: float = 0.0
var _toast_text: String = ""

## ⚠️ Guide 是**自动加载单例**，它挂在 /root 下面。
##    所以不能用 `../level/Player` 这种相对路径 —— 那是给 base_level 里的节点用的。
##    （成就系统用相对路径是对的，因为它本身就是 base_level 的一个节点。）
##    这里按分组查，并且在 Player 还没就绪时允许之后再补查。
var player: Player
var controller: FarmController

func _try_resolve() -> bool:
	if player != null and is_instance_valid(player) \
			and controller != null and is_instance_valid(controller):
		return true
	player = get_tree().get_first_node_in_group("player") as Player
	controller = get_tree().get_first_node_in_group("farm_controller") as FarmController
	return player != null and controller != null

func total() -> int:
	return LIST.size()

func count_done() -> int:
	return done.size()

func has(id: String) -> bool:
	return done.has(id)

## 当前该做的那一条；全做完了返回空字典
func current() -> Dictionary:
	for e in LIST:
		if not done.has(String(e.get("id", ""))):
			return e
	return {}

func current_text() -> String:
	var e := current()
	if e.is_empty():
		return "全部完成！"
	return String(e.get("text", ""))

func current_hint() -> String:
	var e := current()
	if e.is_empty():
		return ""
	return String(e.get("hint", ""))

## 已经完成了所有目标
func is_all_done() -> bool:
	return current().is_empty()

func toast_visible() -> bool:
	return _toast_time > 0.0

func toast_text() -> String:
	return _toast_text

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(0.0, _toast_time - delta)
	if not _try_resolve():
		return
	# 一次只推进一步 —— 一帧里跳好几步的话玩家会看不懂发生了什么
	var e := current()
	if e.is_empty():
		return
	var id: String = String(e.get("id", ""))
	if _condition_met(id):
		_complete(e)

## id -> 是否达成。全部从已有状态推导，不额外记数。
func _condition_met(id: String) -> bool:
	match id:
		"plant_3":
			return player.total_planted >= 3
		"water_1":
			return player.total_watered >= 1
		"harvest_1":
			return player.total_harvested >= 1
		"sell_1":
			return player.total_earned >= 1
		"goal_300":
			return controller.goal_reached
		"mine_1":
			return MineRun.total_runs >= 1
		"boss_1":
			return MineRun.total_boss >= 1
		"goods_1":
			return player.total_goods >= 1
		"process_1":
			return player.total_processed >= 1
		"upgrade_1":
			return Upgrades.has_any()
	return false

func _complete(e: Dictionary) -> void:
	var id: String = String(e.get("id", ""))
	var text: String = String(e.get("text", id))
	done[id] = true
	var nxt: String = current_text()
	_toast_text = "✓ %s  →  下一个：%s" % [text, nxt]
	_toast_time = 3.5
	print("[目标] 完成：", text, "（", count_done(), "/", total(), "）→ 下一个：", nxt)
	Sfx.play("goal")
	step_done.emit(id, text, nxt)

# --- 存档 ---

func to_save_data() -> Dictionary:
	return {"done": done.keys()}

func apply_save_data(d: Dictionary) -> void:
	# 存档是权威：先清空再读，缺字段就退回"一个都没做"
	done.clear()
	for id in d.get("done", []):
		done[String(id)] = true
