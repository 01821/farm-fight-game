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
	torch_left = TORCH_TIME
	run_started.emit()
	print("[矿洞] 进洞，火把 ", int(TORCH_TIME), " 秒")

## 第 depth 层的收获倍率
func loot_multiplier() -> float:
	return DEPTH_LOOT[clampi(depth - 1, 0, DEPTH_LOOT.size() - 1)]

## 第 depth 层的敌人强度倍率
func enemy_multiplier() -> float:
	return DEPTH_ENEMY[clampi(depth - 1, 0, DEPTH_ENEMY.size() - 1)]

func is_deepest() -> bool:
	return depth >= MAX_DEPTH

## 下一层。已经是最深就返回 false。
## **注意火把不会补** —— 这是整个分层的紧张感来源。
func descend() -> bool:
	if not active or is_deepest():
		return false
	depth += 1
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

## success = true 保留这趟收获；false = 丢掉（在洞里倒下了）
func finish(success: bool) -> void:
	if not active:
		return
	active = false
	_pending = {"success": success, "gold": gold, "kills": kills, "ore": ore, "boss_down": boss_down}
	print("[矿洞] 出洞 - ", "带回" if success else "丢掉",
		"这趟收获：", gold, " 金 / ", ore, " 块矿石，赶跑 ", kills, " 只",
		"，关底", "已拆" if boss_down else "没拆")
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
