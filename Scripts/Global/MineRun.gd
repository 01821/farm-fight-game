extends Node

## 矿洞「这一趟」的状态（自动加载单例，全局名字 MineRun）。
##
## **进出矿洞是靠切换场景实现的**，而农场的状态（地块、每株作物、金币…）全都活在
## base_level 场景里，一切场景就没了。解决办法是**复用已有的存档系统**：
## 进洞前先用 SaveSystem 存一次，回来时它的「启动自动读档」会把农场原样恢复。
##
## 这样不用把农场塞进 autoload，也不会丢状态 —— 而且"死在洞里丢掉这趟收获"
## 天然成立：存档是在**进洞之前**拍的。

signal run_started
signal run_finished(success: bool, gold: int, kills: int)

const FARM_SCENE: String = "res://Scenes/base_level.tscn"
const MINE_SCENE: String = "res://Scenes/Mine/mine_level.tscn"
## 一趟的火把时间（秒）。烧完自动被送回农场，**收获保留**。
const TORCH_TIME: float = 75.0

## --- 分层 ---
## 矿洞有几层。**火把是一根到底的**：下潜不补时间，
## 所以"再往下走一层，还是见好就收"是个真抉择。
const MAX_DEPTH: int = 3
## 每深一层的收获倍率（越深越肥）
const DEPTH_LOOT: Array[float] = [1.0, 1.7, 2.6]
## 每深一层，怪的强度倍率
const DEPTH_ENEMY: Array[float] = [1.0, 1.45, 2.0]

var active: bool = false
## 当前在第几层（1 起）
var depth: int = 1
## 这一趟捡到的金币
var gold: int = 0
## 这一趟挖到的矿石块数（价值已经算进 gold 里了，这个只是给结算显示用）
var ore: int = 0
## 这一趟有没有把关底 Boss 拆掉
var boss_down: bool = false
## 这一趟赶跑的怪
var kills: int = 0
## 「最近一次拆掉关底」是第几天。**跨存档持久化**，用来判断今天是不是首通。
var last_boss_day: int = -1
## 进洞那天是第几天（由矿洞口在进洞时记下）
var entry_day: int = 0
## 进洞时用的是第几号存档槽（决定地图种子）
var entry_slot: int = 1
## 这趟拆到的那件独特装备 id（给结算提示用，没拆到就是空串）
var pending_unique: String = ""
## 这趟在洞里捡到的装备 id 列表（遗物）。活着回去才到手。
var pending_items: Array[String] = []
## 每日首通关底的额外奖励
const DAILY_FIRST_GOLD: int = 30

## --- 生涯累计（**不随每趟重置**，成就靠它判断）---
var total_runs: int = 0
var total_boss: int = 0
var total_mine_kills: int = 0
## 到过的最深层数
var deepest: int = 0
## 单趟带回最多的一次
var best_run_gold: int = 0
## 这一趟有没有倒下过（"一命通关"靠它判断）
var died_this_run: bool = false
## 有几次是"一次没倒、还把关底拆了"地出来的
var flawless_runs: int = 0
var torch_left: float = 0.0
## 测试用的开关：headless 测试里不能真的切场景（一切后面就没法继续跑断言了）。
## 关掉之后 finish() 只改状态、不切场景。
var scene_switch_enabled: bool = true

var _pending: Dictionary = {}

func start_run() -> void:
	active = true
	depth = 1
	gold = 0
	ore = 0
	boss_down = false
	kills = 0
	died_this_run = false
	pending_items.clear()
	pending_unique = ""
	torch_left = TORCH_TIME
	# 生涯累计在这里加，其余的重置
	total_runs += 1
	deepest = maxi(deepest, 1)
	run_started.emit()
	print("[矿洞] 进洞（第 ", total_runs, " 趟），火把 ", int(TORCH_TIME), " 秒")

## 第 depth 层的收获倍率
func loot_multiplier() -> float:
	return DEPTH_LOOT[clampi(depth - 1, 0, DEPTH_LOOT.size() - 1)]

## 第 depth 层的敌人强度倍率
func enemy_multiplier() -> float:
	return DEPTH_ENEMY[clampi(depth - 1, 0, DEPTH_ENEMY.size() - 1)]

func is_deepest() -> bool:
	return depth >= MAX_DEPTH

## 当前这一层的地图种子。
## **同一个存档 + 同一层 = 同一张图**，换存档或换层就是新图。
func level_seed() -> int:
	return MineGen.seed_for(entry_slot, depth)

