extends Node

## 土地升级（自动加载单例，全局名字 Upgrades）。
##
## 三件东西，各自升级：**洒水器 / 肥料 / 温室**。
## 它们改的是"种田这件事本身的规则"，而不是给你更多钱 ——
## 所以玩家买了之后每天的操作会真的变少。
##
## 购买方式**没有另做 UI**：玩家把道具切到「工具箱」，站在商店按 F 就买下一级。
## 复用了现成的交互流程（切道具 → 按 F），少做一套面板。

signal upgraded(id: int, level: int)

enum Kind { SPRINKLER, FERTILIZER, GREENHOUSE }

const MAX_LEVEL: int = 3

## id → {名字, 说明, 每级价格}
const INFO: Array[Dictionary] = [
	{
		"name": "洒水器",
		"desc": "每天早上自动浇 N 株作物",
		"prices": [40, 90, 180],
	},
	{
		"name": "肥料",
		"desc": "作物长得更快（每级 -15% 时间）",
		"prices": [50, 110, 220],
	},
	{
		"name": "温室",
		"desc": "每级让每次收获多 1 个",
		"prices": [70, 150, 300],
	},
]

## 每级自动浇几株
const SPRINKLER_PER_LEVEL: int = 2
## 肥料每级让生长时间乘以多少
const FERTILIZER_STEP: float = 0.15

var levels: Array[int] = [0, 0, 0]

func name_of(id: int) -> String:
	return String(INFO[clampi(id, 0, INFO.size() - 1)]["name"])

func desc_of(id: int) -> String:
	return String(INFO[clampi(id, 0, INFO.size() - 1)]["desc"])

func level_of(id: int) -> int:
	return levels[clampi(id, 0, levels.size() - 1)]

func max_level() -> int:
	return MAX_LEVEL

func is_maxed(id: int) -> bool:
	return level_of(id) >= MAX_LEVEL

## 升下一级要多少钱；已经满级返回 -1
func next_price(id: int) -> int:
	if is_maxed(id):
		return -1
	var prices: Array = INFO[clampi(id, 0, INFO.size() - 1)]["prices"]
	return int(prices[level_of(id)])

func can_afford(player_money: int, id: int) -> bool:
	var p: int = next_price(id)
	return p >= 0 and player_money >= p

## 花钱升一级。返回有没有买成。
func buy(id: int, player_money: int) -> bool:
	if not can_afford(player_money, id):
		return false
	var idx: int = clampi(id, 0, levels.size() - 1)
	levels[idx] += 1
	upgraded.emit(idx, levels[idx])
	print("[升级] ", name_of(idx), " 升到 ", levels[idx], " 级 —— ", effect_text(idx))
	return true

## 把当前效果说成人话（日志 / UI 都能用）
func effect_text(id: int) -> String:
	match clampi(id, 0, levels.size() - 1):
		Kind.SPRINKLER:
			return "每天早上自动浇 %d 株" % sprinkler_count()
		Kind.FERTILIZER:
			return "生长时间 x%.2f" % grow_time_multiplier()
		Kind.GREENHOUSE:
			return "每次收获 +%d 个" % greenhouse_bonus()
	return ""

# --- 效果查询（别的系统读这几个）---

## 每天早上自动浇几株，0 = 没买
func sprinkler_count() -> int:
	return levels[Kind.SPRINKLER] * SPRINKLER_PER_LEVEL

## 生长时间倍率（1.0 = 没买）
func grow_time_multiplier() -> float:
	return maxf(0.25, 1.0 - FERTILIZER_STEP * float(levels[Kind.FERTILIZER]))

## 每次收获多拿几个
func greenhouse_bonus() -> int:
	return levels[Kind.GREENHOUSE]

func has_any() -> bool:
	for l in levels:
		if l > 0:
			return true
	return false

# --- 存档 ---

func to_save_data() -> Dictionary:
	return {"levels": Array(levels)}

func apply_save_data(d: Dictionary) -> void:
	# ⚠️ 先把等级清零再读。存档是权威 —— 读一份"没有这一段"的旧存档时，
	#    应该退回全 0，而不是把当前等级留着（那等于旧存档继承了新进度）。
	for i in range(levels.size()):
		levels[i] = 0
	var raw: Variant = d.get("levels", null)
	if typeof(raw) != TYPE_ARRAY:
		return
	var arr: Array = raw
	for i in range(levels.size()):
		levels[i] = clampi(int(arr[i]) if i < arr.size() else 0, 0, MAX_LEVEL)