## 下一层。已经是最深就返回 false。
## **注意火把不会补** —— 这是整个分层的紧张感来源。
func descend() -> bool:
	if not active or is_deepest():
		return false
	depth += 1
	deepest = maxi(deepest, depth)
	print("[矿洞] 下到第 ", depth, " 层（收获 x", loot_multiplier(), "，火把只剩 ",
		int(torch_left), " 秒）")
	return true

func add_gold(n: int) -> void:
	if n <= 0:
		return
	# 越深越肥：倍率在这里统一乘，掉落物本身不用管自己在第几层
	gold += int(round(float(n) * loot_multiplier()))

## 矿石：价值直接算进 gold，另外记一个块数给结算显示
func add_ore(n: int) -> void:
	if n <= 0:
		return
	ore += 1
	gold += int(round(float(n) * loot_multiplier()))

func add_kill() -> void:
	kills += 1
	total_mine_kills += 1

## 在洞里捡到的**装备**（遗物）。和金币一样，**活着回去才真的到手** ——
## 在洞里倒下的话，它们跟着一起丢。这是"下矿有风险"这条线上最贵的东西。
func add_item(id: String) -> void:
	if id == "" or pending_items.has(id):
		return
	pending_items.append(id)

## 在洞里倒下了。除了结束这趟，还要记下来 ——「一命通关」成就要看它。
func mark_died() -> void:
	died_this_run = true

## success = true 保留这趟收获；false = 丢掉（在洞里倒下了）
func finish(success: bool) -> void:
	if not active:
		return
	active = false
	if success:
		best_run_gold = maxi(best_run_gold, gold)
	if boss_down:
		total_boss += 1
	# 一命通关：全程没倒下 + 拆了关底 + 活着出来
	if success and boss_down and not died_this_run:
		flawless_runs += 1
	_pending = {"success": success, "gold": gold, "kills": kills, "ore": ore, "boss_down": boss_down,
		"depth": depth, "flawless": boss_down and not died_this_run and success,
		"items": pending_items.duplicate() if success else []}
	print("[矿洞] 出洞 - ", "带回" if success else "丢掉",
		"这趟收获：", gold, " 金 / ", ore, " 块矿石，赶跑 ", kills, " 只",
		"，关底", "已拆" if boss_down else "没拆")
	if success and pending_items.size() > 0:
		for id in pending_items:
			print("[矿洞] 带回遗物：", ItemData.name_of(id))
	run_finished.emit(success, gold, kills)
	if scene_switch_enabled:
		get_tree().change_scene_to_file(FARM_SCENE)

## 回到农场后由矿洞口读取一次，然后清空（保证只结算一次）
func consume_result() -> Dictionary:
	var r := _pending
	_pending = {}
	return r

func has_result() -> bool:
	return not _pending.is_empty()

## 今天还没拆过关底吗
func can_claim_daily() -> bool:
	return boss_down and entry_day > last_boss_day

## 领走今天的首通奖励，返回领了多少（已经领过就返回 0）
func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	last_boss_day = entry_day
	print("[矿洞] 今日首通关底，额外 +", DAILY_FIRST_GOLD, " 金")
	return DAILY_FIRST_GOLD

# --- 存档 ---
# ⚠️ 只存**跨天要记住的**东西（最近一次拆关底是哪天）。
#    这一趟的 gold / depth / boss_down 都是临时状态，切场景就该没了，不该进存档。

func to_save_data() -> Dictionary:
	return {
		"last_boss_day": last_boss_day,
		"total_runs": total_runs, "total_boss": total_boss,
		"total_mine_kills": total_mine_kills, "deepest": deepest,
		"best_run_gold": best_run_gold,
		"flawless_runs": flawless_runs,
	}

func apply_save_data(d: Dictionary) -> void:
	last_boss_day = int(d.get("last_boss_day", -1))
	total_runs = maxi(0, int(d.get("total_runs", 0)))
	total_boss = maxi(0, int(d.get("total_boss", 0)))
	total_mine_kills = maxi(0, int(d.get("total_mine_kills", 0)))
	deepest = maxi(0, int(d.get("deepest", 0)))
	best_run_gold = maxi(0, int(d.get("best_run_gold", 0)))
	flawless_runs = maxi(0, int(d.get("flawless_runs", 0)))
